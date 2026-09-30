-- Phase 2: The Raw Data (Bronze Layer)

USE DATABASE RIDEFLOW;
USE SCHEMA MEDALLION;

-- 1. Create the Bronze Table
CREATE ICEBERG TABLE MEDALLION.bronze_trips (
  trip_id STRING, driver_id STRING, rider_id STRING,
  pickup_ts TIMESTAMP_NTZ(6), dropoff_ts TIMESTAMP_NTZ(6),
  pickup_zone_id INT, dropoff_zone_id INT,
  distance_miles FLOAT, fare_amount NUMBER(10,2), tip_amount NUMBER(10,2),
  payment_type STRING,
  _ingest_ts TIMESTAMP_NTZ(6), _batch_id STRING, _source_table STRING
)
CATALOG = 'SNOWFLAKE'
EXTERNAL_VOLUME = 'rideflow_vol_azure'
BASE_LOCATION = 'bronze/trips/';

-- 2. Create the Data Stream
CREATE STREAM MEDALLION.bronze_trips_stream ON TABLE MEDALLION.bronze_trips;
