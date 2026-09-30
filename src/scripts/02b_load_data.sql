USE DATABASE RIDEFLOW;
USE SCHEMA MEDALLION;

-- 1. Create the Missing Silver and Gold Tables
CREATE TABLE IF NOT EXISTS silver_zones (
  zone_id INT,
  zone_name STRING,
  borough STRING,
  _ingest_ts TIMESTAMP_NTZ(6)
);

CREATE TABLE IF NOT EXISTS silver_rejects (
  trip_id STRING, driver_id STRING, rider_id STRING,
  pickup_ts TIMESTAMP_NTZ(6), dropoff_ts TIMESTAMP_NTZ(6),
  pickup_zone_id INT, dropoff_zone_id INT,
  distance_miles FLOAT, fare_amount NUMBER(10,2), tip_amount NUMBER(10,2),
  payment_type STRING,
  _ingest_ts TIMESTAMP_NTZ(6), _batch_id STRING, _source_table STRING,
  reject_reason STRING,
  inserted_at TIMESTAMP_NTZ(6)
);

CREATE OR REPLACE TABLE silver_trips (
  trip_id STRING, driver_id STRING, 
  pickup_ts TIMESTAMP_NTZ(6), dropoff_ts TIMESTAMP_NTZ(6), 
  fare_amount NUMBER(10,2), tip_amount NUMBER(10,2),
  inserted_at TIMESTAMP_NTZ DEFAULT SYSDATE()
);

CREATE OR REPLACE TABLE gold_daily_driver_earnings (
  driver_id STRING,
  trip_date DATE,
  total_fare NUMBER(10,2),
  total_tips NUMBER(10,2),
  total_trips INT
);

-- 2. Create a temporary staging area to upload local files
CREATE OR REPLACE TEMPORARY STAGE local_upload_stage FILE_FORMAT = (TYPE = PARQUET);

-- 3. Upload the Parquet files from your WSL machine into Snowflake's stage
PUT file:///mnt/e/Snowflake/Kimball_Star_Schema/output/raw_trips.parquet @local_upload_stage AUTO_COMPRESS=FALSE;
PUT file:///mnt/e/Snowflake/Kimball_Star_Schema/output/raw_zones.parquet @local_upload_stage AUTO_COMPRESS=FALSE;

-- 4. Clear old bad data and ingest the staged trips into the Bronze Iceberg Table
TRUNCATE TABLE bronze_trips;

COPY INTO bronze_trips (
  trip_id, driver_id, rider_id, pickup_ts, dropoff_ts, pickup_zone_id, dropoff_zone_id, 
  distance_miles, fare_amount, tip_amount, payment_type
)
FROM (
  SELECT 
    $1:trip_id::STRING, $1:driver_id::STRING, $1:rider_id::STRING,
    $1:pickup_datetime::TIMESTAMP_NTZ, $1:dropoff_datetime::TIMESTAMP_NTZ,
    $1:pickup_location_id::INT, $1:dropoff_location_id::INT,
    $1:trip_distance::FLOAT, $1:fare_amount::NUMBER(10,2), $1:tip_amount::NUMBER(10,2),
    $1:payment_type::STRING
  FROM @local_upload_stage/raw_trips.parquet
)
MATCH_BY_COLUMN_NAME = NONE;

-- 5. Clear and ingest the staged zones into the Silver Zones reference table
TRUNCATE TABLE silver_zones;

COPY INTO silver_zones (zone_id, zone_name, borough, _ingest_ts)
FROM (
  SELECT $1:location_id::INT, $1:zone::STRING, $1:borough::STRING, CURRENT_TIMESTAMP()
  FROM @local_upload_stage/raw_zones.parquet
);
