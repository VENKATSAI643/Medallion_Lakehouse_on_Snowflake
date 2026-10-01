# 02b Load Data - Commands and Concepts Explanation

## What is this script doing?
In a Medallion Architecture, you need a way to actually get your raw files *into* the database before you can start cleaning them. This script is all about **initial setup and data ingestion**. It creates the empty tables for the next stages (Silver and Gold) and physically loads your local Parquet data files into the Snowflake Bronze and Silver tables.

---

## Detailed Code Explanation

Below is the step-by-step breakdown of the commands in `02b_load_data.sql` in layman's terminology.

### 1. Setting the Context
```sql
USE DATABASE RIDEFLOW;
USE SCHEMA MEDALLION;
```
**In Layman's Terms:** 
Just like the previous script, this tells Snowflake to execute all the following commands inside the `RIDEFLOW` database and the `MEDALLION` schema (like opening a specific folder on your computer before saving files).

---

### 2. Creating the Silver and Gold Tables
```sql
CREATE TABLE IF NOT EXISTS silver_zones (...)
CREATE TABLE IF NOT EXISTS silver_rejects (...)
CREATE OR REPLACE TABLE silver_trips (...)
CREATE OR REPLACE TABLE gold_daily_driver_earnings (...)
```
**What is the use of it?**
Here, we are building the empty "filing cabinets" for the next phases of our data pipeline. 
- **`silver_trips`:** Will hold the cleaned, filtered, and trustworthy trip data.
- **`silver_rejects`:** A "quarantine" cabinet. If a trip record has missing or bad data (e.g., negative fare amounts), it gets thrown in here instead of breaking our pipeline.
- **`silver_zones`:** A reference table (lookup table) containing the names of the pickup and dropoff locations.
- **`gold_daily_driver_earnings`:** The final, highly summarized table meant for business executives. It aggregates the trips to show daily earnings per driver.

---

### 3. Creating a Temporary Staging Area
```sql
CREATE OR REPLACE TEMPORARY STAGE local_upload_stage FILE_FORMAT = (TYPE = PARQUET);
```
**What is the use of it?**
A **Stage** in Snowflake is like a secure loading dock. 
**In Layman's Terms:** Before you can unpack boxes (files) into your warehouse (tables), the delivery truck needs a place to park and unload. This command creates a temporary loading dock specifically for `PARQUET` files. Because it is `TEMPORARY`, this loading dock will automatically disappear when you log out, keeping your environment clean.

---

### 4. Uploading Local Files to the Stage (The `PUT` Command)
```sql
PUT file:///mnt/e/.../raw_trips.parquet @local_upload_stage AUTO_COMPRESS=FALSE;
PUT file:///mnt/e/.../raw_zones.parquet @local_upload_stage AUTO_COMPRESS=FALSE;
```
**What is the use of it?**
The `PUT` command takes files from your local computer (in this case, your WSL Linux drive on Windows) and securely uploads them up into the Snowflake loading dock (`@local_upload_stage`) that we just built.

---

### 5. Loading Data into the Bronze Table (The `COPY INTO` Command)
```sql
TRUNCATE TABLE bronze_trips;

COPY INTO bronze_trips (...)
FROM (
  SELECT $1:trip_id::STRING, ...
  FROM @local_upload_stage/raw_trips.parquet
)
```
**What is the use of it?**
Now that the files are sitting on the loading dock, we need to unpack them into our actual tables.
- **`TRUNCATE TABLE`:** This command acts like a giant trash can. It quickly deletes all existing rows in the `bronze_trips` table, ensuring we are starting with a completely clean slate before loading new data.
- **`COPY INTO`:** This is Snowflake's powerful tool for unpacking files. It reads the `raw_trips.parquet` file from the loading dock and inserts the data into the `bronze_trips` table.
- **The `SELECT $1...` part:** A Parquet file stores data in a single massive column structure (referred to as `$1`). This SQL logic extracts individual fields (like `$1:trip_id`) and safely casts them into the correct formats (`::STRING`, `::INT`) so they fit perfectly into the table columns.

> **Wait, where is the data being pushed to Azure?**
> This exact `COPY INTO bronze_trips` command is where the magic happens! 
> Remember in the previous script where we created `bronze_trips` as an **Iceberg Table** pointing to `EXTERNAL_VOLUME = 'rideflow_vol_azure'`? 
> Because of that definition, when Snowflake executes this `COPY INTO` command, it doesn't save the data inside itself. Instead, Snowflake's engine takes the data from the temporary loading dock, formats it as Iceberg, and physically pushes it straight into your Azure Blob Storage container (`bronze/trips/`).

---

### 6. Loading Data into the Silver Zones Table
```sql
TRUNCATE TABLE silver_zones;

COPY INTO silver_zones (zone_id, zone_name, borough, _ingest_ts)
FROM (
  SELECT $1:location_id::INT, $1:zone::STRING, $1:borough::STRING, CURRENT_TIMESTAMP()
  FROM @local_upload_stage/raw_zones.parquet
);
```
**What is the use of it?**
Exactly the same logic as above, but for the location zones. It clears the old zones data, reads the `raw_zones.parquet` file from the loading dock, maps the columns, and adds a `CURRENT_TIMESTAMP()` to record exactly *when* this data was ingested. 

*(Note: While trips go through Bronze first because they are large and messy, reference data like "Zones" is often small and clean enough to be loaded directly into Silver).*
