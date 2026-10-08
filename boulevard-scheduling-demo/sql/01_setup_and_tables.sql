-- =============================================================================
-- Boulevard Scheduling Demo — Step 1: Database, warehouse context, and tables
-- Run as a role with CREATE DATABASE (e.g. SYSADMIN or ACCOUNTADMIN).
-- To use a different warehouse, edit the USE WAREHOUSE line below.
-- =============================================================================

USE WAREHOUSE COMPUTE_WH;   -- <-- change to your warehouse

CREATE DATABASE IF NOT EXISTS SPABOOKINGS;
CREATE SCHEMA IF NOT EXISTS SPABOOKINGS.PUBLIC;
USE SCHEMA SPABOOKINGS.PUBLIC;

-- ---------------------------------------------------------------- appointments
CREATE OR REPLACE TABLE APPOINTMENTS (
    APPOINTMENT_ID       VARCHAR,
    ORDER_ID             VARCHAR,
    CLIENT_ID            VARCHAR,
    BUSINESS_ID          VARCHAR,
    BUSINESS_NAME        VARCHAR,
    LOCATION_CITY        VARCHAR,
    PROVIDER_ID          VARCHAR,
    APPOINTMENT_DATE     DATE,
    APPOINTMENT_TIME     TIME,
    SERVICE_DURATION_MINS NUMBER(38,0),
    APPOINTMENT_STATUS   VARCHAR,
    BOOKING_SOURCE       VARCHAR,
    BOOKED_AT            DATE,
    DAYS_BOOKED_IN_ADVANCE NUMBER(38,0),
    CANCELLATION_REASON  VARCHAR,
    IS_FIRST_VISIT       BOOLEAN,
    SERVICE_CATEGORY     VARCHAR
);

-- ---------------------------------------------------------------- order lines
CREATE OR REPLACE TABLE ORDERLINES (
    ORDER_LINE_ID   VARCHAR,
    ORDER_ID        VARCHAR,
    APPOINTMENT_ID  VARCHAR,
    CLIENT_ID       VARCHAR,
    BUSINESS_ID     VARCHAR,
    SERVICE_DATE    DATE,
    SERVICE_CATEGORY VARCHAR,
    SERVICE_NAME    VARCHAR,
    PROVIDER_ID     VARCHAR,
    UNIT_PRICE      FLOAT,
    QUANTITY        NUMBER(38,0),
    DISCOUNT_AMOUNT FLOAT,
    TIP_AMOUNT      FLOAT,
    LINE_TOTAL      FLOAT,
    ORDER_STATUS    VARCHAR,
    PAYMENT_METHOD  VARCHAR
);

-- ---------------------------------------------------------------- rebooking predictions (ML pipeline output)
CREATE OR REPLACE TABLE CLIENT_REBOOKING_PREDICTIONS (
    CLIENT_ID            VARCHAR,
    DAYS_SINCE_LAST_VISIT NUMBER(38,0),
    TENURE_DAYS          NUMBER(38,0),
    TOTAL_APPOINTMENTS   NUMBER(38,0),
    COMPLETED_COUNT      NUMBER(38,0),
    NO_SHOW_RATE         FLOAT,
    CANCELLATION_RATE    FLOAT,
    AVG_DAYS_BETWEEN_VISITS FLOAT,
    AVG_DURATION_MINS    FLOAT,
    AVG_DAYS_BOOKED_ADVANCE FLOAT,
    APP_BOOKING_PCT      FLOAT,
    SERVICE_CATEGORIES   NUMBER(38,0),
    TOTAL_SPEND          FLOAT,
    AVG_ORDER_VALUE      FLOAT,
    AVG_TIP              FLOAT,
    TIP_RATE             FLOAT,
    SPEND_TREND          FLOAT,
    RISK_SCORE           FLOAT,
    PREDICTED_AT_RISK    NUMBER(38,0),
    ACTUAL_AT_RISK       NUMBER(38,0),
    PREDICTION_TIMESTAMP VARCHAR,
    PREDICTION_TS        TIMESTAMP_NTZ
);

-- ---------------------------------------------------------------- daily appointment volume (aggregated)
CREATE OR REPLACE TABLE DAILY_APPOINTMENT_VOLUME (
    APPOINTMENT_DATE  DATE,
    LOCATION_CITY     VARCHAR,
    SERVICE_CATEGORY  VARCHAR,
    APPOINTMENT_COUNT NUMBER(18,0),
    DAY_OF_WEEK       NUMBER(2,0),
    IS_WEEKEND        NUMBER(1,0),
    MONTH_NUM         NUMBER(2,0)
);

-- ---------------------------------------------------------------- provider skills
CREATE OR REPLACE TABLE PROVIDER_SKILLS (
    PROVIDER_ID      VARCHAR,
    PROVIDER_NAME    VARCHAR,
    BUSINESS_ID      VARCHAR,
    BUSINESS_NAME    VARCHAR,
    LOCATION_CITY    VARCHAR,
    SKILL_CATEGORIES VARCHAR,
    MAX_DAILY_HOURS  NUMBER(1,0),
    HOURLY_RATE      NUMBER(2,0)
);

-- ---------------------------------------------------------------- provider availability
CREATE OR REPLACE TABLE PROVIDER_AVAILABILITY (
    PROVIDER_ID     VARCHAR,
    DAY_OF_WEEK     NUMBER(1,0),
    DAY_NAME        VARCHAR(9),
    AVAILABLE_START TIME,
    AVAILABLE_END   TIME,
    IS_AVAILABLE    BOOLEAN
);

-- ---------------------------------------------------------------- forecast results (populated by ML model)
CREATE OR REPLACE TABLE LABOR_FORECAST_RESULTS (
    SERIES      VARIANT,
    TS          TIMESTAMP_NTZ,
    FORECAST    FLOAT,
    LOWER_BOUND FLOAT,
    UPPER_BOUND FLOAT
);

-- ---------------------------------------------------------------- forecast input view
CREATE OR REPLACE VIEW V_DAILY_DEMAND AS
SELECT
    [LOCATION_CITY, SERVICE_CATEGORY] AS SERIES_KEY,
    APPOINTMENT_DATE::TIMESTAMP_NTZ AS TS,
    COUNT(*)::FLOAT AS APPOINTMENT_COUNT
FROM SPABOOKINGS.PUBLIC.APPOINTMENTS
WHERE APPOINTMENT_STATUS = 'completed'
GROUP BY 1, 2;
