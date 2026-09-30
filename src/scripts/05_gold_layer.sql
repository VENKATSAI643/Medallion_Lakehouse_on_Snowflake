-- Phase 5: Business Intelligence (Gold Layer)

USE DATABASE RIDEFLOW;
USE SCHEMA MEDALLION;

-- 1. Create a Gold Mart Task
-- (Since this is a single statement, we don't need a procedure)
CREATE TASK MEDALLION.gold_daily_driver_earnings_task
  WAREHOUSE = bi_wh
  AFTER MEDALLION.dq_gate_task
AS
  MERGE INTO MEDALLION.gold_daily_driver_earnings g
  USING (
    SELECT 
      driver_id, 
      DATE(dropoff_ts) AS trip_date, 
      SUM(fare_amount) AS total_fare, 
      SUM(tip_amount) AS total_tips,
      COUNT(trip_id) AS total_trips
    FROM MEDALLION.silver_trips
    -- Use a stream on silver_trips in production to only aggregate new records
    GROUP BY driver_id, DATE(dropoff_ts)
  ) src ON g.driver_id = src.driver_id AND g.trip_date = src.trip_date
  WHEN MATCHED THEN UPDATE SET 
    g.total_fare = g.total_fare + src.total_fare,
    g.total_tips = g.total_tips + src.total_tips,
    g.total_trips = g.total_trips + src.total_trips
  WHEN NOT MATCHED THEN INSERT (driver_id, trip_date, total_fare, total_tips, total_trips)
  VALUES (src.driver_id, src.trip_date, src.total_fare, src.total_tips, src.total_trips);
