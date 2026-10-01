# 02 Bronze Layer - Commands and Concepts Explanation

## What is the Bronze Layer?
In a Medallion Architecture (Bronze, Silver, Gold), the **Bronze Layer** is the very first landing zone for your data. It contains raw, unprocessed data directly from the source systems. The primary goal here is to just get the data into the system quickly and safely without changing it. It serves as a historical record that you can always go back to.

---

## Detailed Code Explanation

Below is the step-by-step breakdown of the commands in `02_bronze_layer.sql` in layman's terminology.

### 1. Setting the Context
```sql
USE DATABASE RIDEFLOW;
USE SCHEMA MEDALLION;
```
**What is the use of it?**
These commands set the active database and schema for your current Snowflake session so that subsequent commands know where to execute.

**In Layman's Terms:** 
Imagine the database (`RIDEFLOW`) as an office building and the schema (`MEDALLION`) as a specific room in that building. By running these commands, you are walking into that specific room. Any new tables or streams you build will now automatically be placed inside this room.

---

### 2. Creating the Bronze Table
```sql
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
```
**What is the use of it?**
This command creates the actual table that will hold the raw data. It defines all the business columns (like `trip_id`, `distance_miles`) and some auditing metadata columns (like `_ingest_ts`). 

**In Layman's Terms:** 
You are setting up a highly organized "filing cabinet" for your raw trip data. 
- **Iceberg Table:** Instead of storing the data entirely inside Snowflake, an Iceberg table acts like a smart link. It keeps the data directly in your cloud storage (Azure) in an open format, while Snowflake simply manages and reads it efficiently.
- **Metadata columns (`_ingest_ts`, `_batch_id`):** Notice the columns starting with an underscore. These are like timestamps stamped on an envelope. They don't come from the source system, but instead help track *when* the data arrived and in which *batch*, ensuring you have a complete audit trail.
- **EXTERNAL_VOLUME and BASE_LOCATION:** This tells Snowflake the exact physical location in your Azure cloud storage where the files should actually be saved.

---

### 3. Creating the Data Stream
```sql
CREATE STREAM MEDALLION.bronze_trips_stream ON TABLE MEDALLION.bronze_trips;
```
**What is the use of it?**
This command creates a Snowflake **Stream** on top of the Bronze table. Streams are used for Change Data Capture (CDC). They keep track of inserts, updates, and deletes made to a table.

**In Layman's Terms:**
A Stream is like an automatic "notification bell" or "to-do list" attached to your filing cabinet. 
Whenever new trips are dumped into the Bronze table, the stream silently records this new activity. When it is time to clean the data and move it to the next stage (the Silver Layer), you don't have to scan the entire cabinet to figure out what's new. You simply ask the stream, "What new records came in since I last checked?" This makes the whole data pipeline tremendously fast and cost-effective.

---

## Deep Dive: Syntax Breakdown

### The `CREATE` Syntax
When you see `CREATE ICEBERG TABLE MEDALLION.bronze_trips (...) CATALOG = '...' EXTERNAL_VOLUME = '...' BASE_LOCATION = '...';`, it breaks down into these core parts:

1. **`CREATE TABLE` vs `CREATE ICEBERG TABLE`**: A standard `CREATE TABLE` builds a normal Snowflake table where Snowflake owns the storage entirely inside its own system. Adding `ICEBERG` instructs Snowflake to use the open **Apache Iceberg** format (more on that below).
2. **Column Definitions `(...)`**: The comma-separated list of column names and what type of data they hold (e.g., `STRING` for text, `INT` for numbers, `TIMESTAMP_NTZ` for dates and times).
3. **`CATALOG = 'SNOWFLAKE'`**: This tells Snowflake to be the "manager" or "librarian" that keeps track of the table's structure, schema, and history of changes.
4. **`EXTERNAL_VOLUME = 'rideflow_vol_azure'`**: This links the table to an external storage location (like an Azure Blob Storage container) that was securely configured beforehand.
5. **`BASE_LOCATION = 'bronze/trips/'`**: This specifies the exact folder path inside your external volume where the physical data files will be saved.

### What exactly is "Iceberg"? (Is it a table or a function?)
**Apache Iceberg** is **not** a built-in Snowflake function, nor is it a traditional database table. It is an **open table format**—a specific standardized way of organizing and saving files in the cloud.

When you run the command `CREATE ICEBERG TABLE`, Snowflake acts as the engine that builds a structure in your Azure storage. It writes the data and the metadata (the "smart index") directly into Azure using these Iceberg format standards. 

**In Layman's Terms:**
Imagine you have millions of loose CSV or Excel files in your cloud storage. Managing them and querying them is a nightmare. Iceberg is like a universal filing system standard (think of how PDF is a universal standard for documents, Iceberg is a universal standard for big data tables). 
When you create an **Iceberg Table** in Snowflake, you are telling Snowflake: *"Hey, create a table, but don't lock the files inside your system. Save the actual files over in my Azure account using the universal Iceberg filing standard."*

Because the files are saved in this open standard in your Azure storage:
- The actual data remains in your control in your Azure account.
- *Other* tools (like Databricks, Python, or Spark) can read the data directly from Azure without needing Snowflake at all.
- At the same time, Snowflake can still query and analyze this data incredibly fast, just as if it were stored normally inside Snowflake.

### What does `MEDALLION.bronze_trips` mean?
This is the **fully qualified name** of the table within the current database.

It breaks down as:
- **`MEDALLION`**: This is the **schema name**. A schema is simply a logical folder or a grouping within your database (`RIDEFLOW`) where related objects are organized.
- **`.`**: The dot separates the schema name from the table name.
- **`bronze_trips`**: This is the actual **table name**. "Bronze" indicates it belongs to the raw data layer, and "trips" describes the data it holds.

**In Layman's Terms:**
Think of it like a file path on your computer. If someone says "look at `MEDALLION.bronze_trips`", they are saying: "Go into the `MEDALLION` folder, and open the file named `bronze_trips`."

---

## Common Questions

### Where can I see the Catalog info and what is `bronze/trips/`?
- **Catalog Info (`CATALOG = 'SNOWFLAKE'`)**: Because Snowflake is set as the catalog (the "manager"), all the metadata and table definitions are tracked inside Snowflake itself. To "see" this catalog information, you run standard SQL commands inside the Snowflake UI, such as `SHOW ICEBERG TABLES;` or `DESCRIBE TABLE MEDALLION.bronze_trips;`.
- **`BASE_LOCATION = 'bronze/trips/'`**: This is the literal folder path *inside* your Azure Blob Storage container. If you were to log into your Microsoft Azure portal and open the `rideflow_vol_azure` storage container, you would see a folder named `bronze`, and inside it, a folder named `trips`. This is where the physical Iceberg data files are saved.

### If data is stored in Azure, why build the Bronze table in Snowflake?
This is the core concept of a **Data Lakehouse**—separating **Storage** (Azure) from **Compute** (Snowflake).

1. **Azure is just the hard drive:** Azure Blob Storage is incredibly cheap and scalable for *storing* raw files, but by itself, it doesn't have a database "brain" to query, clean, or transform that data easily.
2. **Snowflake is the brain:** Snowflake provides a massive "Compute Engine". By defining the Bronze table inside Snowflake, you are teaching Snowflake's brain exactly where those Azure files are and how to read them.
In short: You keep the files in Azure for cheap storage and flexibility, but you map it in Snowflake so you can actually *process* and *query* the data effortlessly.

---

## Deep Dive: How Streams Work Technically

### How is a Stream implemented in the background?
From a technical perspective, a Snowflake **Stream** does *not* create a copy of your data or continuously run background tasks. Instead, it relies on Snowflake's internal **Transaction Log** and **Metadata Layer**.

Here is how it works under the hood:
1. **The Offset (Snapshot):** When you create a stream, Snowflake simply records the current state (a snapshot) of the table as an "offset" in its metadata. It costs almost zero storage.
2. **The Transaction Log:** As new DML operations (Inserts, Updates, Deletes) happen on the table, Snowflake naturally records these changes in its internal transaction log.
3. **Querying the Delta:** When you query the stream (e.g., `SELECT * FROM bronze_trips_stream`), Snowflake computes the difference between the stream's current offset and the current state of the table by looking at the transaction log. It returns only the *delta* (the changed rows) along with three metadata columns (`METADATA$ACTION`, `METADATA$ISUPDATE`, `METADATA$ROW_ID`) that describe what kind of change happened.
4. **Advancing the Offset:** Once you consume the stream inside a DML transaction (for example, inserting the stream's contents into the Silver table), the stream's offset automatically advances to the current point in time. The stream is now "empty" until new data arrives.

### How is the Stream attached to Azure?
This is a crucial distinction: **The stream is NOT attached directly to Azure.** 

1. The stream is a Snowflake metadata object attached strictly to the **Snowflake Iceberg Table**.
2. When new physical data files (Parquet files) are dropped into your Azure Blob Storage (`bronze/trips/`), the Iceberg table's catalog is updated to point to these new files. (Because `CATALOG = 'SNOWFLAKE'`, Snowflake updates its own metadata to register this new data).
3. Snowflake's engine recognizes that the Iceberg table has changed (via a new Iceberg snapshot).
4. This change is registered in Snowflake's transaction log for that table.
5. The stream simply reads this Snowflake transaction log. 

**Summary:** Azure holds the physical files $\rightarrow$ Iceberg Metadata registers the new files $\rightarrow$ Snowflake's Transaction Log records the change $\rightarrow$ The Stream queries the Transaction Log.

---

### How is the data actually inserted into the raw Azure physical files?
Since the `bronze_trips` table uses `CATALOG = 'SNOWFLAKE'`, Snowflake acts as the primary manager that writes the data. There are generally two main ways data physically lands in those Azure folders:

**1. The Snowflake Write (Most Common in this setup)**
You extract data from your source system (using tools like Azure Data Factory, Python scripts, or Snowpipe) and execute a standard SQL command in Snowflake:
```sql
INSERT INTO MEDALLION.bronze_trips (trip_id, ...) VALUES (...);
-- OR
COPY INTO MEDALLION.bronze_trips FROM @my_azure_stage;
```
When you run this `INSERT` or `COPY` command, Snowflake takes the data, automatically packages it into highly compressed **Parquet files** using the open Iceberg standard, and pushes those physical files directly into your Azure `bronze/trips/` folder.

**2. The External Write (Bring Your Own Data)**
Because Iceberg is an open format, external tools (like Databricks or Apache Spark) *can* write Iceberg files. **However, there is a catch based on how you set up the Catalog:**

- **Since your code uses `CATALOG = 'SNOWFLAKE'`:** Snowflake is the boss of the metadata. If you simply drop files into Azure using an external tool, the Iceberg metadata **will not** automatically update. Those files will just sit there invisibly until you use Snowflake to ingest them (e.g., using a `COPY INTO` command or Snowpipe).
- **If you used an External Catalog:** If your architecture used a third-party catalog (like Polaris or AWS Glue) and you set `CATALOG = 'my_external_catalog'`, then an external tool (like Spark) could write the files *and* update the Iceberg metadata. Snowflake would then periodically sync with that external catalog, update its own transaction log, and *then* the stream would detect the new data.

**To directly answer the workflow:**
If you want the flow: *Insert file in Azure -> Iceberg metadata updates -> Snowflake Transaction log updates -> Stream sees it*, you either need an **External Catalog Integration**, OR you need to use **Snowpipe** to automatically trigger a Snowflake `INSERT`/`COPY` the moment a file lands in Azure.
