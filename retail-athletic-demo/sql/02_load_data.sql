-- =============================================================================
-- Retail Athletic Demo — Step 2: Load synthetic data (~150K rows, ~1-2 min on XS)
--
-- All "random" values are derived from HASH(row_key, '<salt>') rather than
-- RANDOM(), so the data is identical on every run and derived columns stay
-- consistent with the values they are derived from (net <= gross, MSRP > cost,
-- KPI rollups match transactions, churn label depends on behaviour, etc.).
--
-- Data window: 2024-10-01 .. 2025-09-30. Feature/scoring date: 2025-09-30.
-- Run AFTER 01_setup_and_tables.sql. Safe to re-run (truncates first).
-- =============================================================================

USE WAREHOUSE COMPUTE_WH;   -- <-- change to your warehouse
USE SCHEMA RETAIL_ATHLETIC_DEMO.PUBLIC;

TRUNCATE TABLE DIM_PRODUCT;            TRUNCATE TABLE DIM_STORE;
TRUNCATE TABLE DIM_CUSTOMER;           TRUNCATE TABLE ML_CUSTOMER_FEATURES;
TRUNCATE TABLE DIM_MARKETING_CAMPAIGN; TRUNCATE TABLE FACT_CAMPAIGN_PERFORMANCE;
TRUNCATE TABLE FACT_DAILY_SALES;       TRUNCATE TABLE FACT_DAILY_KPI;
TRUNCATE TABLE FACT_CUSTOMER_INTERACTIONS;
TRUNCATE TABLE FACT_INVENTORY_SNAPSHOT; TRUNCATE TABLE FACT_DEMAND_FORECAST;
TRUNCATE TABLE ASSORTMENT_PLAN;        TRUNCATE TABLE PRODUCT_DEVELOPMENT_PIPELINE;

-- ============================================================ DIM_PRODUCT (500)
INSERT INTO DIM_PRODUCT (PRODUCT_ID, PRODUCT_NAME, PRODUCT_LINE, CATEGORY, SUBCATEGORY, MATERIAL,
    COLOR, SIZE, SEASON, LAUNCH_DATE, LIFECYCLE_STAGE, UNIT_COST, MSRP, WHOLESALE_PRICE, IS_SUSTAINABLE)
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 500))
), p AS (
    SELECT n,
        'P' || LPAD(n, 5, '0') AS product_id,
        GET(ARRAY_CONSTRUCT('Performance','Everyday','Sunday','Banks','Ponto','Clementine',
                            'Riviera','Halo','DreamKnit','BlueLine'), UNIFORM(0, 9, HASH(n, 'line')))::STRING AS line,
        IFF(UNIFORM(0, 99, HASH(n, 'gender')) < 50, 'Men''s', 'Women''s') AS gender,
        UNIFORM(0, 99, HASH(n, 'type')) AS type_roll,
        UNIFORM(0, 99, HASH(n, 'stage')) AS stage_roll,
        UNIFORM(12::FLOAT, 55::FLOAT, HASH(n, 'cost')) AS cost,
        UNIFORM(2.8::FLOAT, 4.2::FLOAT, HASH(n, 'markup')) AS markup,
        GET(ARRAY_CONSTRUCT('Azure Blue','Cloud Grey','Night Black','Pacific Green','Desert Sand','Coastline Navy',
                            'Dusk Rose','Stone','Linen White','Redwood','Sage','Carbon'), UNIFORM(0, 11, HASH(n, 'color')))::STRING AS color
    FROM base
), p2 AS (
    SELECT *,
        CASE WHEN type_roll < 35 THEN 'Tops'
             WHEN type_roll < 70 THEN 'Bottoms'
             WHEN type_roll < 82 THEN 'Outerwear'
             WHEN type_roll < 92 OR gender = 'Men''s' THEN 'Accessories'
             ELSE 'Dresses & Jumpsuits' END AS ptype,
        CASE WHEN stage_roll < 55 THEN 'In Market'
             WHEN stage_roll < 70 THEN 'Markdown'
             WHEN stage_roll < 78 THEN 'Retired'
             WHEN stage_roll < 86 THEN 'Production'
             WHEN stage_roll < 91 THEN 'Pre-Production'
             WHEN stage_roll < 94 THEN 'Tech Pack Review'
             WHEN stage_roll < 97 THEN 'Sampling'
             WHEN stage_roll < 99 THEN 'Design'
             ELSE 'Concept' END AS stage
    FROM p
), p3 AS (
    SELECT *,
        CASE ptype
            WHEN 'Tops'        THEN GET(ARRAY_CONSTRUCT('Tees','Long Sleeves','Tanks','Hoodies','Polos'), UNIFORM(0, 4, HASH(n, 'sub')))::STRING
            WHEN 'Bottoms'     THEN GET(ARRAY_CONSTRUCT('Joggers','Shorts','Leggings','Pants'), UNIFORM(0, 3, HASH(n, 'sub')))::STRING
            WHEN 'Outerwear'   THEN GET(ARRAY_CONSTRUCT('Jackets','Vests','Pullovers'), UNIFORM(0, 2, HASH(n, 'sub')))::STRING
            WHEN 'Accessories' THEN GET(ARRAY_CONSTRUCT('Hats','Socks','Bags'), UNIFORM(0, 2, HASH(n, 'sub')))::STRING
            ELSE                    GET(ARRAY_CONSTRUCT('Dresses','Jumpsuits'), UNIFORM(0, 1, HASH(n, 'sub')))::STRING
        END AS subcat,
        -- pre-market products launch in the future; everything else already launched
        IFF(stage IN ('Production','Pre-Production','Tech Pack Review','Sampling','Design','Concept'),
            DATEADD('day', UNIFORM(10, 180, HASH(n, 'launch')), '2025-09-30'::DATE),
            DATEADD('day', UNIFORM(0, 790, HASH(n, 'launch')), '2023-06-01'::DATE)) AS launch_date
    FROM p2
)
SELECT
    product_id,
    line || ' ' || subcat || ' - ' || color,
    line,
    gender || ' ' || ptype,
    subcat,
    GET(ARRAY_CONSTRUCT('Recycled Polyester','Organic Cotton','Tencel Lyocell','Nylon','Merino Wool Blend',
                        'Repreve Fiber','Bamboo Blend','Linen Blend'), UNIFORM(0, 7, HASH(n, 'material')))::STRING,
    color,
    GET(ARRAY_CONSTRUCT('XS','S','M','L','XL','XXL'), UNIFORM(0, 5, HASH(n, 'size')))::STRING,
    CASE WHEN MONTH(launch_date) <= 4 THEN 'Spring' WHEN MONTH(launch_date) <= 8 THEN 'Summer'
         WHEN MONTH(launch_date) <= 10 THEN 'Fall' ELSE 'Holiday' END || ' ' || YEAR(launch_date),
    launch_date,
    stage,
    ROUND(cost, 2),
    ROUND(cost * markup, 0) - 0.01,                 -- e.g. 88.00 -> 87.99
    ROUND((ROUND(cost * markup, 0) - 0.01) * 0.5, 2),
    UNIFORM(0, 99, HASH(n, 'sustainable')) < 70
FROM p3;

-- ============================================================== DIM_STORE (25)
-- 20 retail doors, 3 wholesale partners, 2 e-commerce "stores" (DTC fulfilment)
INSERT INTO DIM_STORE (STORE_ID, STORE_NAME, CITY, STATE, REGION, CHANNEL, OPEN_DATE, SQUARE_FEET, IS_ACTIVE)
SELECT 'S' || LPAD(column1, 5, '0'), column2, column3, column4, column5, column6,
       column7::DATE, column8, TRUE
FROM VALUES
    ( 1, 'Store - Carlsbad',             'Carlsbad',        'CA', 'West',          'Retail Store',      '2019-03-15', 3200),
    ( 2, 'Store - Encinitas',            'Encinitas',       'CA', 'West',          'Retail Store',      '2019-09-01', 2400),
    ( 3, 'Store - Manhattan Beach',      'Manhattan Beach', 'CA', 'West',          'Retail Store',      '2020-05-20', 2800),
    ( 4, 'Store - Santa Monica',         'Santa Monica',    'CA', 'West',          'Retail Store',      '2020-11-10', 3500),
    ( 5, 'Store - San Francisco',        'San Francisco',   'CA', 'West',          'Retail Store',      '2021-04-02', 4100),
    ( 6, 'Store - Seattle',              'Seattle',         'WA', 'West',          'Retail Store',      '2021-08-14', 3300),
    ( 7, 'Store - Portland',             'Portland',        'OR', 'West',          'Retail Store',      '2022-02-25', 2700),
    ( 8, 'Store - Denver',               'Denver',          'CO', 'West',          'Retail Store',      '2022-06-11', 3000),
    ( 9, 'Store - Scottsdale',           'Scottsdale',      'AZ', 'West',          'Retail Store',      '2022-10-07', 2600),
    (10, 'Store - Austin',               'Austin',          'TX', 'South',         'Retail Store',      '2021-12-03', 3400),
    (11, 'Store - Dallas',               'Dallas',          'TX', 'South',         'Retail Store',      '2023-03-18', 3100),
    (12, 'Store - Miami',                'Miami',           'FL', 'South',         'Retail Store',      '2022-11-19', 2900),
    (13, 'Store - Atlanta',              'Atlanta',         'GA', 'South',         'Retail Store',      '2023-05-06', 2800),
    (14, 'Store - Nashville',            'Nashville',       'TN', 'South',         'Retail Store',      '2023-09-09', 2500),
    (15, 'Store - New York SoHo',        'New York',        'NY', 'East',          'Retail Store',      '2021-06-26', 5200),
    (16, 'Store - Boston',               'Boston',          'MA', 'East',          'Retail Store',      '2022-08-20', 3000),
    (17, 'Store - Philadelphia',         'Philadelphia',    'PA', 'East',          'Retail Store',      '2024-02-10', 2700),
    (18, 'Store - Chicago',              'Chicago',         'IL', 'Midwest',       'Retail Store',      '2022-04-30', 3600),
    (19, 'Store - Minneapolis',          'Minneapolis',     'MN', 'Midwest',       'Retail Store',      '2024-04-13', 2400),
    (20, 'Store - Honolulu',             'Honolulu',        'HI', 'West',          'Retail Store',      '2023-12-01', 2200),
    (21, 'Wholesale - Outdoor Partner',  'Denver',          'CO', 'West',          'Wholesale',         '2020-01-15', 0),
    (22, 'Wholesale - Department Store', 'New York',        'NY', 'East',          'Wholesale',         '2020-07-01', 0),
    (23, 'Wholesale - Specialty Run',    'Chicago',         'IL', 'Midwest',       'Wholesale',         '2021-03-01', 0),
    (24, 'E-Commerce - US',              'Carlsbad',        'CA', 'West',          'DTC Website',       '2015-06-01', 0),
    (25, 'E-Commerce - International',   'Carlsbad',        'CA', 'International', 'International DTC', '2019-01-01', 0);

-- ======================================= Customers: shared base (temp table)
-- A latent "engagement" score drives behaviour; churn risk is a logistic
-- function of that behaviour plus noise, so the ML model has real signal.
CREATE OR REPLACE TEMPORARY TABLE _CUSTOMER_BASE AS
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 5000))
), lat AS (
    SELECT n,
        'C' || LPAD(n, 6, '0') AS customer_id,
        NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'eng')) AS e,
        IFF(UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'intl')) < 0.08,
            20 + UNIFORM(0, 3, HASH(n, 'city')), UNIFORM(0, 19, HASH(n, 'city'))) AS city_idx
    FROM base
), feat AS (
    SELECT lat.*,
        GREATEST(0, LEAST(365, ROUND(120 - 70 * e + 60 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'dsl')))))  AS days_since,
        GREATEST(0.1, LEAST(5, 1.5 + 0.7 * e + 0.5 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'freq'))))     AS freq,   -- purchases / quarter
        UNIFORM(60::FLOAT, 220::FLOAT, HASH(n, 'aov'))                                                  AS aov,
        GREATEST(0, LEAST(0.9, 0.25 + 0.12 * e + 0.08 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'email')))) AS email_eng,
        GREATEST(0, ROUND(12 + 7 * e + 5 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'web'))))                 AS web_visits,
        GREATEST(0, LEAST(0.4, 0.08 - 0.03 * e + 0.04 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'ret'))))   AS return_rate,
        GREATEST(0.05, LEAST(1, 0.5 + 0.15 * e + 0.15 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'pdiv'))))  AS prod_div,
        GREATEST(0.05, LEAST(1, 0.45 + 0.12 * e + 0.18 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'cdiv')))) AS chan_div,
        GREATEST(0, LEAST(10, ROUND(7 + 1.5 * e + 1.5 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'nps')))))   AS nps,
        UNIFORM(30, 2000, HASH(n, 'tenure'))                                                            AS tenure_raw
    FROM lat
), risk AS (
    SELECT feat.*,
        GREATEST(tenure_raw, days_since + 30) AS tenure_days,
        1 / (1 + EXP(-(-1.1
            + 0.012 * (days_since - 120)
            - 0.6   * (freq - 1.5)
            - 4.0   * (email_eng - 0.25)
            - 0.05  * (web_visits - 12)
            + 6.0   * (return_rate - 0.08)
            - 0.15  * (nps - 7)
            + 0.6   * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'noise'))))) AS churn_risk
    FROM feat
), derived AS (
    SELECT risk.*,
        GREATEST(1, LEAST(60, ROUND(freq * 4 * tenure_days / 365))) AS total_orders,
        ROUND(aov * freq * 4 * GREATEST(0.1, 1 - days_since / 365), 2) AS spend_12m
    FROM risk
)
SELECT derived.*,
    ROUND(aov * total_orders, 2) AS lifetime_value,
    CASE WHEN total_orders <= 2 AND tenure_days < 150                 THEN 'New Customer'
         WHEN days_since > 270                                         THEN 'Lapsed'
         WHEN days_since > 180                                         THEN 'Win-Back Target'
         WHEN aov * total_orders >= 2500 AND churn_risk >= 0.5         THEN 'High-Value At-Risk'
         WHEN total_orders >= 12 AND churn_risk < 0.35                 THEN 'Loyal VIP'
         WHEN web_visits >= 15 AND total_orders <= 3                   THEN 'Browser'
         ELSE 'Active Regular' END AS segment
FROM derived;

-- ======================================================= ML_CUSTOMER_FEATURES
INSERT INTO ML_CUSTOMER_FEATURES (CUSTOMER_ID, FEATURE_DATE, DAYS_SINCE_LAST_PURCHASE, PURCHASE_FREQUENCY,
    AVG_ORDER_VALUE, TOTAL_SPEND_12M, PRODUCT_DIVERSITY_SCORE, CHANNEL_DIVERSITY_SCORE, RETURN_RATE,
    EMAIL_ENGAGEMENT_RATE, WEB_VISITS_30D, CHURN_PROBABILITY, PREDICTED_NEXT_PURCHASE,
    RECOMMENDED_PRODUCTS, CLV_PREDICTED_12M, SEGMENT_PREDICTED)
SELECT
    customer_id,
    '2025-09-30'::DATE,
    days_since,
    ROUND(freq, 2),
    ROUND(aov, 2),
    spend_12m,
    ROUND(prod_div, 4),
    ROUND(chan_div, 4),
    ROUND(return_rate, 4),
    ROUND(email_eng, 4),
    web_visits,
    -- a legacy rule-based score: correlated with true risk but noisy
    ROUND(GREATEST(0.01, LEAST(0.99, churn_risk + 0.15 * NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'legacy')))), 4),
    DATEADD('day', LEAST(365, ROUND(90 / freq * (1 + churn_risk))), '2025-09-30'::DATE),
    GET(ARRAY_CONSTRUCT(
        'Performance Joggers;Everyday Tees;DreamKnit Hoodies',
        'Banks Shorts;Ponto Pants;Sunday Pullovers',
        'Halo Leggings;Clementine Dresses;Riviera Tanks',
        'DreamKnit Joggers;Performance Shorts;BlueLine Jackets',
        'Everyday Long Sleeves;Sunday Joggers;Ponto Hoodies',
        'Riviera Polos;Halo Tanks;Banks Hats'), UNIFORM(0, 5, HASH(n, 'reco')))::STRING,
    ROUND(spend_12m * (1 - churn_risk) * 1.15, 2),
    IFF(UNIFORM(0, 99, HASH(n, 'pseg')) < 90, segment, 'Active Regular')
FROM _CUSTOMER_BASE;

-- ================================================================ DIM_CUSTOMER
INSERT INTO DIM_CUSTOMER (CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL, PHONE, CITY, STATE, REGION, SEGMENT,
    LIFETIME_VALUE, FIRST_PURCHASE_DATE, LAST_PURCHASE_DATE, TOTAL_ORDERS, PREFERRED_CHANNEL,
    OPT_IN_EMAIL, OPT_IN_SMS, CHURN_RISK_SCORE, NPS_SCORE)
WITH named AS (
    SELECT b.*,
        GET(ARRAY_CONSTRUCT('James','Mary','John','Patricia','Robert','Jennifer','Michael','Linda','David','Elizabeth',
            'William','Barbara','Richard','Susan','Joseph','Jessica','Thomas','Sarah','Chris','Karen','Daniel','Lisa',
            'Matthew','Nancy','Anthony','Maya','Mark','Margaret','Andrew','Sandra','Joshua','Ashley','Steven','Kim',
            'Ryan','Emily','Brandon','Priya','Brian','Michelle'), UNIFORM(0, 39, HASH(n, 'fn')))::STRING AS first_name,
        GET(ARRAY_CONSTRUCT('Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez',
            'Martinez','Hernandez','Lopez','Gonzalez','Wilson','Anderson','Thomas','Taylor','Moore','Jackson','Martin',
            'Lee','Perez','Thompson','White','Harris','Sanchez','Clark','Ramirez','Lewis','Nguyen'),
            UNIFORM(0, 29, HASH(n, 'ln')))::STRING AS last_name,
        GET(ARRAY_CONSTRUCT('San Diego','Los Angeles','San Francisco','Seattle','Portland','Denver','Phoenix',
            'Salt Lake City','Austin','Dallas','Houston','Miami','Atlanta','Nashville','Charlotte','New York','Boston',
            'Philadelphia','Chicago','Minneapolis','Toronto','Vancouver','London','Sydney'), city_idx)::STRING AS city,
        GET(ARRAY_CONSTRUCT('CA','CA','CA','WA','OR','CO','AZ','UT','TX','TX','TX','FL','GA','TN','NC','NY','MA',
            'PA','IL','MN','ON','BC','ENG','NSW'), city_idx)::STRING AS state,
        GET(ARRAY_CONSTRUCT('West','West','West','West','West','West','West','West','South','South','South',
            'South','South','South','East','East','East','East','Midwest','Midwest','International','International',
            'International','International'), city_idx)::STRING AS region
    FROM _CUSTOMER_BASE b
)
SELECT
    customer_id,
    first_name,
    last_name,
    LOWER(first_name) || '.' || LOWER(last_name) || n || '@' ||
        GET(ARRAY_CONSTRUCT('gmail.com','yahoo.com','outlook.com','icloud.com','hotmail.com'), UNIFORM(0, 4, HASH(n, 'dom')))::STRING,
    '+1-' || UNIFORM(201, 989, HASH(n, 'area')) || '-555-' || LPAD(UNIFORM(0, 9999, HASH(n, 'phone')), 4, '0'),
    city,
    state,
    region,
    segment,
    lifetime_value,
    DATEADD('day', -tenure_days, '2025-09-30'::DATE),
    DATEADD('day', -days_since, '2025-09-30'::DATE),
    total_orders,
    CASE WHEN region = 'International' THEN 'International DTC'
         WHEN UNIFORM(0, 99, HASH(n, 'pchan')) < 55 THEN 'DTC Website'
         WHEN UNIFORM(0, 99, HASH(n, 'pchan')) < 90 THEN 'Retail Store'
         ELSE 'Wholesale' END,
    UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'optemail')) < 0.55 + 0.4 * email_eng,
    UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'optsms')) < 0.45,
    ROUND(churn_risk, 4),
    nps
FROM named;

-- ===================================================== DIM_MARKETING_CAMPAIGN (40)
INSERT INTO DIM_MARKETING_CAMPAIGN (CAMPAIGN_ID, CAMPAIGN_NAME, CAMPAIGN_TYPE, CHANNEL, START_DATE, END_DATE,
    BUDGET, TARGET_SEGMENT, PRODUCT_LINE, STATUS)
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 40))
), c AS (
    SELECT n,
        'CMP' || LPAD(n, 4, '0') AS campaign_id,
        GET(ARRAY_CONSTRUCT('Email Blast','Social Ads','Influencer','Retargeting','Loyalty Program',
                            'Seasonal Sale','New Launch','Brand Awareness'), MOD(n - 1, 8))::STRING AS ctype,
        GET(ARRAY_CONSTRUCT('Performance','Everyday','Sunday','Banks','Ponto','DreamKnit'),
            UNIFORM(0, 5, HASH(n, 'line')))::STRING AS line,
        DATEADD('day', UNIFORM(0, 320, HASH(n, 'start')), '2024-10-01'::DATE) AS start_date,
        UNIFORM(14, 45, HASH(n, 'len')) AS len_days,
        ROUND(UNIFORM(15000, 150000, HASH(n, 'budget')), -3) AS budget
    FROM base
)
SELECT
    campaign_id,
    ctype || ' - ' || line || ' ' || TO_CHAR(start_date, 'Mon YYYY'),
    ctype,
    IFF(ctype IN ('Seasonal Sale', 'Loyalty Program'), 'Retail Store', 'DTC Website'),
    start_date,
    LEAST(DATEADD('day', len_days, start_date), '2025-09-30'::DATE),
    budget,
    CASE ctype WHEN 'Retargeting'     THEN 'Browser'
               WHEN 'Loyalty Program' THEN 'Loyal VIP'
               WHEN 'Email Blast'     THEN 'Win-Back Target'
               WHEN 'Seasonal Sale'   THEN 'Lapsed'
               WHEN 'New Launch'      THEN 'Active Regular'
               ELSE 'New Customer' END,
    line,
    IFF(DATEADD('day', len_days, start_date) < '2025-09-30'::DATE, 'Completed', 'Active')
FROM c;

-- ================================================== FACT_CAMPAIGN_PERFORMANCE
-- Funnel is internally consistent: cost -> impressions (CPM) -> clicks (CTR)
-- -> conversions (CVR) -> revenue (AOV) -> ROAS. CVR/CPM vary by campaign type.
INSERT INTO FACT_CAMPAIGN_PERFORMANCE (PERF_ID, CAMPAIGN_ID, PERF_DATE, IMPRESSIONS, CLICKS, CONVERSIONS,
    REVENUE_ATTRIBUTED, COST, ROAS)
WITH days AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1 AS k FROM TABLE(GENERATOR(ROWCOUNT => 60))
), p AS (
    SELECT c.CAMPAIGN_ID AS id, c.CAMPAIGN_TYPE AS t, c.BUDGET AS budget,
           DATEDIFF('day', c.START_DATE, c.END_DATE) + 1 AS ndays,
           DATEADD('day', d.k, c.START_DATE) AS pdate
    FROM DIM_MARKETING_CAMPAIGN c
    JOIN days d ON d.k <= DATEDIFF('day', c.START_DATE, c.END_DATE)
), m AS (
    SELECT p.*,
        ROUND(budget / ndays * UNIFORM(0.7::FLOAT, 1.3::FLOAT, HASH(id, pdate, 'cost')), 2) AS cost,
        CASE t WHEN 'Email Blast' THEN 10 WHEN 'Loyalty Program' THEN 10 WHEN 'Retargeting' THEN 9
               WHEN 'Brand Awareness' THEN 7 ELSE 12 END AS cpm,
        UNIFORM(0.008::FLOAT, 0.03::FLOAT, HASH(id, pdate, 'ctr')) AS ctr,
        CASE t WHEN 'Retargeting' THEN 0.055 WHEN 'Loyalty Program' THEN 0.05 WHEN 'Email Blast' THEN 0.045
               WHEN 'Seasonal Sale' THEN 0.04 WHEN 'New Launch' THEN 0.03 WHEN 'Influencer' THEN 0.025
               WHEN 'Social Ads' THEN 0.02 ELSE 0.012 END
            * UNIFORM(0.75::FLOAT, 1.25::FLOAT, HASH(id, pdate, 'cvr')) AS cvr,
        UNIFORM(95::FLOAT, 140::FLOAT, HASH(id, pdate, 'aov')) AS aov
    FROM p
), f AS (
    SELECT m.*, ROUND(cost / cpm * 1000) AS impressions FROM m
), f2 AS (
    SELECT f.*, ROUND(impressions * ctr) AS clicks FROM f
), f3 AS (
    SELECT f2.*, ROUND(clicks * cvr) AS conversions FROM f2
)
SELECT
    'PF' || LPAD(ROW_NUMBER() OVER (ORDER BY id, pdate), 7, '0'),
    id, pdate, impressions, clicks, conversions,
    ROUND(conversions * aov, 2),
    cost,
    ROUND(DIV0(conversions * aov, cost), 2)
FROM f3;

-- =========================================================== FACT_DAILY_SALES
-- ~50K transactions. Daily volume has weekend lift, a holiday peak (Black
-- Friday week), a summer bump, a Jan/Feb dip and ~25% YoY growth. Customers
-- only buy between their first and last purchase dates, so lapsed customers
-- stop buying. Popular products are skewed (power-law), wholesale uses
-- wholesale price, markdown items and the holiday sale carry deeper discounts.
INSERT INTO FACT_DAILY_SALES (SALE_ID, SALE_DATE, PRODUCT_ID, STORE_ID, CUSTOMER_ID, CHANNEL, QUANTITY,
    UNIT_PRICE, DISCOUNT_PCT, GROSS_REVENUE, NET_REVENUE, COST_OF_GOODS, RETURN_FLAG)
WITH days AS (
    SELECT DATEADD('day', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2024-10-01'::DATE) AS d
    FROM TABLE(GENERATOR(ROWCOUNT => 365))
), slots AS (
    SELECT d, ROW_NUMBER() OVER (ORDER BY d, s.seq) AS k
    FROM days CROSS JOIN (SELECT SEQ4() AS seq FROM TABLE(GENERATOR(ROWCOUNT => 650))) s
), demand AS (
    SELECT d, k,
        155
        * IFF(DAYOFWEEKISO(d) >= 6, 1.35, 1.0)
        * CASE WHEN d BETWEEN '2024-11-25' AND '2024-12-02' THEN 2.4
               WHEN MONTH(d) IN (11, 12) THEN 1.6
               WHEN MONTH(d) IN (5, 6, 7) THEN 1.15
               WHEN MONTH(d) IN (1, 2)    THEN 0.8
               ELSE 1.0 END
        * (1 + 0.25 * DATEDIFF('day', '2024-10-01', d) / 365) AS expected
    FROM slots
), kept AS (
    SELECT d, k FROM demand
    WHERE UNIFORM(0::FLOAT, 1::FLOAT, HASH(k, 'keep')) < expected / 650
), sellable AS (
    SELECT PRODUCT_ID, MSRP, WHOLESALE_PRICE, UNIT_COST, LIFECYCLE_STAGE,
           ROW_NUMBER() OVER (ORDER BY PRODUCT_ID) AS rn
    FROM DIM_PRODUCT WHERE LIFECYCLE_STAGE IN ('In Market', 'Markdown', 'Retired')
), cnt AS (
    SELECT COUNT(*) AS c FROM sellable
), picks AS (
    SELECT kept.d, kept.k,
        FLOOR(POW(UNIFORM(0::FLOAT, 1::FLOAT, HASH(k, 'prod')), 1.6) * cnt.c) + 1 AS prod_rn,
        'C' || LPAD(UNIFORM(1, 5000, HASH(k, 'cust')), 6, '0') AS customer_id
    FROM kept CROSS JOIN cnt
), tx AS (
    SELECT pk.d, pk.k, pk.customer_id, s.PRODUCT_ID, s.MSRP, s.WHOLESALE_PRICE, s.UNIT_COST, s.LIFECYCLE_STAGE,
        CASE WHEN c.REGION = 'International' THEN 'International DTC'
             WHEN UNIFORM(0, 99, HASH(pk.k, 'chan')) < 50 THEN 'DTC Website'
             WHEN UNIFORM(0, 99, HASH(pk.k, 'chan')) < 85 THEN 'Retail Store'
             ELSE 'Wholesale' END AS channel,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(pk.k, 'qty')) AS uq,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(pk.k, 'disc')) AS ud
    FROM picks pk
    JOIN sellable s     ON s.rn = pk.prod_rn
    JOIN DIM_CUSTOMER c ON c.CUSTOMER_ID = pk.customer_id
    WHERE pk.d BETWEEN c.FIRST_PURCHASE_DATE AND c.LAST_PURCHASE_DATE
), priced AS (
    SELECT tx.*,
        CASE channel WHEN 'DTC Website' THEN 'S00024'
                     WHEN 'International DTC' THEN 'S00025'
                     WHEN 'Wholesale' THEN 'S000' || (21 + UNIFORM(0, 2, HASH(k, 'store')))
                     ELSE 'S' || LPAD(UNIFORM(1, 20, HASH(k, 'store')), 5, '0') END AS store_id,
        CASE WHEN uq < 0.62 THEN 1 WHEN uq < 0.87 THEN 2 WHEN uq < 0.96 THEN 3 ELSE 4 END AS qty,
        IFF(channel = 'Wholesale', WHOLESALE_PRICE, MSRP) AS unit_price,
        CASE WHEN channel = 'Wholesale'                      THEN 0
             WHEN LIFECYCLE_STAGE = 'Markdown'               THEN 0.30
             WHEN d BETWEEN '2024-11-25' AND '2024-12-02'    THEN 0.25
             WHEN ud < 0.70 THEN 0 WHEN ud < 0.85 THEN 0.10 WHEN ud < 0.95 THEN 0.15 ELSE 0.20 END AS disc
    FROM tx
)
SELECT
    'T' || LPAD(k, 9, '0'),
    d, PRODUCT_ID, store_id, customer_id, channel, qty, unit_price, disc,
    ROUND(qty * unit_price, 2),
    ROUND(qty * unit_price * (1 - disc), 2),
    ROUND(qty * UNIT_COST, 2),
    UNIFORM(0::FLOAT, 1::FLOAT, HASH(k, 'return')) < IFF(channel IN ('DTC Website', 'International DTC'), 0.11, 0.05)
FROM priced;

-- ============================================================= FACT_DAILY_KPI
-- Rolled up from FACT_DAILY_SALES by date x channel x customer region, so the
-- KPI table always reconciles with transactions. Conversion rate, marketing
-- spend and inventory turns are modelled (no session/inventory-cost source).
INSERT INTO FACT_DAILY_KPI (KPI_DATE, CHANNEL, REGION, GROSS_REVENUE, NET_REVENUE, ORDERS, UNITS_SOLD,
    AVG_ORDER_VALUE, RETURN_RATE, CONVERSION_RATE, NEW_CUSTOMERS, REPEAT_CUSTOMERS, INVENTORY_TURNS,
    GROSS_MARGIN_PCT, COGS, MARKETING_SPEND, CAC, LTV_TO_CAC_RATIO)
WITH s AS (
    SELECT f.*, c.REGION,
           MIN(f.SALE_DATE) OVER (PARTITION BY f.CUSTOMER_ID) AS first_sale
    FROM FACT_DAILY_SALES f JOIN DIM_CUSTOMER c ON c.CUSTOMER_ID = f.CUSTOMER_ID
), g AS (
    SELECT SALE_DATE AS kpi_date, CHANNEL, REGION,
        SUM(GROSS_REVENUE) AS gross, SUM(NET_REVENUE) AS net, COUNT(*) AS orders, SUM(QUANTITY) AS units,
        AVG(IFF(RETURN_FLAG, 1, 0)) AS return_rate, SUM(COST_OF_GOODS) AS cogs,
        COUNT(DISTINCT IFF(SALE_DATE = first_sale, CUSTOMER_ID, NULL)) AS new_c,
        COUNT(DISTINCT CUSTOMER_ID) AS all_c
    FROM s GROUP BY 1, 2, 3
), m AS (
    SELECT g.*,
        ROUND(net * UNIFORM(0.08::FLOAT, 0.14::FLOAT, HASH(kpi_date, CHANNEL, REGION, 'mkt')), 2) AS mkt_spend
    FROM g
)
SELECT
    kpi_date, CHANNEL, REGION,
    ROUND(gross, 2), ROUND(net, 2), orders, units,
    ROUND(DIV0(net, orders), 2),
    ROUND(return_rate, 4),
    ROUND(CASE CHANNEL WHEN 'Retail Store' THEN 0.22 WHEN 'Wholesale' THEN 0.35 ELSE 0.032 END
          * UNIFORM(0.8::FLOAT, 1.2::FLOAT, HASH(kpi_date, CHANNEL, REGION, 'conv')), 4),
    new_c,
    all_c - new_c,
    ROUND(UNIFORM(4::FLOAT, 9::FLOAT, HASH(kpi_date, CHANNEL, REGION, 'turns')), 2),
    ROUND(DIV0(net - cogs, net), 4),
    ROUND(cogs, 2),
    mkt_spend,
    ROUND(DIV0(mkt_spend, GREATEST(new_c, 1)), 2),
    ROUND(LEAST(99, DIV0(DIV0(net, orders) * 3.5, DIV0(mkt_spend, GREATEST(new_c, 1)))), 2)
FROM m;

-- ================================================ FACT_CUSTOMER_INTERACTIONS (20K)
-- Each product has a latent quality score, so ratings, review text and
-- sentiment are consistent with each other and differ between products.
INSERT INTO FACT_CUSTOMER_INTERACTIONS (INTERACTION_ID, CUSTOMER_ID, INTERACTION_DATE, CHANNEL, INTERACTION_TYPE,
    PRODUCT_ID, PAGE_VIEWS, SESSION_DURATION_SEC, ADDED_TO_CART, PURCHASED, RETURNED, RATING, REVIEW_TEXT,
    SENTIMENT_SCORE, DEVICE_TYPE, REFERRAL_SOURCE)
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 20000))
), sellable AS (
    SELECT PRODUCT_ID, ROW_NUMBER() OVER (ORDER BY PRODUCT_ID) AS rn
    FROM DIM_PRODUCT WHERE LIFECYCLE_STAGE IN ('In Market', 'Markdown', 'Retired')
), cnt AS (
    SELECT COUNT(*) AS c FROM sellable
), r AS (
    SELECT n,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'type')) AS ut,
        FLOOR(POW(UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'prod')), 1.6) * cnt.c) + 1 AS prod_rn,
        'C' || LPAD(UNIFORM(1, 5000, HASH(n, 'cust')), 6, '0') AS customer_id,
        DATEADD('second', UNIFORM(0, 31535999, HASH(n, 'ts')), '2024-10-01'::TIMESTAMP_NTZ) AS ts,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'dev')) AS ud,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'ref')) AS ur,
        UNIFORM(0::FLOAT, 1::FLOAT, HASH(n, 'intl')) AS ui,
        NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'rating')) AS zr,
        NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'sent')) AS zs,
        UNIFORM(1, 20, HASH(n, 'pv')) AS pv,
        UNIFORM(15, 900, HASH(n, 'dur')) AS dur,
        UNIFORM(0, 2, HASH(n, 'txt')) AS txt
    FROM base CROSS JOIN cnt
), t AS (
    SELECT r.*, s.PRODUCT_ID,
        CASE WHEN ut < 0.35 THEN 'Page View'  WHEN ut < 0.47 THEN 'Search'
             WHEN ut < 0.59 THEN 'Add to Cart' WHEN ut < 0.67 THEN 'Purchase'
             WHEN ut < 0.69 THEN 'Return'      WHEN ut < 0.75 THEN 'Review'
             WHEN ut < 0.85 THEN 'Email Click' WHEN ut < 0.90 THEN 'SMS Click'
             ELSE 'Store Visit' END AS itype,
        NORMAL(0::FLOAT, 0.6::FLOAT, HASH(s.PRODUCT_ID, 'quality')) AS quality
    FROM r JOIN sellable s ON s.rn = r.prod_rn
), t2 AS (
    SELECT t.*,
        IFF(itype = 'Review', GREATEST(1, LEAST(5, ROUND(4.1 + quality + 0.8 * zr))), NULL) AS rating
    FROM t
)
SELECT
    'I' || LPAD(n, 9, '0'),
    customer_id,
    ts,
    CASE WHEN itype = 'Store Visit' THEN 'Retail Store'
         WHEN ui < 0.08 THEN 'International DTC'
         ELSE 'DTC Website' END,
    itype,
    PRODUCT_ID,
    IFF(itype = 'Store Visit', 1, pv),
    dur,
    itype IN ('Add to Cart', 'Purchase'),
    itype = 'Purchase',
    itype = 'Return',
    rating,
    CASE WHEN rating = 5 THEN GET(ARRAY_CONSTRUCT('Love the fit and feel!', 'Best joggers I have ever owned.', 'My new favorite brand.'), txt)::STRING
         WHEN rating = 4 THEN GET(ARRAY_CONSTRUCT('Great for workouts and everyday wear.', 'Fabric is incredibly soft.', 'Perfect for travel.'), txt)::STRING
         WHEN rating = 3 THEN GET(ARRAY_CONSTRUCT('Runs a bit large, otherwise great.', 'A bit pricey but worth it.', 'Nice fabric, sizing is inconsistent.'), txt)::STRING
         WHEN rating <= 2 THEN GET(ARRAY_CONSTRUCT('Color faded after a few washes.', 'The quality has gone down recently.', 'Seams started coming apart after a month.'), txt)::STRING
    END,
    IFF(rating IS NULL, NULL, ROUND(GREATEST(-1, LEAST(1, (rating - 3) / 2 + 0.2 * zs)), 4)),
    CASE WHEN itype = 'Store Visit' THEN 'In-Store'
         WHEN ud < 0.58 THEN 'Mobile' WHEN ud < 0.92 THEN 'Desktop' ELSE 'Tablet' END,
    CASE WHEN itype = 'Email Click' THEN 'Email'
         WHEN itype IN ('Store Visit', 'SMS Click') THEN 'Direct'
         WHEN ur < 0.25 THEN 'Organic Search' WHEN ur < 0.45 THEN 'Paid Search'
         WHEN ur < 0.65 THEN 'Social Media'   WHEN ur < 0.85 THEN 'Direct'
         WHEN ur < 0.92 THEN 'Referral'       ELSE 'Influencer' END
FROM t2;

-- ==================================================== FACT_INVENTORY_SNAPSHOT
-- 52 weekly snapshots x 120 most popular products x 8 retail stores.
-- Holiday weeks draw stock down, producing more stockouts in Nov/Dec.
INSERT INTO FACT_INVENTORY_SNAPSHOT (SNAPSHOT_DATE, PRODUCT_ID, STORE_ID, ON_HAND_QTY, IN_TRANSIT_QTY,
    ALLOCATED_QTY, WEEKS_OF_SUPPLY, REORDER_POINT, STOCKOUT_FLAG)
WITH weeks AS (
    SELECT DATEADD('week', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2024-10-07'::DATE) AS wk
    FROM TABLE(GENERATOR(ROWCOUNT => 52))
), prods AS (
    SELECT PRODUCT_ID FROM DIM_PRODUCT
    WHERE LIFECYCLE_STAGE IN ('In Market', 'Markdown', 'Retired')
    ORDER BY PRODUCT_ID LIMIT 120
), strs AS (
    SELECT STORE_ID FROM DIM_STORE WHERE CHANNEL = 'Retail Store' ORDER BY STORE_ID LIMIT 8
), g AS (
    SELECT w.wk, p.PRODUCT_ID, s.STORE_ID,
        UNIFORM(4::FLOAT, 15::FLOAT, HASH(p.PRODUCT_ID, s.STORE_ID, 'rate')) AS weekly_rate,
        GREATEST(0, ROUND(60 - IFF(MONTH(w.wk) IN (11, 12), 28, 0)
                          + 28 * NORMAL(0::FLOAT, 1::FLOAT, HASH(w.wk, p.PRODUCT_ID, s.STORE_ID, 'oh')))) AS on_hand,
        GREATEST(0, ROUND(20 + 10 * NORMAL(0::FLOAT, 1::FLOAT, HASH(w.wk, p.PRODUCT_ID, s.STORE_ID, 'it')))) AS in_transit,
        GREATEST(0, ROUND(10 + 5 * NORMAL(0::FLOAT, 1::FLOAT, HASH(w.wk, p.PRODUCT_ID, s.STORE_ID, 'al')))) AS allocated
    FROM weeks w CROSS JOIN prods p CROSS JOIN strs s
)
SELECT wk, PRODUCT_ID, STORE_ID, on_hand, in_transit, allocated,
       ROUND(on_hand / weekly_rate, 1), ROUND(weekly_rate * 3), on_hand = 0
FROM g;

-- ======================================================= FACT_DEMAND_FORECAST
-- 12 months x 100 products x 6 stores. Model v1.0 (Oct-Mar) has ~22% error;
-- the improved v2.1 (Apr-Sep) has ~11% error — a nice "model improvement" story.
INSERT INTO FACT_DEMAND_FORECAST (FORECAST_ID, FORECAST_DATE, PRODUCT_ID, STORE_ID, SEASON, FORECAST_QTY,
    ACTUAL_QTY, FORECAST_REVENUE, ACTUAL_REVENUE, MODEL_VERSION, MAPE)
WITH months AS (
    SELECT DATEADD('month', ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2024-10-01'::DATE) AS m
    FROM TABLE(GENERATOR(ROWCOUNT => 12))
), prods AS (
    SELECT PRODUCT_ID, MSRP FROM DIM_PRODUCT
    WHERE LIFECYCLE_STAGE IN ('In Market', 'Markdown', 'Retired')
    ORDER BY PRODUCT_ID LIMIT 100
), strs AS (
    SELECT STORE_ID FROM DIM_STORE WHERE CHANNEL = 'Retail Store' ORDER BY STORE_ID LIMIT 6
), a AS (
    SELECT mo.m, p.PRODUCT_ID, p.MSRP, s.STORE_ID,
        IFF(mo.m < '2025-04-01', 'v1.0', 'v2.1') AS model_version,
        GREATEST(0, ROUND(UNIFORM(25::FLOAT, 120::FLOAT, HASH(p.PRODUCT_ID, s.STORE_ID, 'base'))
            * CASE MONTH(mo.m) WHEN 11 THEN 1.6 WHEN 12 THEN 1.8 WHEN 1 THEN 0.8 WHEN 2 THEN 0.8
                               WHEN 5 THEN 1.15 WHEN 6 THEN 1.15 WHEN 7 THEN 1.15 ELSE 1.0 END
            * (1 + 0.12 * NORMAL(0::FLOAT, 1::FLOAT, HASH(mo.m, p.PRODUCT_ID, s.STORE_ID, 'act'))))) AS actual_qty,
        NORMAL(0::FLOAT, 1::FLOAT, HASH(mo.m, p.PRODUCT_ID, s.STORE_ID, 'err')) AS z_err
    FROM months mo CROSS JOIN prods p CROSS JOIN strs s
), f AS (
    SELECT a.*,
        GREATEST(1, ROUND(actual_qty * (1 + IFF(model_version = 'v1.0', 0.22, 0.11) * z_err))) AS forecast_qty
    FROM a
)
SELECT
    'FC' || LPAD(ROW_NUMBER() OVER (ORDER BY m, PRODUCT_ID, STORE_ID), 7, '0'),
    m, PRODUCT_ID, STORE_ID,
    CASE WHEN MONTH(m) <= 4 THEN 'Spring' WHEN MONTH(m) <= 8 THEN 'Summer'
         WHEN MONTH(m) <= 10 THEN 'Fall' ELSE 'Holiday' END || ' ' || YEAR(m),
    forecast_qty, actual_qty,
    ROUND(forecast_qty * MSRP * 0.82, 2),
    ROUND(actual_qty * MSRP * 0.82, 2),
    model_version,
    ROUND(ABS(forecast_qty - actual_qty) / NULLIF(actual_qty, 0), 4)
FROM f;

-- ============================================================ ASSORTMENT_PLAN (200)
-- Closed seasons have full actuals; Fall 2025 is in season (partial);
-- Holiday 2025 is still being planned (no actuals). Markdown rises as
-- sell-through falls.
INSERT INTO ASSORTMENT_PLAN (PLAN_ID, SEASON, STORE_ID, CATEGORY, PRODUCT_LINE, PLANNED_STYLES, PLANNED_UNITS,
    PLANNED_REVENUE, ACTUAL_STYLES, ACTUAL_UNITS, ACTUAL_REVENUE, SELL_THROUGH_PCT, MARKDOWN_PCT, PLAN_STATUS)
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 200))
), a AS (
    SELECT n,
        GET(ARRAY_CONSTRUCT('Spring 2024','Summer 2024','Fall 2024','Holiday 2024','Spring 2025','Summer 2025',
                            'Fall 2025','Holiday 2025'), UNIFORM(0, 7, HASH(n, 'season')))::STRING AS season,
        'S' || LPAD(UNIFORM(1, 20, HASH(n, 'store')), 5, '0') AS store_id,
        GET(ARRAY_CONSTRUCT('Men''s Tops','Men''s Bottoms','Men''s Outerwear','Women''s Tops','Women''s Bottoms',
                            'Women''s Outerwear','Women''s Accessories'), UNIFORM(0, 6, HASH(n, 'cat')))::STRING AS category,
        GET(ARRAY_CONSTRUCT('Performance','Everyday','Sunday','Banks','Ponto','DreamKnit'),
            UNIFORM(0, 5, HASH(n, 'line')))::STRING AS line,
        UNIFORM(5, 30, HASH(n, 'styles')) AS planned_styles,
        ROUND(UNIFORM(200, 4000, HASH(n, 'units')), -1) AS planned_units,
        UNIFORM(60::FLOAT, 130::FLOAT, HASH(n, 'price')) AS avg_price,
        LEAST(1.0, UNIFORM(0.6::FLOAT, 1.12::FLOAT, HASH(n, 'st'))) AS st_full,
        UNIFORM(0.8::FLOAT, 1.05::FLOAT, HASH(n, 'astyles')) AS style_ratio,
        NORMAL(0::FLOAT, 1::FLOAT, HASH(n, 'md')) AS z_md,
        UNIFORM(0, 1, HASH(n, 'status')) AS status_roll
    FROM base
), b AS (
    SELECT a.*,
        season = 'Holiday 2025' AS is_future,
        season = 'Fall 2025'    AS in_season,
        st_full * IFF(season = 'Fall 2025', 0.55, 1.0) AS st
    FROM a
), c AS (
    SELECT b.*,
        IFF(is_future, NULL, GREATEST(0, LEAST(0.4, 0.42 - 0.38 * st + 0.05 * z_md))) AS markdown,
        IFF(is_future, NULL, ROUND(planned_units * st)) AS actual_units
    FROM b
)
SELECT
    'AP' || LPAD(n, 5, '0'),
    season, store_id, category, line,
    planned_styles, planned_units, ROUND(planned_units * avg_price, 2),
    IFF(is_future, NULL, GREATEST(1, ROUND(planned_styles * style_ratio))),
    actual_units,
    IFF(is_future, NULL, ROUND(actual_units * avg_price * (1 - markdown * 0.5), 2)),
    IFF(is_future, NULL, ROUND(st, 4)),
    ROUND(markdown, 4),
    CASE WHEN is_future THEN IFF(status_roll = 0, 'Draft', 'Approved')
         WHEN in_season THEN 'In Season'
         ELSE 'Closed' END
FROM c;

-- ================================================ PRODUCT_DEVELOPMENT_PIPELINE (80)
INSERT INTO PRODUCT_DEVELOPMENT_PIPELINE (PIPELINE_ID, PRODUCT_NAME, PRODUCT_LINE, CATEGORY, DESIGNER,
    TARGET_SEASON, CURRENT_STAGE, STAGE_ENTRY_DATE, TARGET_LAUNCH_DATE, ESTIMATED_COST, SUSTAINABILITY_CERT,
    MATERIAL_INNOVATION, RISK_LEVEL, NOTES)
WITH base AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS n FROM TABLE(GENERATOR(ROWCOUNT => 80))
), a AS (
    SELECT n,
        GET(ARRAY_CONSTRUCT('Performance','Everyday','Sunday','Banks','Ponto','Clementine','Riviera','Halo',
                            'DreamKnit','BlueLine'), UNIFORM(0, 9, HASH(n, 'line')))::STRING AS line,
        GET(ARRAY_CONSTRUCT('Men''s Tops','Men''s Bottoms','Women''s Tops','Women''s Bottoms','Women''s Outerwear',
                            'Women''s Accessories'), UNIFORM(0, 5, HASH(n, 'cat')))::STRING AS category,
        GET(ARRAY_CONSTRUCT('Concept','Design','Sampling','Tech Pack Review','Pre-Production','Production','In Market'),
            UNIFORM(0, 6, HASH(n, 'stage')))::STRING AS stage,
        UNIFORM(0, 2, HASH(n, 'risk')) AS risk_idx,
        DATEADD('day', UNIFORM(0, 240, HASH(n, 'entry')), '2025-01-15'::DATE) AS entry_date,
        UNIFORM(60, 300, HASH(n, 'lead')) AS lead_days
    FROM base
)
SELECT
    'PD' || LPAD(n, 4, '0'),
    line || ' ' || SPLIT_PART(category, ' ', 2) || ' Next Gen',
    line,
    category,
    GET(ARRAY_CONSTRUCT('Alex Chen','Sam Rivera','Jordan Lee','Taylor Kim','Morgan Patel','Casey Nguyen',
                        'Drew Santos','Riley Thompson','Avery Mitchell','Quinn Harper'), UNIFORM(0, 9, HASH(n, 'designer')))::STRING,
    CASE WHEN stage IN ('Concept', 'Design') THEN 'Fall 2026'
         WHEN stage IN ('Sampling', 'Tech Pack Review') THEN 'Summer 2026'
         WHEN stage = 'Pre-Production' THEN 'Spring 2026'
         ELSE 'Holiday 2025' END,
    stage,
    entry_date,
    DATEADD('day', lead_days, entry_date),
    ROUND(UNIFORM(8::FLOAT, 45::FLOAT, HASH(n, 'cost')), 2),
    GET(ARRAY_CONSTRUCT('bluesign', 'OEKO-TEX', 'GOTS', 'GRS', NULL, NULL), UNIFORM(0, 5, HASH(n, 'cert')))::STRING,
    GET(ARRAY_CONSTRUCT('Bio-based nylon from castor beans', 'Recycled ocean plastic fiber', 'Plant-based dye process',
                        'Zero-waste pattern cutting', 'Graphene-infused moisture wicking', 'Seaweed-based Lyocell',
                        'Regenerative cotton sourcing', NULL, NULL), UNIFORM(0, 8, HASH(n, 'innov')))::STRING,
    GET(ARRAY_CONSTRUCT('Low', 'Medium', 'High'), risk_idx)::STRING,
    CASE risk_idx
        WHEN 0 THEN 'Progressing on schedule; supplier samples approved.'
        WHEN 1 THEN 'Fit adjustments requested after wear test; one extra sample round expected.'
        ELSE 'Material sourcing delay - alternate mill being evaluated; launch date at risk.' END
FROM a;

DROP TABLE IF EXISTS _CUSTOMER_BASE;

-- ================================================================ row counts
SELECT TABLE_NAME, ROW_COUNT
FROM RETAIL_ATHLETIC_DEMO.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'PUBLIC' AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
