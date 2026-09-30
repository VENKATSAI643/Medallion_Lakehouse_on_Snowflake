-- Phase 1: Storage Setup

-- 1. Create the External Volume
CREATE OR REPLACE EXTERNAL VOLUME rideflow_vol_azure
  STORAGE_LOCATIONS = ((
    NAME = 'azure_main'
    STORAGE_PROVIDER = 'AZURE'
    -- Note: Snowflake requires the blob format here, even for dfs.core.windows.net endpoints
    STORAGE_BASE_URL = '&AZURE_STORAGE_BASE_URL'
    AZURE_TENANT_ID = '&AZURE_TENANT_ID'
  ));

-- 2. Get Azure Consent Details
DESC EXTERNAL VOLUME rideflow_vol_azure;

-- (Pause here. Grant access in Azure using the output from the DESC command before verifying)

-- 3. Verify Connection
SELECT SYSTEM$VERIFY_EXTERNAL_VOLUME('rideflow_vol_azure');
