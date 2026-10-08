-- =============================================================================
-- Player 360 Demo — Step 3: Analytic views and dynamic tables
-- Run AFTER 02_load_data.sql.
--
-- Dynamic tables use PLAYER_360_BUILD_WH by default.
-- Change this to your warehouse or create:
--   CREATE WAREHOUSE IF NOT EXISTS PLAYER_360_BUILD_WH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60;
-- =============================================================================

-- Create the build warehouse for dynamic tables (skip if you already have one)
CREATE WAREHOUSE IF NOT EXISTS PLAYER_360_BUILD_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

USE SCHEMA PLAYER_360.ANALYTIC;

-- ============================================================
-- Dynamic Table: AD_ENGAGEMENT (per-user ad metrics)
-- ============================================================
CREATE OR REPLACE DYNAMIC TABLE AD_ENGAGEMENT
    TARGET_LAG = '5 minutes'
    WAREHOUSE = PLAYER_360_BUILD_WH
AS
SELECT
    USER_ID,
    COUNT(AD_INTERACTION_ID) AS total_ads,
    COUNT(CASE WHEN PURCHASE_TYPE != 'none' THEN PURCHASE_ID END) AS total_purchases,
    SUM(PURCHASE_AMOUNT) AS total_purchases_amount,
    COALESCE(NULLIF(COUNT(CASE WHEN PURCHASE_TYPE != 'none' THEN PURCHASE_ID END), 0)
        / NULLIF(COUNT(AD_INTERACTION_ID), 0), 0) AS proportion_purchased,
    COALESCE(AVG(CASE WHEN PURCHASE_TYPE != 'none' THEN PURCHASE_AMOUNT END),0) AS average_purchase_amount,
    AVG(AD_ENGAGEMENT_TIME) AS average_ad_engagement_time,
    COUNT(CASE WHEN TIMESTAMP_OF_PURCHASE >= CURRENT_DATE - INTERVAL '30 DAYS' THEN AD_INTERACTION_ID END) AS total_ads_last_30_days,
    COUNT(CASE WHEN TIMESTAMP_OF_PURCHASE >= CURRENT_DATE - INTERVAL '30 DAYS'
                AND PURCHASE_TYPE != 'none' THEN PURCHASE_ID END) AS total_purchases_last_30_days,
    SUM(CASE WHEN TIMESTAMP_OF_PURCHASE >= CURRENT_DATE - INTERVAL '30 DAYS'
            THEN PURCHASE_AMOUNT END) AS total_purchases_amount_last_30_days,
    COALESCE(NULLIF(COUNT(CASE WHEN TIMESTAMP_OF_PURCHASE >= CURRENT_DATE - INTERVAL '30 DAYS'
                                AND PURCHASE_TYPE != 'none' THEN PURCHASE_ID END), 0)
        / NULLIF(COUNT(CASE WHEN TIMESTAMP_OF_PURCHASE >= CURRENT_DATE - INTERVAL '30 DAYS' THEN AD_INTERACTION_ID END), 0), 0)
        AS proportion_purchased_last_30_days,
    COALESCE(AVG(CASE
                 WHEN TIMESTAMP_OF_PURCHASE >= CURRENT_DATE - INTERVAL '30 DAYS'
                      AND PURCHASE_TYPE != 'none'
                 THEN PURCHASE_AMOUNT
             END), 0) AS average_purchase_amount_last_30_days,
    AVG(CASE WHEN TIMESTAMP_OF_PURCHASE >= CURRENT_DATE - INTERVAL '30 DAYS'
              THEN AD_ENGAGEMENT_TIME END) AS average_ad_engagement_time_last_30_days
FROM PLAYER_360.RAW.PURCHASES
GROUP BY USER_ID;

-- ============================================================
-- Dynamic Table: DEMOGRAPHICS (player profile summary)
-- ============================================================
CREATE OR REPLACE DYNAMIC TABLE DEMOGRAPHICS
    TARGET_LAG = '1 day'
    WAREHOUSE = PLAYER_360_BUILD_WH
AS
WITH user_activity AS (
    SELECT
        e.USER_ID,
        COUNT(e.LOG_IN) AS total_sessions,
        SUM(e.SESSION_DURATION_MINUTES) AS total_session_duration,
        COUNT(DISTINCT(DATE_TRUNC('week', e.LOG_IN))) AS active_weeks,
        total_sessions/active_weeks AS average_sessions_per_active_week,
        total_session_duration/total_sessions AS average_session_duration
    FROM PLAYER_360.RAW.SESSIONS e
    GROUP BY e.USER_ID
), user_spending AS (
    SELECT
        p.USER_ID,
        COUNT(p.PURCHASE_ID) AS total_ads,
        IFF(COUNT(CASE WHEN p.PURCHASE_TYPE != 'none' THEN p.PURCHASE_ID END) > 2, TRUE, FALSE) AS is_spender,
        COALESCE(AVG(p.PURCHASE_AMOUNT), 0) AS avg_purchase_amount_per_ad
    FROM PLAYER_360.RAW.PURCHASES p
    GROUP BY p.USER_ID
), user_engagement AS (
    SELECT
        ua.USER_ID,
        ua.total_sessions,
        ua.active_weeks,
        CASE
            WHEN ua.total_sessions / ua.active_weeks > 15 THEN 'Hardcore'
            ELSE 'Casual'
        END AS player_type
    FROM user_activity ua
)
SELECT
    u.USER_ID,
    CONCAT(u.FIRST_NAME, ' ', u.LAST_NAME) AS full_name,
    DATEDIFF(year, u.BIRTHDATE, CURRENT_DATE()) AS age,
    u.GENDER,
    u.LOCATION,
    ue.player_type,
    ua.average_sessions_per_active_week,
    ua.average_session_duration,
    us.total_ads,
    us.is_spender,
    us.avg_purchase_amount_per_ad,
    st.USER_ID IS NOT NULL AS has_support_ticket
FROM PLAYER_360.RAW.USERS u
LEFT JOIN user_engagement ue ON u.USER_ID = ue.USER_ID
LEFT JOIN user_spending us ON u.USER_ID = us.USER_ID
LEFT JOIN user_activity ua ON u.USER_ID = ua.USER_ID
LEFT JOIN PLAYER_360.RAW.SUPPORT_TICKETS st ON u.USER_ID = st.USER_ID;

-- ============================================================
-- Dynamic Table: RETENTION (player retention and churn)
-- ============================================================
CREATE OR REPLACE DYNAMIC TABLE RETENTION
    TARGET_LAG = '1 day'
    WAREHOUSE = PLAYER_360_BUILD_WH
AS
WITH first_login AS (
    SELECT
        USER_ID,
        MIN(LOG_IN) AS first_login_date,
        MAX(LOG_IN) AS last_login_date,
        COUNT(*) AS total_logins
    FROM PLAYER_360.RAW.SESSIONS
    GROUP BY USER_ID
), login_activity AS (
    SELECT
        f.USER_ID,
        f.first_login_date,
        f.last_login_date,
        f.total_logins,
        IFF(MAX(DATEDIFF(day, f.first_login_date, e.LOG_IN) >= 1), TRUE, FALSE) AS logged_in_after_1_day,
        IFF(MAX(DATEDIFF(day, f.first_login_date, e.LOG_IN) >= 7), TRUE, FALSE) AS logged_in_after_7_days,
        IFF(MAX(DATEDIFF(day, f.first_login_date, e.LOG_IN) >= 30), TRUE, FALSE) AS logged_in_after_30_days,
        IFF(MAX(e.LOG_IN >= DATEADD(day, -30, CURRENT_DATE())), TRUE, FALSE) AS logged_in_in_last_30_days,
        DATEDIFF(day, f.last_login_date, CURRENT_DATE()) AS days_since_last_login
    FROM first_login f
    LEFT JOIN PLAYER_360.RAW.SESSIONS e ON e.USER_ID = f.USER_ID
    GROUP BY f.USER_ID, f.first_login_date, f.last_login_date, f.total_logins
)
SELECT *,
    IFF(days_since_last_login > 30, 1, 0) AS churned
FROM login_activity;

-- ============================================================
-- Dynamic Table: POINTS_PER_EVENT (points for each session)
-- ============================================================
CREATE OR REPLACE DYNAMIC TABLE POINTS_PER_EVENT
    TARGET_LAG = '5 minutes'
    WAREHOUSE = PLAYER_360_BUILD_WH
AS
WITH player_points_per_event AS (
    SELECT
        ge.USER_ID,
        ge.SESSION_ID,
        ge.ASSISTS * (SELECT points FROM POINTS_MAPPING_TABLE WHERE event = 'Assists') AS assist_points,
        ge.BOOSTS * (SELECT points FROM POINTS_MAPPING_TABLE WHERE event = 'Boosts') AS boost_points,
        ge.DAMAGE_DEALT * (SELECT points FROM POINTS_MAPPING_TABLE WHERE event = 'Damage Dealt') AS damage_points,
        ge.DISTANCE_TRAVELED * (SELECT points FROM POINTS_MAPPING_TABLE WHERE event = 'Distance Traveled') AS distance_points,
        ge.KILLS * (SELECT points FROM POINTS_MAPPING_TABLE WHERE event = 'Kills') AS kill_points,
        ge.WEAPONS_ACQUIRED * (SELECT points FROM POINTS_MAPPING_TABLE WHERE event = 'Weapons Acquired') AS weapon_points,
        ge.HEADSHOTS * (SELECT points FROM POINTS_MAPPING_TABLE WHERE event = 'Head Shots') AS headshot_points,
        ge.HEALS * (SELECT points FROM POINTS_MAPPING_TABLE WHERE event = 'Heals') AS heals_points
    FROM PLAYER_360.RAW.GAME_EVENTS ge
), player_points_per_session AS (
    SELECT
        USER_ID, SESSION_ID,
        SUM(assist_points) AS ASSISTS_POINTS,
        SUM(boost_points) AS BOOSTS_POINTS,
        SUM(damage_points) AS DAMAGE_POINTS,
        SUM(distance_points) AS DISTANCE_POINTS,
        SUM(kill_points) AS KILLS_POINTS,
        SUM(weapon_points) AS WEAPONS_POINTS,
        SUM(headshot_points) AS HEADSHOTS_POINTS,
        SUM(heals_points) AS HEALS_POINTS,
        SUM(assist_points + boost_points + damage_points + distance_points + kill_points + weapon_points + headshot_points + heals_points) AS TOTAL_POINTS
    FROM player_points_per_event
    GROUP BY USER_ID, SESSION_ID
)
SELECT
    pps.USER_ID, pps.SESSION_ID,
    s.LOG_IN, s.LOG_OUT, s.SESSION_DURATION_MINUTES,
    ASSISTS_POINTS, BOOSTS_POINTS, DAMAGE_POINTS, DISTANCE_POINTS,
    KILLS_POINTS, WEAPONS_POINTS, HEADSHOTS_POINTS, HEALS_POINTS, TOTAL_POINTS
FROM player_points_per_session pps
LEFT JOIN PLAYER_360.RAW.SESSIONS s ON pps.SESSION_ID = s.SESSION_ID::VARCHAR;

-- ============================================================
-- Dynamic Table: POINTS_PER_USER (total points per player)
-- ============================================================
CREATE OR REPLACE DYNAMIC TABLE POINTS_PER_USER
    TARGET_LAG = '5 minutes'
    WAREHOUSE = PLAYER_360_BUILD_WH
AS
SELECT
    USER_ID,
    SUM(COALESCE(ASSISTS_POINTS, 0)) AS ASSISTS_POINTS,
    SUM(COALESCE(BOOSTS_POINTS, 0)) AS BOOSTS_POINTS,
    SUM(COALESCE(DAMAGE_POINTS, 0)) AS DAMAGE_POINTS,
    SUM(COALESCE(DISTANCE_POINTS, 0)) AS DISTANCE_POINTS,
    SUM(COALESCE(KILLS_POINTS, 0)) AS KILLS_POINTS,
    SUM(COALESCE(WEAPONS_POINTS, 0)) AS WEAPONS_POINTS,
    SUM(COALESCE(HEADSHOTS_POINTS, 0)) AS HEADSHOTS_POINTS,
    SUM(COALESCE(HEALS_POINTS, 0)) AS HEALS_POINTS,
    SUM(
        COALESCE(ASSISTS_POINTS, 0) + COALESCE(BOOSTS_POINTS, 0) +
        COALESCE(DAMAGE_POINTS, 0) + COALESCE(DISTANCE_POINTS, 0) +
        COALESCE(KILLS_POINTS, 0) + COALESCE(WEAPONS_POINTS, 0) +
        COALESCE(HEADSHOTS_POINTS, 0) + COALESCE(HEALS_POINTS, 0)
    ) AS TOTAL_POINTS
FROM PLAYER_360.ANALYTIC.POINTS_PER_EVENT
GROUP BY USER_ID
ORDER BY USER_ID;

-- ============================================================
-- Dynamic Table: USER_RANKINGS (rank tiers based on points)
-- ============================================================
CREATE OR REPLACE DYNAMIC TABLE USER_RANKINGS
    TARGET_LAG = '1 day'
    WAREHOUSE = PLAYER_360_BUILD_WH
AS
WITH RankedPlayers AS (
    SELECT
        utp.USER_ID,
        utp.TOTAL_POINTS,
        drm.RANK_NAME,
        RANK() OVER (ORDER BY utp.TOTAL_POINTS DESC) AS PlayerRank,
        COUNT(*) OVER () AS TotalPlayers
    FROM PLAYER_360.ANALYTIC.POINTS_PER_USER utp
    LEFT JOIN PLAYER_360.ANALYTIC.RANKING_MAPPING_TABLE drm
        ON utp.TOTAL_POINTS >= drm.LOWER_BOUND
        AND utp.TOTAL_POINTS < drm.UPPER_BOUND
)
SELECT
    USER_ID, TOTAL_POINTS, RANK_NAME,
    ((PlayerRank - 1) / CAST(TotalPlayers AS FLOAT)) * 100 AS PERCENTILE
FROM RankedPlayers
ORDER BY USER_ID;

-- ============================================================
-- Views (analytics views built on top of raw + analytic tables)
-- ============================================================

CREATE OR REPLACE VIEW AD_CONVERSION_OVER_TIME AS
SELECT
    TO_CHAR(p.TIMESTAMP_OF_PURCHASE, 'YYYY-MM') AS Month,
    p.AD_TYPE,
    COUNT(p.AD_INTERACTION_ID) AS Total_Ads,
    COUNT(DISTINCT CASE WHEN p.PURCHASE_TYPE != 'none' THEN p.PURCHASE_ID END) AS PURCHASED_ADS,
    (COUNT(DISTINCT CASE WHEN p.PURCHASE_TYPE != 'none' THEN p.PURCHASE_ID END) * 1.0 / COUNT(p.AD_INTERACTION_ID)) AS Ad_Conversion_Rate
FROM PLAYER_360.RAW.PURCHASES p
GROUP BY TO_CHAR(p.TIMESTAMP_OF_PURCHASE, 'YYYY-MM'), p.AD_TYPE
ORDER BY Month DESC, p.AD_TYPE DESC;

CREATE OR REPLACE VIEW ARPDAU AS
SELECT
    dau.ACTIVE_DATE,
    COALESCE(SUM(p.PURCHASE_AMOUNT), 0) AS total_revenue,
    dau.ACTIVE_USER_COUNT,
    CASE WHEN dau.ACTIVE_USER_COUNT > 0 THEN SUM(p.PURCHASE_AMOUNT) / dau.ACTIVE_USER_COUNT ELSE 0 END AS arp_dau
FROM PLAYER_360.ANALYTIC.DAILY_ACTIVE_USERS dau
LEFT JOIN PLAYER_360.RAW.PURCHASES p ON CAST(p.TIMESTAMP_OF_PURCHASE AS DATE) = dau.ACTIVE_DATE
GROUP BY dau.ACTIVE_DATE, dau.ACTIVE_USER_COUNT
ORDER BY dau.ACTIVE_DATE DESC;

CREATE OR REPLACE VIEW COHORT_CLTV AS
WITH CohortData AS (
    SELECT u.USER_ID, TO_CHAR(u.ACCOUNT_CREATION, 'YYYY-MM') AS CohortMonth,
           p.PURCHASE_AMOUNT, p.TIMESTAMP_OF_PURCHASE, u.ACCOUNT_CREATION
    FROM PLAYER_360.RAW.USERS u
    LEFT JOIN PLAYER_360.RAW.PURCHASES p ON u.USER_ID = p.USER_ID
    WHERE u.CONSENT = TRUE
), CohortRevenue AS (
    SELECT CohortMonth, SUM(PURCHASE_AMOUNT) AS TotalRevenue,
           COUNT(DISTINCT USER_ID) AS TotalPlayers, MIN(ACCOUNT_CREATION) AS CohortStartDate
    FROM CohortData GROUP BY CohortMonth
), CohortLTV AS (
    SELECT CohortMonth, TotalRevenue, TotalPlayers, (TotalRevenue / TotalPlayers) AS LTV, CohortStartDate
    FROM CohortRevenue
)
SELECT CohortMonth AS Cohort_Month, TotalRevenue AS Total_Revenue, TotalPlayers AS Total_Players,
       LTV, MONTHS_BETWEEN(CURRENT_DATE, CohortStartDate) AS Months_Active,
       (TotalRevenue / NULLIF(MONTHS_BETWEEN(CURRENT_DATE, CohortStartDate), 0)) AS Normalized_LTV
FROM CohortLTV ORDER BY CohortMonth;

CREATE OR REPLACE VIEW COUNTRY_COUNT AS
SELECT LOCATION AS COUNTRY, COUNT(USER_ID) AS TOTAL_PLAYERS
FROM PLAYER_360.RAW.USERS GROUP BY LOCATION;

CREATE OR REPLACE VIEW DAILY_CHURN_RATE AS
WITH ActiveUsers AS (
    SELECT DATE(LOG_IN) AS log_in_date, USER_ID
    FROM PLAYER_360.RAW.SESSIONS GROUP BY DATE(LOG_IN), USER_ID
), ChurnedUsers AS (
    SELECT a.USER_ID, a.log_in_date
    FROM ActiveUsers a
    LEFT JOIN ActiveUsers b ON a.USER_ID = b.USER_ID AND b.log_in_date = DATEADD(DAY, -1, a.log_in_date)
    WHERE b.USER_ID IS NULL
), DailyStats AS (
    SELECT a.log_in_date, COUNT(DISTINCT a.USER_ID) AS active_users, COUNT(DISTINCT c.USER_ID) AS churned_users
    FROM ActiveUsers a LEFT JOIN ChurnedUsers c ON a.USER_ID = c.USER_ID AND a.log_in_date = c.log_in_date
    GROUP BY a.log_in_date
), EarliestDate AS (
    SELECT MIN(DATE(LOG_IN)) AS earliest_date FROM PLAYER_360.RAW.SESSIONS
)
SELECT log_in_date, churned_users, active_users,
       CASE WHEN active_users > 0 THEN (churned_users::FLOAT / active_users::FLOAT) * 100 ELSE NULL END AS churn_rate_percentage
FROM DailyStats ds JOIN EarliestDate ed ON ds.log_in_date != ed.earliest_date
ORDER BY log_in_date;

CREATE OR REPLACE VIEW DARPPU AS
SELECT
    dau.ACTIVE_DATE,
    COALESCE(SUM(p.PURCHASE_AMOUNT), 0) AS total_revenue_from_paying_users,
    COUNT(DISTINCT p.USER_ID) AS total_paying_users,
    CASE WHEN COUNT(DISTINCT p.USER_ID) > 0 THEN SUM(p.PURCHASE_AMOUNT) / COUNT(DISTINCT p.USER_ID) ELSE 0 END AS darppu
FROM PLAYER_360.ANALYTIC.DAILY_ACTIVE_USERS dau
LEFT JOIN PLAYER_360.RAW.PURCHASES p ON CAST(p.TIMESTAMP_OF_PURCHASE AS DATE) = dau.ACTIVE_DATE AND p.PURCHASE_TYPE != 'none'
GROUP BY dau.ACTIVE_DATE
ORDER BY dau.ACTIVE_DATE DESC;

CREATE OR REPLACE VIEW MONTHLY_CHURN_RATE AS
WITH ActiveUsers AS (
    SELECT EXTRACT(YEAR, LOG_IN) AS year, EXTRACT(MONTH, LOG_IN) AS month, USER_ID
    FROM PLAYER_360.RAW.SESSIONS GROUP BY 1, 2, USER_ID
), ChurnedUsers AS (
    SELECT a.year, a.month, a.USER_ID
    FROM ActiveUsers a LEFT JOIN ActiveUsers b ON a.USER_ID = b.USER_ID AND a.year = b.year AND a.month = b.month + 1
    WHERE b.USER_ID IS NULL
), MonthlyStats AS (
    SELECT a.year, a.month, COUNT(DISTINCT a.USER_ID) AS active_users, COUNT(DISTINCT c.USER_ID) AS churned_users
    FROM ActiveUsers a LEFT JOIN ChurnedUsers c ON a.USER_ID = c.USER_ID AND a.year = c.year AND a.month = c.month
    GROUP BY a.year, a.month
), EarliestMonth AS (
    SELECT MIN(year) AS earliest_year, MIN(month) AS earliest_month FROM ActiveUsers
)
SELECT ms.year, ms.month, ms.churned_users, ms.active_users,
       CASE WHEN ms.active_users > 0 THEN (ms.churned_users::FLOAT / ms.active_users::FLOAT) * 100 ELSE NULL END AS churn_rate_percentage
FROM MonthlyStats ms
JOIN EarliestMonth em ON NOT (ms.year = em.earliest_year AND ms.month = em.earliest_month)
ORDER BY year, month;
