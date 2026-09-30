# Detailed SQL Code Walkthrough

This document breaks down the actual SQL code from each script in the `src/scripts/` directory, explaining the logic, syntax, and Snowflake-specific features used line-by-line.

---

## 00_database_setup.sql
This script prepares the foundation of the Snowflake environment.

```sql
CREATE DATABASE IF NOT EXISTS RIDEFLOW;
CREATE SCHEMA IF NOT EXISTS RIDEFLOW.MEDALLION;
```
* **`IF NOT EXISTS`**: A safe deployment practice. It ensures that running this script multiple times is idempotent (it won't crash if the database already exists).
* **`SCHEMA`**: Schemas act as folders within a database to organize tables. We isolate our project in the `MEDALLION` schema.

```sql
CREATE WAREHOUSE IF NOT EXISTS ETL_WH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60;
CREATE WAREHOUSE IF NOT EXISTS BI_WH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60;
```
* **`WAREHOUSE_SIZE = 'XSMALL'`**: Provisions a single cluster of compute. XSMALL is the cheapest size (1 credit/hour).
* **`AUTO_SUSPEND = 60`**: This is a critical cost-saving feature. If no queries hit the warehouse for 60 seconds, Snowflake completely shuts it down, so you stop paying for it.
* **Separation of Compute**: We create `ETL_WH` for background data loading, and `BI_WH` for dashboard queries, ensuring heavy data processing doesn't slow down business reports.

---

## 01_storage_setup.sql
This script connects Snowflake to the external Azure Blob container.

```sql
CREATE OR REPLACE EXTERNAL VOLUME rideflow_vol_azure
  STORAGE_LOCATIONS = (
    (
      NAME = 'azure_location',
      STORAGE_PROVIDER = 'AZURE',
      STORAGE_BASE_URL = 'azure://<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net/<CONTAINER>/',
      AZURE_TENANT_ID = '<YOUR_AZURE_TENANT_ID>'
    )
  );
```
* **`EXTERNAL VOLUME`**: A Snowflake object that securely stores credentials and paths to an external cloud storage bucket (AWS S3, Azure Blob, or Google Cloud Storage).
* **`STORAGE_BASE_URL`**: The exact URI of the Azure container where the physical Iceberg Parquet files will be written.

---

## 02_bronze_layer.sql
This script defines the raw landing zone.

```sql
CREATE OR REPLACE ICEBERG TABLE MEDALLION.bronze_trips ( ... )
  CATALOG = 'SNOWFLAKE'
  EXTERNAL_VOLUME = 'rideflow_vol_azure'
  BASE_LOCATION = 'bronze_trips/';
```
* **`ICEBERG TABLE`**: Unlike standard Snowflake tables, Iceberg tables store their data files in open Parquet format in your Azure container, avoiding Snowflake storage lock-in.
* **`CATALOG = 'SNOWFLAKE'`**: Tells Snowflake that it has write access and full control over managing the Iceberg metadata.

```sql
CREATE STREAM MEDALLION.bronze_trips_stream 
ON TABLE MEDALLION.bronze_trips 
APPEND_ONLY = TRUE;
```
* **`STREAM`**: Snowflake's native Change Data Capture (CDC) mechanism. It acts as a bookmark, recording exactly which rows were inserted since the last time the stream was consumed.
* **`APPEND_ONLY = TRUE`**: Optimizes the stream to only track `INSERT` operations (since Bronze is an append-only raw layer).

---

## 02b_load_data.sql
This script creates downstream tables and manually loads local files into Snowflake.

```sql
CREATE OR REPLACE TEMPORARY STAGE local_upload_stage FILE_FORMAT = (TYPE = PARQUET);
PUT file:///mnt/e/.../raw_trips.parquet @local_upload_stage AUTO_COMPRESS=FALSE;
```
* **`TEMPORARY STAGE`**: A scratchpad space in Snowflake used temporarily to hold uploaded files.
* **`PUT`**: A special SnowSQL CLI command that physically uploads a file from your local computer (`file://`) into the Snowflake stage (`@local_upload_stage`).

```sql
COPY INTO bronze_trips (...)
FROM (
  SELECT $1:pickup_datetime::TIMESTAMP_NTZ, ...
  FROM @local_upload_stage/raw_trips.parquet
)
MATCH_BY_COLUMN_NAME = NONE;
```
* **`COPY INTO`**: Flushes the data from the stage into the actual table. Because `bronze_trips` is an Iceberg table, Snowflake simultaneously writes the underlying Parquet files out to Azure.
* **`$1:column_name::TYPE`**: Parquet files are treated as semi-structured variants (like JSON) in Snowflake stages. `$1` refers to the first column (the variant object). We explicitly extract and cast each field (e.g., `::TIMESTAMP_NTZ`) because the original Parquet column names differed from our table schema.

---

## 03_silver_layer.sql
This script implements data cleansing using a Stored Procedure and a Task.

```sql
CREATE OR REPLACE PROCEDURE MEDALLION.silver_trips_proc()
...
BEGIN
  BEGIN TRANSACTION;
```
* **`BEGIN TRANSACTION;`**: A critical requirement because Snowflake consumes (empties) streams upon DML execution. By wrapping both the `INSERT` and `MERGE` statements in a single transaction, both queries can read the exact same snapshot of the stream.

```sql
  INSERT INTO MEDALLION.silver_rejects
  SELECT s.trip_id, ... 
         CASE WHEN dropoff_ts <= pickup_ts THEN 'BAD_TIMESTAMP_ORDER' ... END
  FROM MEDALLION.bronze_trips_stream s ...
```
* **`silver_rejects`**: We query the stream and use `CASE` statements to flag rows violating business logic, routing them to a dead-letter queue. We explicitly name columns like `s.trip_id` to avoid pulling hidden metadata columns (like `METADATA$ACTION`) that come with `SELECT *` on streams.

```sql
  MERGE INTO MEDALLION.silver_trips t
  USING (
    SELECT s.* FROM MEDALLION.bronze_trips_stream s ...
    QUALIFY ROW_NUMBER() OVER (PARTITION BY s.trip_id ORDER BY s._ingest_ts DESC) = 1
  ) src ON t.trip_id = src.trip_id
```
* **`QUALIFY ROW_NUMBER()`**: Deduplication logic. If the stream contains duplicate `trip_id`s, this window function sorts them by ingest time and only keeps the newest one (`= 1`).
* **`MERGE`**: An upsert operation. If the `trip_id` already exists in `silver_trips`, it `UPDATE`s it. If not, it `INSERT`s it.

```sql
CREATE OR REPLACE TASK MEDALLION.silver_trips_task
  WAREHOUSE = etl_wh
  SCHEDULE = '10 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('MEDALLION.bronze_trips_stream')
AS CALL MEDALLION.silver_trips_proc();
```
* **`WHEN SYSTEM$STREAM_HAS_DATA`**: Prevents the task from waking up the `etl_wh` warehouse if there are no new rows in the Bronze stream, saving compute costs.

---

## 04_quality_control.sql
This script acts as a circuit breaker for data quality.

```sql
  SELECT COUNT_IF(reject_reason IS NOT NULL) / NULLIF(COUNT(*),0) INTO :reject_rate
```
* **`COUNT_IF`**: Quickly counts how many rows went to the rejects table today.
* **`NULLIF(COUNT(*), 0)`**: Prevents a "divide by zero" error by converting 0 to `NULL`.

```sql
  IF (reject_rate > 0.02) THEN 
    RAISE bad_dq; 
  END IF;
```
* **`RAISE`**: Throws an exception. If >2% of the data is bad, the task fails. Because downstream tasks depend on this task succeeding, a failure here acts as a "circuit breaker" and halts the entire pipeline, protecting the Gold layer.

---

## 05_gold_layer.sql
This script aggregates data for fast business reporting.

```sql
CREATE TASK MEDALLION.gold_daily_driver_earnings_task
  AFTER MEDALLION.dq_gate_task
```
* **`AFTER`**: Creates a Directed Acyclic Graph (DAG) dependency. This task will *only* run after the `dq_gate_task` finishes successfully.

```sql
  MERGE INTO ...
  USING (
    SELECT driver_id, DATE(dropoff_ts) AS trip_date, SUM(fare_amount) AS total_fare ...
    GROUP BY driver_id, DATE(dropoff_ts)
  )
```
* **Pre-Aggregation**: Instead of querying raw rows, we `GROUP BY` the driver and day, heavily compressing the data into a summarized format for instant BI dashboard load times.

---

## 06_automation.sql
This script safely starts the pipeline.

```sql
EXECUTE IMMEDIATE
$$
BEGIN
  ALTER TASK MEDALLION.silver_trips_task SUSPEND;
EXCEPTION WHEN OTHER THEN
  NULL; -- Ignore if it's already suspended
END;
$$;
```
* **`EXECUTE IMMEDIATE $$`**: Tells the Snowflake CLI to execute the entire block as a single entity, bypassing aggressive semicolon string-splitting bugs.
* **Idempotency**: Snowflake forbids altering child tasks if the root task is running. We use a try/catch (`EXCEPTION WHEN OTHER THEN NULL;`) to forcefully suspend the root task without throwing an error if it's already suspended.

---

## 07_monitoring.sql & 08_trigger_pipeline.sql
These scripts are for observability and manual execution.

```sql
SELECT STATE, ERROR_MESSAGE, NAME AS TASK_NAME
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(...))
```
* **`TASK_HISTORY()`**: A Snowflake table function that provides an audit log of all background task executions, which is essential for catching silent failures (like missing privileges).

```sql
EXECUTE TASK MEDALLION.silver_trips_task;
```
* **`EXECUTE TASK`**: Bypasses the 10-minute cron schedule and forces the root task to run instantly, rippling down to trigger all child tasks in sequence.
