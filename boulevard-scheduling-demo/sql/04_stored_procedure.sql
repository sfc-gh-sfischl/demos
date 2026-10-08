-- =============================================================================
-- Boulevard Scheduling Demo — Step 4: Staffing Recommendation Stored Procedure
-- Run AFTER 02_load_data.sql (needs data in tables).
-- This SP is used as a custom tool by the Cortex Agent.
-- =============================================================================

USE SCHEMA SPABOOKINGS.PUBLIC;

CREATE OR REPLACE PROCEDURE RECOMMEND_SCHEDULE(START_DATE VARCHAR, END_DATE VARCHAR)
RETURNS TABLE (
    FORECAST_DATE     DATE,
    LOCATION_CITY     VARCHAR,
    SERVICE_CATEGORY  VARCHAR,
    FORECASTED_DEMAND FLOAT,
    AVAILABLE_PROVIDERS NUMBER,
    RECOMMENDED_STAFF  NUMBER,
    STAFFING_STATUS   VARCHAR,
    GAP               NUMBER
)
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    res RESULTSET;
BEGIN
    res := (
        WITH forecast_parsed AS (
            SELECT
                TS::DATE AS FORECAST_DATE,
                SERIES[0]::VARCHAR AS LOCATION_CITY,
                SERIES[1]::VARCHAR AS SERVICE_CATEGORY,
                CEIL(FORECAST) AS FORECASTED_DEMAND,
                DAYOFWEEK(TS) AS DOW
            FROM SPABOOKINGS.PUBLIC.LABOR_FORECAST_RESULTS
            WHERE TS::DATE BETWEEN :START_DATE::DATE AND :END_DATE::DATE
        ),
        available_staff AS (
            SELECT
                ps.LOCATION_CITY,
                ps.SKILL_CATEGORIES,
                pa.DAY_OF_WEEK,
                COUNT(*) AS PROVIDER_COUNT
            FROM SPABOOKINGS.PUBLIC.PROVIDER_SKILLS ps
            JOIN SPABOOKINGS.PUBLIC.PROVIDER_AVAILABILITY pa
                ON ps.PROVIDER_ID = pa.PROVIDER_ID
            WHERE pa.IS_AVAILABLE = TRUE
            GROUP BY ps.LOCATION_CITY, ps.SKILL_CATEGORIES, pa.DAY_OF_WEEK
        ),
        staff_by_category AS (
            SELECT
                a.LOCATION_CITY,
                a.DAY_OF_WEEK,
                sc.VALUE::VARCHAR AS SERVICE_CATEGORY,
                SUM(a.PROVIDER_COUNT) AS AVAILABLE_PROVIDERS
            FROM available_staff a,
                 LATERAL SPLIT_TO_TABLE(a.SKILL_CATEGORIES, ',') sc
            GROUP BY 1, 2, 3
        )
        SELECT
            f.FORECAST_DATE,
            f.LOCATION_CITY,
            f.SERVICE_CATEGORY,
            f.FORECASTED_DEMAND::FLOAT,
            COALESCE(s.AVAILABLE_PROVIDERS, 0)::INT AS AVAILABLE_PROVIDERS,
            GREATEST(CEIL(f.FORECASTED_DEMAND / 4.0), 1)::INT AS RECOMMENDED_STAFF,
            CASE
                WHEN COALESCE(s.AVAILABLE_PROVIDERS, 0) < GREATEST(CEIL(f.FORECASTED_DEMAND / 4.0), 1) THEN 'Understaffed'
                WHEN COALESCE(s.AVAILABLE_PROVIDERS, 0) > GREATEST(CEIL(f.FORECASTED_DEMAND / 4.0), 1) * 2 THEN 'Overstaffed'
                ELSE 'Adequate'
            END AS STAFFING_STATUS,
            (COALESCE(s.AVAILABLE_PROVIDERS, 0) - GREATEST(CEIL(f.FORECASTED_DEMAND / 4.0), 1))::INT AS GAP
        FROM forecast_parsed f
        LEFT JOIN staff_by_category s
            ON f.LOCATION_CITY = s.LOCATION_CITY
            AND f.SERVICE_CATEGORY = s.SERVICE_CATEGORY
            AND f.DOW = s.DAY_OF_WEEK
        ORDER BY f.FORECAST_DATE, f.LOCATION_CITY, f.SERVICE_CATEGORY
    );
    RETURN TABLE(res);
END;
$$;
