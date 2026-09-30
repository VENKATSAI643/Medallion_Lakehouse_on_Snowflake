-- Phase 0: Database and Schema Setup

-- 1. Create the Database (the main filing cabinet)
CREATE DATABASE IF NOT EXISTS RIDEFLOW;

-- 2. Create the Schema (the specific drawer for this project)
CREATE SCHEMA IF NOT EXISTS RIDEFLOW.MEDALLION;

-- 3. Create the Compute Engines (Warehouses)
CREATE WAREHOUSE IF NOT EXISTS ETL_WH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60;
CREATE WAREHOUSE IF NOT EXISTS BI_WH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60;

-- 4. Set the active context for this session
USE DATABASE RIDEFLOW;
USE SCHEMA MEDALLION;
