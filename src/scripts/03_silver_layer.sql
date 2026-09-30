-- Phase 3: Data Cleaning (Silver Layer)

USE DATABASE RIDEFLOW;
USE SCHEMA MEDALLION;

-- 1. Create the Stored Procedure for the Silver logic
CREATE OR REPLACE PROCEDURE MEDALLION.silver_trips_proc()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
  -- Snowflake consumes streams upon DML. We MUST wrap multiple DMLs in a transaction
  -- so both the INSERT and the MERGE can see the exact same stream data!
  BEGIN TRANSACTION;

  -- Route bad data to the rejects table
  INSERT INTO MEDALLION.silver_rejects
  SELECT s.trip_id, s.driver_id, s.rider_id, s.pickup_ts, s.dropoff_ts, s.pickup_zone_id, 
         s.dropoff_zone_id, s.distance_miles, s.fare_amount, s.tip_amount, s.payment_type, 
         s._ingest_ts, s._batch_id, s._source_table,
         CASE WHEN dropoff_ts <= pickup_ts THEN 'BAD_TIMESTAMP_ORDER'
              WHEN fare_amount < 0 THEN 'NEGATIVE_FARE'
              WHEN z.zone_id IS NULL THEN 'UNKNOWN_ZONE'
              ELSE 'OTHER' END AS reject_reason,
         CURRENT_TIMESTAMP()
  FROM MEDALLION.bronze_trips_stream s
  LEFT JOIN MEDALLION.silver_zones z ON z.zone_id = s.pickup_zone_id
  WHERE dropoff_ts <= pickup_ts OR fare_amount < 0 OR z.zone_id IS NULL;

  -- Clean data is merged and deduplicated
  MERGE INTO MEDALLION.silver_trips t
  USING (
    SELECT s.* FROM MEDALLION.bronze_trips_stream s
    JOIN MEDALLION.silver_zones z ON z.zone_id = s.pickup_zone_id
    WHERE s.dropoff_ts > s.pickup_ts AND s.fare_amount >= 0
    QUALIFY ROW_NUMBER() OVER (PARTITION BY s.trip_id ORDER BY s._ingest_ts DESC) = 1
  ) src ON t.trip_id = src.trip_id
  WHEN MATCHED THEN UPDATE SET 
    t.pickup_ts = src.pickup_ts,
    t.dropoff_ts = src.dropoff_ts,
    t.fare_amount = src.fare_amount,
    t.tip_amount = src.tip_amount
  WHEN NOT MATCHED THEN INSERT (
    trip_id, driver_id, pickup_ts, dropoff_ts, fare_amount, tip_amount
  ) VALUES (
    src.trip_id, src.driver_id, src.pickup_ts, src.dropoff_ts, src.fare_amount, src.tip_amount
  );
  
  COMMIT;
  RETURN 'SUCCESS';
END;
$$;

-- 2. Create the Silver Task to call the procedure
CREATE OR REPLACE TASK MEDALLION.silver_trips_task
  WAREHOUSE = etl_wh
  SCHEDULE = '10 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('MEDALLION.bronze_trips_stream')
AS
  CALL MEDALLION.silver_trips_proc();
