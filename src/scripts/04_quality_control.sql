-- Phase 4: Quality Control (The Gate)

USE DATABASE RIDEFLOW;
USE SCHEMA MEDALLION;

-- 1. Create the Stored Procedure for the Data Quality Gate
CREATE OR REPLACE PROCEDURE MEDALLION.dq_gate_proc()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE 
  reject_rate FLOAT; 
  bad_dq EXCEPTION (-20001, 'DQ gate failed: Reject rate too high');
BEGIN
  -- Calculate rejection rate
  SELECT COUNT_IF(reject_reason IS NOT NULL) / NULLIF(COUNT(*),0) INTO :reject_rate
  FROM (
      SELECT reject_reason FROM MEDALLION.silver_rejects WHERE DATE(inserted_at) = CURRENT_DATE()
      UNION ALL
      SELECT NULL AS reject_reason FROM MEDALLION.silver_trips WHERE DATE(inserted_at) = CURRENT_DATE()
  );
  
  -- Circuit Breaker Threshold (e.g. 2%)
  IF (reject_rate > 0.02) THEN 
    RAISE bad_dq; 
  END IF;
  
  RETURN 'PASSED';
END;
$$;

-- 2. Create the Data Quality Gate Task
CREATE TASK MEDALLION.dq_gate_task 
  WAREHOUSE = etl_wh 
  AFTER MEDALLION.silver_trips_task 
AS
  CALL MEDALLION.dq_gate_proc();
