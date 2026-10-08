-- =============================================================================
-- Boulevard Scheduling Demo — Step 2: Load data
--
-- Loads APPOINTMENTS and ORDERLINES from the included CSV files via PUT + COPY.
-- Loads PROVIDER_SKILLS and PROVIDER_AVAILABILITY via inline INSERT statements.
-- Derives DAILY_APPOINTMENT_VOLUME via SQL aggregation.
--
-- Run AFTER 01_setup_and_tables.sql.  Safe to re-run (truncates first).
--
-- IMPORTANT: Run the PUT commands from SnowSQL or Snowflake CLI, not Snowsight.
--            Adjust the file:// paths to where you unzipped the package.
-- =============================================================================

USE WAREHOUSE COMPUTE_WH;   -- <-- change to your warehouse
USE SCHEMA SPABOOKINGS.PUBLIC;

-- ============================================================
-- Stage + file format for CSV loading
-- ============================================================
CREATE OR REPLACE FILE FORMAT SPABOOKINGS_CSV
    TYPE = CSV
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('');

CREATE OR REPLACE STAGE SPABOOKINGS_LOAD
    FILE_FORMAT = SPABOOKINGS_CSV;

-- ============================================================
-- PUT the CSV files (run from SnowSQL / snow CLI — not Snowsight)
-- Adjust paths to where you unzipped the package.
-- ============================================================
-- From the package root directory:
PUT file://data/boulevard_appointments.csv @SPABOOKINGS_LOAD AUTO_COMPRESS = TRUE;
PUT file://data/boulevard_commerce_order_lines.csv @SPABOOKINGS_LOAD AUTO_COMPRESS = TRUE;

-- ============================================================
-- COPY into APPOINTMENTS and ORDERLINES
-- ============================================================
TRUNCATE TABLE APPOINTMENTS;
COPY INTO APPOINTMENTS
    FROM @SPABOOKINGS_LOAD/boulevard_appointments.csv
    FILE_FORMAT = SPABOOKINGS_CSV
    ON_ERROR = 'CONTINUE';

TRUNCATE TABLE ORDERLINES;
COPY INTO ORDERLINES
    FROM @SPABOOKINGS_LOAD/boulevard_commerce_order_lines.csv
    FILE_FORMAT = SPABOOKINGS_CSV
    ON_ERROR = 'CONTINUE';

-- ============================================================
-- PROVIDER_SKILLS (20 providers)
-- ============================================================
TRUNCATE TABLE PROVIDER_SKILLS;
INSERT INTO PROVIDER_SKILLS VALUES
('PRV0001','Ava Martinez','BIZ008','Posh Nails & Spa','Denver','Hair,Skin',8,85),
('PRV0002','Liam Chen','BIZ008','Posh Nails & Spa','Denver','Hair',8,70),
('PRV0003','Sophia Rodriguez','BIZ002','Bloom Salon & Spa','Los Angeles','Hair,Skin',8,85),
('PRV0004','Noah Kim','BIZ008','Posh Nails & Spa','Denver','Skin,Massage',8,70),
('PRV0005','Isabella Patel','BIZ008','Posh Nails & Spa','Denver','Nails,Waxing',8,55),
('PRV0006','Mason Taylor','BIZ008','Posh Nails & Spa','Denver','Hair',7,70),
('PRV0007','Mia Johnson','BIZ008','Posh Nails & Spa','Denver','Hair,Skin',7,85),
('PRV0008','Ethan Williams','BIZ005','Revive Beauty Bar','Austin','Skin,Massage',7,70),
('PRV0009','Charlotte Brown','BIZ002','Bloom Salon & Spa','Los Angeles','Nails,Waxing',7,55),
('PRV0010','James Wilson','BIZ002','Bloom Salon & Spa','Los Angeles','Hair',7,70),
('PRV0011','Amelia Davis','BIZ008','Posh Nails & Spa','Denver','Hair,Skin',6,70),
('PRV0012','Benjamin Garcia','BIZ002','Bloom Salon & Spa','Los Angeles','Skin,Massage',6,70),
('PRV0013','Harper Lee','BIZ008','Posh Nails & Spa','Denver','Nails,Waxing',6,55),
('PRV0014','Lucas Miller','BIZ002','Bloom Salon & Spa','Los Angeles','Hair',6,70),
('PRV0015','Evelyn Moore','BIZ008','Posh Nails & Spa','Denver','Hair,Skin',6,70),
('PRV0016','Alexander White','BIZ004','Serenity Spa','Chicago','Skin,Massage',6,70),
('PRV0017','Abigail Jackson','BIZ004','Serenity Spa','Chicago','Hair,Skin,Massage',6,95),
('PRV0018','Daniel Harris','BIZ008','Posh Nails & Spa','Denver','Hair',6,70),
('PRV0019','Emily Clark','BIZ007','The Beauty Loft','Miami','Hair,Skin,Massage',6,95),
('PRV0020','Henry Lewis','BIZ008','Posh Nails & Spa','Denver','Skin,Massage',6,70);

-- ============================================================
-- PROVIDER_AVAILABILITY (20 providers x 7 days = 140 rows)
-- ============================================================
TRUNCATE TABLE PROVIDER_AVAILABILITY;
INSERT INTO PROVIDER_AVAILABILITY
WITH providers AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS N,
           'PRV' || LPAD(ROW_NUMBER() OVER (ORDER BY SEQ4()), 4, '0') AS PROVIDER_ID
    FROM TABLE(GENERATOR(ROWCOUNT => 20))
),
days AS (
    SELECT column1 AS DOW, column2 AS DNAME FROM VALUES
    (0,'Sunday'),(1,'Monday'),(2,'Tuesday'),(3,'Wednesday'),(4,'Thursday'),(5,'Friday'),(6,'Saturday')
)
SELECT
    p.PROVIDER_ID,
    d.DOW,
    d.DNAME,
    CASE WHEN d.DOW = 0 THEN '10:00:00'::TIME
         WHEN d.DOW IN (5,6) THEN '09:00:00'::TIME
         ELSE '09:00:00'::TIME END AS AVAILABLE_START,
    CASE WHEN d.DOW = 0 THEN '17:00:00'::TIME
         WHEN d.DOW IN (5,6) THEN '20:00:00'::TIME
         ELSE '18:00:00'::TIME END AS AVAILABLE_END,
    CASE
        -- Even providers: Sunday off
        WHEN MOD(p.N, 2) = 0 AND d.DOW = 0 THEN FALSE
        -- Odd providers: Monday off
        WHEN MOD(p.N, 2) = 1 AND d.DOW = 1 THEN FALSE
        -- Providers 11+ work all 7 days (no off day)
        WHEN p.N >= 11 THEN TRUE
        ELSE TRUE
    END AS IS_AVAILABLE
FROM providers p
CROSS JOIN days d
ORDER BY p.PROVIDER_ID, d.DOW;

-- ============================================================
-- DAILY_APPOINTMENT_VOLUME (aggregated from APPOINTMENTS)
-- ============================================================
TRUNCATE TABLE DAILY_APPOINTMENT_VOLUME;
INSERT INTO DAILY_APPOINTMENT_VOLUME
SELECT
    APPOINTMENT_DATE,
    LOCATION_CITY,
    SERVICE_CATEGORY,
    COUNT(*) AS APPOINTMENT_COUNT,
    DAYOFWEEK(APPOINTMENT_DATE) AS DAY_OF_WEEK,
    CASE WHEN DAYOFWEEK(APPOINTMENT_DATE) IN (0,6) THEN 1 ELSE 0 END AS IS_WEEKEND,
    MONTH(APPOINTMENT_DATE) AS MONTH_NUM
FROM APPOINTMENTS
WHERE APPOINTMENT_STATUS = 'completed'
GROUP BY 1, 2, 3;

-- ============================================================
-- Verify row counts
-- ============================================================
SELECT 'APPOINTMENTS' AS TBL, COUNT(*) AS ROWS FROM APPOINTMENTS
UNION ALL SELECT 'ORDERLINES', COUNT(*) FROM ORDERLINES
UNION ALL SELECT 'PROVIDER_SKILLS', COUNT(*) FROM PROVIDER_SKILLS
UNION ALL SELECT 'PROVIDER_AVAILABILITY', COUNT(*) FROM PROVIDER_AVAILABILITY
UNION ALL SELECT 'DAILY_APPOINTMENT_VOLUME', COUNT(*) FROM DAILY_APPOINTMENT_VOLUME
ORDER BY TBL;
