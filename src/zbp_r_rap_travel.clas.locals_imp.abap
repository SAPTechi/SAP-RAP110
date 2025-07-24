

CLASS lhc_travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    CONSTANTS:
      BEGIN OF travel_status,
        open     TYPE c LENGTH 1 VALUE 'O', " Open
        accepted TYPE c LENGTH 1 VALUE 'A', " Accepted
        canceled TYPE c LENGTH 1 VALUE 'X', " Cancelled
      END OF travel_status.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR travel RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR travel RESULT result.

    METHODS accepttravel FOR MODIFY
      IMPORTING keys FOR ACTION travel~accepttravel RESULT result.

    METHODS recalctotalprice FOR MODIFY
      IMPORTING keys FOR ACTION travel~recalctotalprice.

    METHODS rejecttravel FOR MODIFY
      IMPORTING keys FOR ACTION travel~rejecttravel RESULT result.

    METHODS calculatetotalprice FOR DETERMINE ON MODIFY
      IMPORTING keys FOR travel~calculatetotalprice.

    METHODS setinitialstatus FOR DETERMINE ON MODIFY
      IMPORTING keys FOR travel~setinitialstatus.

    METHODS calculatetravelid FOR DETERMINE ON SAVE
      IMPORTING keys FOR travel~calculatetravelid.

    METHODS validateagency FOR VALIDATE ON SAVE
      IMPORTING keys FOR travel~validateagency.

    METHODS validatecustomer FOR VALIDATE ON SAVE
      IMPORTING keys FOR travel~validatecustomer.

    METHODS validatedates FOR VALIDATE ON SAVE
      IMPORTING keys FOR travel~validatedates.
    METHODS updateuser FOR MODIFY
      IMPORTING keys FOR ACTION travel~updateuser.


ENDCLASS.


CLASS lhc_travel IMPLEMENTATION.
  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD get_instance_features.
    " Read the travel status of the existing travels
    READ ENTITIES OF zr_rap_travel IN LOCAL MODE
         ENTITY Travel
         FIELDS ( OverallStatus ) WITH CORRESPONDING #( keys )
         RESULT DATA(travels)
         FAILED failed.

    result =
      VALUE #( FOR travel IN travels
               LET is_accepted = COND #( WHEN travel-OverallStatus = travel_status-accepted
                                         THEN if_abap_behv=>fc-o-disabled
                                         ELSE if_abap_behv=>fc-o-enabled  )
                   is_rejected = COND #( WHEN travel-OverallStatus = travel_status-canceled
                                         THEN if_abap_behv=>fc-o-disabled
                                         ELSE if_abap_behv=>fc-o-enabled )
               IN
                   ( %tky                 = travel-%tky
                     %action-acceptTravel = is_accepted
                     %action-rejectTravel = is_rejected

                     %field-BookingFee    = COND #( WHEN travel-OverallStatus = travel_status-accepted
                                                    THEN if_abap_behv=>fc-f-read_only
                                                    ELSE if_abap_behv=>fc-f-unrestricted  )
                     %assoc-_Booking      = COND #( WHEN travel-OverallStatus = travel_status-canceled
                                                    THEN if_abap_behv=>fc-o-enabled
                                                    ELSE if_abap_behv=>fc-o-disabled  ) ) ).
  ENDMETHOD.

  METHOD accepttravel.
    " Set the new overall status
    MODIFY ENTITIES OF zr_rap_travel IN LOCAL MODE
           ENTITY travel
           UPDATE
           FIELDS ( overallstatus )
           WITH VALUE #( FOR key IN keys
                         ( %tky          = key-%tky
                           OverallStatus = travel_status-accepted ) )
           FAILED failed
           REPORTED reported.

    " Fill the response table
    READ ENTITIES OF zr_rap_travel IN LOCAL MODE
         ENTITY travel
         ALL FIELDS WITH CORRESPONDING #( keys )
         RESULT DATA(travels).

    result = VALUE #( FOR travel IN travels
                      ( %tky   = travel-%tky
                        %param = travel ) ).
  ENDMETHOD.

  METHOD rejecttravel.
    " Set the new overall status
    MODIFY ENTITIES OF zr_rap_travel IN LOCAL MODE
           ENTITY travel
           UPDATE
           FIELDS ( overallstatus )
           WITH VALUE #( FOR key IN keys
                         ( %tky          = key-%tky
                           OverallStatus = travel_status-canceled ) )
           FAILED failed
           REPORTED reported.

    " Fill the response table
    READ ENTITIES OF zr_rap_travel IN LOCAL MODE
         ENTITY travel
         ALL FIELDS WITH CORRESPONDING #( keys )
         RESULT DATA(travels).

    result = VALUE #( FOR travel IN travels
                      ( %tky   = travel-%tky
                        %param = travel ) ).
  ENDMETHOD.

  METHOD calculatetravelid.
    " check if TravelID is already filled
    READ ENTITIES OF zr_rap_travel IN LOCAL MODE
         ENTITY travel
         FIELDS ( travelid ) WITH CORRESPONDING #( keys )
         RESULT DATA(travels).

    " remove lines where TravelID is already filled.
    DELETE travels WHERE travelid IS NOT INITIAL.

    " anything left ?
    IF travels IS INITIAL.
      RETURN.
    ENDIF.

    " Select max travel ID
    SELECT SINGLE FROM zrap_travel_a
      FIELDS MAX( travel_id ) AS travelid
      INTO @DATA(max_travelid).

    " Set the travel ID
    MODIFY ENTITIES OF zr_rap_travel IN LOCAL MODE
           ENTITY travel
           UPDATE
           FROM VALUE #( FOR travel IN travels INDEX INTO i
                         ( %tky              = travel-%tky
                           travelid          = max_travelid + i
                           %control-travelid = if_abap_behv=>mk-on ) )
           REPORTED DATA(update_reported).

    reported = CORRESPONDING #( DEEP update_reported ).
  ENDMETHOD.

  METHOD setinitialstatus.
    " Read relevant travel instance data
    READ ENTITIES OF zr_rap_travel IN LOCAL MODE
         ENTITY travel
         FIELDS ( overallstatus ) WITH CORRESPONDING #( keys )
         RESULT DATA(travels).

    " Remove all travel instance data with defined status
    DELETE travels WHERE overallstatus IS NOT INITIAL.
    IF travels IS INITIAL.
      RETURN.
    ENDIF.

    " Set default travel status
    MODIFY ENTITIES OF zr_rap_travel IN LOCAL MODE
           ENTITY travel
           UPDATE
           FIELDS ( overallstatus )
           WITH VALUE #( FOR travel IN travels
                         ( %tky          = travel-%tky
                           OverallStatus = travel_status-open ) )
           REPORTED DATA(update_reported).

    reported = CORRESPONDING #( DEEP update_reported ).
  ENDMETHOD.

  METHOD calculatetotalprice.
    MODIFY ENTITIES OF zr_rap_travel IN LOCAL MODE
           ENTITY travel
           EXECUTE recalctotalprice
           FROM CORRESPONDING #( keys )
           REPORTED DATA(execute_reported).

    reported = CORRESPONDING #( DEEP execute_reported ).
  ENDMETHOD.

  METHOD recalctotalprice.
    TYPES: BEGIN OF ty_amount_per_currencycode,
             amount        TYPE /dmo/total_price,
             currency_code TYPE /dmo/currency_code,
           END OF ty_amount_per_currencycode.

    DATA: amount_per_currencycode TYPE STANDARD TABLE OF ty_amount_per_currencycode.

    " Read all relevant travel instances.
    READ ENTITIES OF zr_rap_travel IN LOCAL MODE
         ENTITY travel
         FIELDS ( bookingfee currencycode )
         WITH CORRESPONDING #( keys )
         RESULT DATA(travels).

    DELETE travels WHERE currencycode IS INITIAL.

    LOOP AT travels ASSIGNING FIELD-SYMBOL(<travel>).
      " Set the start for the calculation by adding the booking fee.
      amount_per_currencycode = VALUE #( ( amount        = <travel>-BookingFee
                                           currency_code = <travel>-CurrencyCode ) ).

      " Read all associated bookings and add them to the total price.
      READ ENTITIES OF zr_rap_travel IN LOCAL MODE
           ENTITY travel BY \_booking
           FIELDS ( flightprice currencycode )
           WITH VALUE #( ( %tky = <travel>-%tky ) )
           RESULT DATA(bookings).

      LOOP AT bookings INTO DATA(booking) WHERE CurrencyCode IS NOT INITIAL.
        COLLECT VALUE ty_amount_per_currencycode( amount        = booking-FlightPrice
                                                  currency_code = booking-CurrencyCode ) INTO amount_per_currencycode.
      ENDLOOP.

      CLEAR <travel>-TotalPrice.
      LOOP AT amount_per_currencycode INTO DATA(single_amount_per_currencycode).
        " If needed do a Currency Conversion
        IF single_amount_per_currencycode-currency_code = <travel>-CurrencyCode.
          <travel>-TotalPrice += single_amount_per_currencycode-amount.
        ELSE.
          /dmo/cl_flight_amdp=>convert_currency( EXPORTING
                                                   iv_amount               = single_amount_per_currencycode-amount
                                                   iv_currency_code_source = single_amount_per_currencycode-currency_code
                                                   iv_currency_code_target = <travel>-CurrencyCode
                                                   iv_exchange_rate_date   = cl_abap_context_info=>get_system_date( )
                                                 IMPORTING
                                                   ev_amount               = DATA(total_booking_price_per_curr) ).
          <travel>-TotalPrice += total_booking_price_per_curr.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    " write back the modified total_price of travels
    MODIFY ENTITIES OF zr_rap_travel IN LOCAL MODE
           ENTITY travel
           UPDATE FIELDS ( totalprice )
           WITH CORRESPONDING #( travels ).
  ENDMETHOD.

  METHOD validateagency.
    " Read relevant travel instance data

    DATA agencies TYPE SORTED TABLE OF /dmo/agency WITH UNIQUE KEY agency_id.

    READ ENTITIES OF zr_rap_travel IN LOCAL MODE
         ENTITY travel
         FIELDS ( agencyid ) WITH CORRESPONDING #( keys )
         RESULT DATA(travels).

    " Optimization of DB select: extract distinct non-initial agency IDs
    agencies = CORRESPONDING #( travels DISCARDING DUPLICATES MAPPING agency_id = agencyid EXCEPT * ).
    DELETE agencies WHERE agency_id IS INITIAL.

    IF agencies IS NOT INITIAL.
      " Check if agency ID exist
      SELECT FROM /dmo/agency
        FIELDS agency_id
        FOR ALL ENTRIES IN @agencies
        WHERE agency_id = @agencies-agency_id
        INTO TABLE @DATA(agencies_db).
    ENDIF.

    " Raise msg for non existing and initial agencyID
    LOOP AT travels INTO DATA(travel).
      " Clear state messages that might exist
      APPEND VALUE #( %tky        = travel-%tky
                      %state_area = 'VALIDATE_AGENCY' )
             TO reported-travel.

      IF travel-agencyid IS NOT INITIAL AND line_exists( agencies_db[ agency_id = travel-agencyid ] ).
        CONTINUE.
      ENDIF.

      APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.

      APPEND VALUE #( %tky              = travel-%tky
                      %state_area       = 'VALIDATE_AGENCY'
                      %msg              = NEW zcm_rap_demo_travel( severity = if_abap_behv_message=>severity-error
                                                                   textid   = zcm_rap_demo_travel=>agency_unknown
                                                                   agencyid = travel-agencyid )
                      %element-agencyid = if_abap_behv=>mk-on )
             TO reported-travel.
    ENDLOOP.
  ENDMETHOD.

  METHOD validatecustomer.
    " Read relevant travel instance data

    DATA customers TYPE SORTED TABLE OF /dmo/customer WITH UNIQUE KEY customer_id.

    READ ENTITIES OF zr_rap_travel IN LOCAL MODE
         ENTITY travel
         FIELDS ( customerid ) WITH CORRESPONDING #( keys )
         RESULT DATA(travels).

    " Optimization of DB select: extract distinct non-initial customer IDs
    customers = CORRESPONDING #( travels DISCARDING DUPLICATES MAPPING customer_id = customerid EXCEPT * ).
    DELETE customers WHERE customer_id IS INITIAL.
    IF customers IS NOT INITIAL.
      " Check if customer ID exist
      SELECT FROM /dmo/customer
        FIELDS customer_id
        FOR ALL ENTRIES IN @customers
        WHERE customer_id = @customers-customer_id
        INTO TABLE @DATA(customers_db).
    ENDIF.

    " Raise msg for non existing and initial customerID
    LOOP AT travels INTO DATA(travel).
      " Clear state messages that might exist
      APPEND VALUE #( %tky        = travel-%tky
                      %state_area = 'VALIDATE_CUSTOMER' )
             TO reported-travel.

      IF travel-customerid IS NOT INITIAL AND line_exists( customers_db[ customer_id = travel-customerid ] ).
        CONTINUE.
      ENDIF.

      APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.

      APPEND VALUE #( %tky                = travel-%tky
                      %state_area         = 'VALIDATE_CUSTOMER'
                      %msg                = NEW zcm_rap_demo_travel( severity   = if_abap_behv_message=>severity-error
                                                                     textid     = zcm_rap_demo_travel=>customer_unknown
                                                                     customerid = travel-customerid )
                      %element-customerid = if_abap_behv=>mk-on )
             TO reported-travel.
    ENDLOOP.
  ENDMETHOD.

  METHOD validatedates.
    READ ENTITIES OF zr_rap_travel IN LOCAL MODE
         ENTITY Travel
         FIELDS ( TravelID BeginDate EndDate ) WITH CORRESPONDING #( keys )
         RESULT DATA(travels).

    LOOP AT travels INTO DATA(travel).
      " Clear state messages that might exist
      APPEND VALUE #( %tky        = travel-%tky
                      %state_area = 'VALIDATE_DATES' )
             TO reported-travel.

      IF travel-EndDate < travel-BeginDate.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                        %msg               = NEW zcm_rap_demo_travel( severity  = if_abap_behv_message=>severity-error
                                                                      textid    = zcm_rap_demo_travel=>date_interval
                                                                      begindate = travel-BeginDate
                                                                      enddate   = travel-EndDate
                                                                      travelid  = travel-TravelID )
                        %element-BeginDate = if_abap_behv=>mk-on
                        %element-EndDate   = if_abap_behv=>mk-on ) TO reported-travel.

      ELSEIF travel-BeginDate < cl_abap_context_info=>get_system_date( ).
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.
        APPEND VALUE #( %tky               = travel-%tky
                        %state_area        = 'VALIDATE_DATES'
                        %msg               = NEW zcm_rap_demo_travel(
                                                     severity  = if_abap_behv_message=>severity-error
                                                     textid    = zcm_rap_demo_travel=>begin_date_before_system_date
                                                     begindate = travel-BeginDate )
                        %element-BeginDate = if_abap_behv=>mk-on ) TO reported-travel.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD updateuser.

   DATA(l) = 1.


  ENDMETHOD.

ENDCLASS.


CLASS lhc_booking DEFINITION INHERITING FROM cl_abap_behavior_handler.

  PRIVATE SECTION.
    METHODS calculatebookingid FOR DETERMINE ON MODIFY
      IMPORTING keys FOR booking~calculatebookingid.

    METHODS calculatetotalprice FOR DETERMINE ON MODIFY
      IMPORTING keys FOR booking~calculatetotalprice.

ENDCLASS.


CLASS lhc_booking IMPLEMENTATION.
  METHOD calculatebookingid.
    DATA: max_bookingid TYPE /dmo/booking_id,
          update        TYPE TABLE FOR UPDATE zr_rap_travel\\booking. "\\ Signifies a child entity or a composition - Sangeeth

    " Read all travels for the requested bookings.
    " If multiple bookings of the same travel are requested, the travel is returned only once.
    READ ENTITIES OF zr_rap_travel IN LOCAL MODE
         ENTITY booking BY \_travel
         FIELDS ( traveluuid )
         WITH CORRESPONDING #( keys )
         RESULT DATA(travels).

    " Process all affected Travels. Read respective bookings, determine the max-id and update the bookings without ID.
    LOOP AT travels INTO DATA(travel).
      READ ENTITIES OF zr_rap_travel IN LOCAL MODE
           ENTITY travel BY \_booking
           FIELDS ( bookingid )
           WITH VALUE #( ( %tky = travel-%tky ) )
           RESULT DATA(bookings).

      " Find max used BookingID in all bookings of this travel
      max_bookingid = '0000'.
      LOOP AT bookings INTO DATA(booking).
        IF booking-bookingid > max_bookingid.
          max_bookingid = booking-bookingid.
        ENDIF.
      ENDLOOP.

      " Provide a booking ID for all bookings that have none.
      LOOP AT bookings INTO booking WHERE bookingid IS INITIAL.
        max_bookingid += 10.
        APPEND VALUE #( %tky      = booking-%tky
                        bookingid = max_bookingid )
               TO update.
      ENDLOOP.
    ENDLOOP.

    " Update the Booking ID of all relevant bookings
    MODIFY ENTITIES OF zr_rap_travel IN LOCAL MODE
           ENTITY booking
           UPDATE FIELDS ( bookingid ) WITH update
           REPORTED DATA(update_reported).

    reported = CORRESPONDING #( DEEP update_reported ).
  ENDMETHOD.

  METHOD calculatetotalprice.
    " Read all travels for the requested bookings.
    " If multiple bookings of the same travel are requested, the travel is returned only once.
    READ ENTITIES OF zr_rap_travel IN LOCAL MODE
         ENTITY booking BY \_travel
         FIELDS ( traveluuid )
         WITH CORRESPONDING #( keys )
         RESULT DATA(travels)
         " TODO: variable is assigned but never used (ABAP cleaner)
         FAILED DATA(read_failed).

    " Trigger calculation of the total price
    MODIFY ENTITIES OF zr_rap_travel IN LOCAL MODE
           ENTITY travel
           EXECUTE recalctotalprice
           FROM CORRESPONDING #( travels )
           REPORTED DATA(execute_reported).

    reported = CORRESPONDING #( DEEP execute_reported ).
  ENDMETHOD.
ENDCLASS.
