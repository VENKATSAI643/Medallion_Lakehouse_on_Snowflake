# 03 Silver Layer - Commands and Concepts Explanation

## What is the Silver Layer?
In a Medallion Architecture, the **Silver Layer** is where data gets cleaned, filtered, and refined. You take the raw, messy data from the Bronze layer, throw out or quarantine the bad records, remove duplicates, and structure it into a clean, trustworthy format. This layer becomes the "single source of truth" for your company.

---

## Detailed Code Explanation

Below is the step-by-step breakdown of the commands in `03_silver_layer.sql` in layman's terminology.

### 1. Creating the Stored Procedure
```sql
CREATE OR REPLACE PROCEDURE MEDALLION.silver_trips_proc()
...
```
**What is the use of it?**
A **Stored Procedure** is simply a reusable script or program saved directly inside Snowflake. Instead of running 5 different SQL commands manually one by one, you bundle them all into this single procedure. Later, you can execute all the logic just by calling its name.

**In Layman's Terms:** It is like recording a macro in Excel. You teach Snowflake a sequence of steps, give it a name (`silver_trips_proc`), and then you can hit "play" on it whenever you want.

---

### 2. The Transaction Block (Crucial for Streams!)
```sql
BEGIN TRANSACTION;
... [all the logic] ...
COMMIT;
```
**What is the use of it?**
Remember that **Streams** automatically "empty" themselves as soon as you use their data. 
In our logic, we need to read the stream *twice*: once to pull out the bad data, and a second time to pull out the good data. 
If we didn't use a transaction, the first read would empty the stream, and the second read would find zero data! 

**In Layman's Terms:** `BEGIN TRANSACTION` essentially pauses time. It allows you to read the stream multiple times within this safe bubble. Once you are completely done sorting the good and bad data, `COMMIT` unpauses time, finalizing the work and permanently emptying those processed records from the stream.

---

### 3. Quarantining the Bad Data
```sql
  INSERT INTO MEDALLION.silver_rejects
  SELECT s.trip_id, ..., 
         CASE WHEN dropoff_ts <= pickup_ts THEN 'BAD_TIMESTAMP_ORDER'
              WHEN fare_amount < 0 THEN 'NEGATIVE_FARE'
              WHEN z.zone_id IS NULL THEN 'UNKNOWN_ZONE'
              ELSE 'OTHER' END AS reject_reason
  FROM MEDALLION.bronze_trips_stream s ...
  WHERE dropoff_ts <= pickup_ts OR fare_amount < 0 OR z.zone_id IS NULL;
```
**What is the use of it?**
This step actively scans the new incoming data from the stream and looks for business logic errors (like a negative taxi fare, or a drop-off time that happens *before* the pickup time). It takes these bad records, tags them with a specific `reject_reason`, and dumps them into the quarantine table (`silver_rejects`). 

**In Layman's Terms:** This is the bouncer at the club checking IDs. If the data breaks the rules, the bouncer slaps a sticky note on it explaining *why* it was rejected, and tosses it into the quarantine bin so it doesn't pollute your clean data.

---

### 4. Merging the Good Data
```sql
  MERGE INTO MEDALLION.silver_trips t
  USING (
    ...
    QUALIFY ROW_NUMBER() OVER (PARTITION BY s.trip_id ORDER BY s._ingest_ts DESC) = 1
  ) src ON t.trip_id = src.trip_id
  WHEN MATCHED THEN UPDATE SET ...
  WHEN NOT MATCHED THEN INSERT ...
```
**What is the use of it?**
This handles the *good* data (positive fares, correct timestamps) and puts it into the final clean `silver_trips` table.
- **`QUALIFY ROW_NUMBER... = 1`:** This is a clever deduplication trick. If the source system accidentally sent the exact same trip twice, this formula groups them by `trip_id` and only keeps the single most recent version.
- **`MERGE INTO`:** This command looks at the Silver table. If the `trip_id` already exists (`MATCHED`), it just updates the existing record with the fresh data. If the `trip_id` is brand new (`NOT MATCHED`), it inserts it as a new row.

---

### 5. Automating it with a Task
```sql
CREATE OR REPLACE TASK MEDALLION.silver_trips_task
  WAREHOUSE = etl_wh
  SCHEDULE = '10 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('MEDALLION.bronze_trips_stream')
AS
  CALL MEDALLION.silver_trips_proc();
```
**What is the use of it?**
A **Task** is Snowflake's built-in automated scheduler (like a Cron job). This automatically runs our stored procedure on a regular cadence without a human clicking a button.

**In Layman's Terms:** 
You are hiring a robot worker. 
- You tell it to wake up every 10 minutes (`SCHEDULE = '10 MINUTE'`).
- The robot checks the stream to see if there is any new work to do (`WHEN SYSTEM$STREAM_HAS_DATA`).
- **The genius part:** If the stream is empty, the robot immediately goes back to sleep without turning on the heavy machinery (`WAREHOUSE = etl_wh`). This saves you a tremendous amount of money because you only pay for computing power when there is *actually* new data to process! 
- If there is data, it hits "play" on your macro (`CALL MEDALLION.silver_trips_proc()`).
