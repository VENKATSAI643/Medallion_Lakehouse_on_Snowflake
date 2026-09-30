USE DATABASE RIDEFLOW;
USE SCHEMA MEDALLION;

-- 1. Force the automated pipeline to wake up and run immediately
EXECUTE TASK MEDALLION.silver_trips_task;

-- 2. (Optional) You can check the task history to ensure it's running
SELECT 
    STATE,
    ERROR_MESSAGE,
    SCHEDULED_TIME,
    COMPLETED_TIME,
    NAME AS TASK_NAME
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('day', -1, CURRENT_TIMESTAMP()),
    RESULT_LIMIT => 10))
ORDER BY SCHEDULED_TIME DESC;
