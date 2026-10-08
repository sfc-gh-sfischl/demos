-- =============================================================================
-- Boulevard Scheduling Demo — Step 3: Semantic View
-- Run AFTER 02_load_data.sql.
-- =============================================================================

USE SCHEMA SPABOOKINGS.PUBLIC;

CREATE OR REPLACE SEMANTIC VIEW SCHEDULING_SEMANTIC_VIEW
    TABLES (
        SPABOOKINGS.PUBLIC.APPOINTMENTS PRIMARY KEY (APPOINTMENT_ID)
            COMMENT = 'Historical appointment data for all salons',
        FORECASTS AS SPABOOKINGS.PUBLIC.LABOR_FORECAST_RESULTS
            COMMENT = 'Forecasted appointment demand by location and service category',
        PROVIDERS AS SPABOOKINGS.PUBLIC.PROVIDER_SKILLS PRIMARY KEY (PROVIDER_ID)
            COMMENT = 'Provider skills, rates, and primary location',
        AVAILABILITY AS SPABOOKINGS.PUBLIC.PROVIDER_AVAILABILITY
            COMMENT = 'Provider weekly availability schedule',
        VOLUME AS SPABOOKINGS.PUBLIC.DAILY_APPOINTMENT_VOLUME
            COMMENT = 'Daily aggregated appointment counts'
    )
    RELATIONSHIPS (
        PROVIDERS_TO_AVAILABILITY AS AVAILABILITY(PROVIDER_ID) REFERENCES PROVIDERS(PROVIDER_ID)
    )
    FACTS (
        FORECASTS.FORECAST_VALUE AS FORECAST,
        FORECASTS.LOWER_BOUND_VALUE AS LOWER_BOUND,
        FORECASTS.UPPER_BOUND_VALUE AS UPPER_BOUND,
        VOLUME.DAILY_COUNT AS APPOINTMENT_COUNT
    )
    DIMENSIONS (
        APPOINTMENTS.APPT_DATE AS APPOINTMENT_DATE
            COMMENT = 'Date of the appointment',
        APPOINTMENTS.APPT_LOCATION AS LOCATION_CITY
            COMMENT = 'City where the salon is located',
        APPOINTMENTS.APPT_SERVICE AS SERVICE_CATEGORY
            COMMENT = 'Type of service (Hair, Skin, Nails, Massage, Waxing)',
        APPOINTMENTS.APPT_STATUS AS APPOINTMENT_STATUS
            COMMENT = 'Status: completed, cancelled, no_show',
        APPOINTMENTS.APPT_PROVIDER AS PROVIDER_ID
            COMMENT = 'Provider who performed the service',
        FORECASTS.FORECAST_DATE AS TS
            COMMENT = 'Forecasted date',
        FORECASTS.FORECAST_SERIES AS SERIES
            COMMENT = 'Location and service category array for forecast',
        PROVIDERS.PROVIDER_NAME_DIM AS PROVIDER_NAME
            COMMENT = 'Name of the provider',
        PROVIDERS.PROVIDER_LOCATION AS LOCATION_CITY
            COMMENT = 'Primary location of the provider',
        PROVIDERS.PROVIDER_SKILLS AS SKILL_CATEGORIES
            COMMENT = 'Comma-separated service categories the provider can perform',
        AVAILABILITY.AVAIL_DAY AS DAY_NAME
            COMMENT = 'Day of week name',
        AVAILABILITY.AVAIL_STATUS AS IS_AVAILABLE
            COMMENT = 'Whether provider is available on this day',
        VOLUME.VOL_DATE AS APPOINTMENT_DATE
            COMMENT = 'Date for the volume metric',
        VOLUME.VOL_LOCATION AS LOCATION_CITY
            COMMENT = 'Location for volume',
        VOLUME.VOL_CATEGORY AS SERVICE_CATEGORY
            COMMENT = 'Service category for volume'
    )
    METRICS (
        APPOINTMENTS.TOTAL_APPOINTMENTS AS COUNT(APPOINTMENT_ID)
            COMMENT = 'Total number of appointments',
        APPOINTMENTS.AVG_DURATION AS AVG(SERVICE_DURATION_MINS)
            COMMENT = 'Average service duration in minutes',
        VOLUME.TOTAL_VOLUME AS SUM(APPOINTMENT_COUNT)
            COMMENT = 'Total appointment volume',
        PROVIDERS.PROVIDER_COUNT AS COUNT(PROVIDER_ID)
            COMMENT = 'Number of providers'
    )
    COMMENT = 'Semantic view for Boulevard salon labor forecasting and scheduling'
    AI_SQL_GENERATION 'When asked about forecasts or predicted demand, query the forecasts table. The SERIES column is an array with [LOCATION_CITY, SERVICE_CATEGORY]. When asked about provider availability, join providers with availability. When calculating staffing needs, assume each provider can handle 4 appointments per day.';
