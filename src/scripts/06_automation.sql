-- Phase 6: Automation

USE DATABASE RIDEFLOW;
USE SCHEMA MEDALLION;

-- 1. Suspend the root task safely (Snowflake requires the root to be suspended before altering children)
EXECUTE IMMEDIATE
$$
BEGIN
  ALTER TASK MEDALLION.silver_trips_task SUSPEND;
EXCEPTION WHEN OTHER THEN
  NULL; -- Ignore if it's already suspended
END;
$$;

-- 2. Resume the child tasks in reverse order (bottom-up)
ALTER TASK MEDALLION.gold_daily_driver_earnings_task RESUME;
ALTER TASK MEDALLION.dq_gate_task RESUME;

-- 3. Finally, resume the root task to turn the entire pipeline back on
ALTER TASK MEDALLION.silver_trips_task RESUME;
