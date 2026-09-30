-- Phase 7: Advanced Analytics & Monitoring

USE DATABASE RIDEFLOW;
USE SCHEMA MEDALLION;

-- 1. View Task Execution History
-- This query shows you the success, failure, and execution time of your task graph runs over the last 7 days.
SELECT 
    STATE,
    ERROR_MESSAGE,
    SCHEDULED_TIME,
    COMPLETED_TIME,
    ROOT_TASK_ID,
    NAME AS TASK_NAME
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('day', -7, CURRENT_TIMESTAMP()),
    RESULT_LIMIT => 100))
ORDER BY SCHEDULED_TIME DESC;

-- 2. Verify Data Lineage (Optional Feature)
-- If you have Snowflake's Data Lineage features enabled, you can trace data dependencies natively.
SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.ACCESS_HISTORY 
WHERE OBJECT_MODIFIED_BY_DDL:objectName = 'MEDALLION.GOLD_DAILY_DRIVER_EARNINGS';
