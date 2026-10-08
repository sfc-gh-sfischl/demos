-- =============================================================================
-- Boulevard Scheduling Demo — Step 5: Train ML.FORECAST model and generate predictions
-- Run AFTER 02_load_data.sql.
-- Training takes ~1-2 min on an XS warehouse. It builds one model per
-- location/category series (~50 models).
-- =============================================================================

USE SCHEMA SPABOOKINGS.PUBLIC;

-- Train the multi-series forecast model (one SQL statement!)
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST LABOR_DEMAND_FORECAST(
    INPUT_DATA   => TABLE(V_DAILY_DEMAND),
    SERIES_COLNAME    => 'SERIES_KEY',
    TIMESTAMP_COLNAME => 'TS',
    TARGET_COLNAME    => 'APPOINTMENT_COUNT'
);

-- Generate 14-day forecast for all series
CREATE OR REPLACE TABLE LABOR_FORECAST_RESULTS AS
SELECT * FROM TABLE(LABOR_DEMAND_FORECAST!FORECAST(FORECASTING_PERIODS => 14));

-- Verify
SELECT COUNT(*) AS forecast_rows FROM LABOR_FORECAST_RESULTS;
