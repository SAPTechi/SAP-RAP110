CLASS zrap_travel_data_generate DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    INTERFACES if_oo_adt_classrun .
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS zrap_travel_data_generate IMPLEMENTATION.

  METHOD if_oo_adt_classrun~main.
    out->write( 'Starting Data Generation' ) ##NO_TEXT.

    " Delete existing entry in the database Table
    DELETE FROM zrap_travel.
    out->write( '--> Delete Travel Content.' ) ##NO_TEXT.

    out->write( 'Generate Data: Travel      /DMO/TRAVEL' ) ##NO_TEXT.

    " Insert Travel Demo Data
    INSERT zrap_travel FROM (
      SELECT FROM /dmo/travel
        FIELDS uuid( )             AS travel_uuid,
               travel_id           AS travel_id,
               agency_id           AS agency_id,
               customer_id         AS customer_id,
               begin_date          AS begin_date,
               end_date            AS end_date,
               booking_fee         AS booking_fee,
               total_price         AS total_price,
               currency_code       AS currency_code,
               description         AS description,
               CASE status
                 WHEN 'B' THEN 'A' " accepted
                 WHEN 'X' THEN 'X' " cancelled
                 ELSE 'O'          " open
               END                 AS overall_status,
               createdby           AS created_by,
               createdat           AS created_at,
               lastchangedby       AS last_changed_by,
               lastchangedat       AS last_changed_at,
               lastchangedat       AS local_last_changed_at
        ORDER BY travel_id
        UP TO 1000 ROWS ).
    COMMIT WORK.

    DELETE FROM zrap_booking_a.
    out->write( '--> Delete Booking Content.' ) ##NO_TEXT.

    out->write( 'Generate Data: Booking      /DMO/BOOKING' ) ##NO_TEXT.

    " Insert Booking Demo Data
    INSERT zrap_booking_A FROM (
        SELECT
          FROM /dmo/booking AS booking
                 JOIN
                   zrap_travel AS z ON booking~travel_id = z~travel_id
          FIELDS uuid( )               AS booking_uuid,
                 z~travel_uuid         AS travel_uuid,
                 booking~booking_id    AS booking_id,
                 booking~booking_date  AS booking_date,
                 booking~customer_id   AS customer_id,
                 booking~carrier_id    AS carrier_id,
                 booking~connection_id AS connection_id,
                 booking~flight_date   AS flight_date,
                 booking~flight_price  AS flight_price,
                 booking~currency_code AS currency_code,
                 z~created_by          AS created_by,
                 z~last_changed_by     AS last_changed_by,
                 z~last_changed_at     AS local_last_changed_by ).
    COMMIT WORK.

    out->write( 'Travel and booking demo data inserted.' ).

    DELETE FROM zrap_userprofile.

    data: ls_userprofile TYPE zrap_userprofile.
    ls_userprofile = VALUE #( uname = sy-uname first_name = 'Ghost' last_name = 'Shadow' ).

    MODIFY zrap_userprofile from @ls_userprofile.

  ENDMETHOD.
ENDCLASS.
