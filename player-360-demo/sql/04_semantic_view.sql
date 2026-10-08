-- =============================================================================
-- Player 360 Demo — Step 4: Semantic View
-- Run AFTER 03_analytic_objects.sql (dynamic tables must exist).
-- =============================================================================

USE SCHEMA PLAYER_360.APP;

CREATE OR REPLACE SEMANTIC VIEW PLAYER_360_SEMANTIC_VIEW
    TABLES (
        PLAYER_360.RAW.USERS PRIMARY KEY (USER_ID)
            COMMENT = 'Player accounts with profile information',
        PLAYER_360.RAW.SESSIONS PRIMARY KEY (SESSION_ID)
            COMMENT = 'Player login sessions with duration and device info',
        PLAYER_360.RAW.PURCHASES PRIMARY KEY (PURCHASE_ID)
            COMMENT = 'In-game purchases and ad interactions',
        PLAYER_360.RAW.GAME_EVENTS PRIMARY KEY (MATCH_ID, USER_ID)
            COMMENT = 'In-game match performance data',
        PLAYER_360.ANALYTIC.DEMOGRAPHICS PRIMARY KEY (USER_ID)
            COMMENT = 'Player demographic and behavioral profile summary',
        PLAYER_360.ANALYTIC.RETENTION PRIMARY KEY (USER_ID)
            COMMENT = 'Player retention metrics and churn status',
        PLAYER_360.ANALYTIC.USER_RANKINGS PRIMARY KEY (USER_ID)
            COMMENT = 'Player ranking tiers based on total points',
        PLAYER_360.ANALYTIC.DAILY_ACTIVE_USERS PRIMARY KEY (ACTIVE_DATE)
            COMMENT = 'Daily count of unique active players'
    )
    RELATIONSHIPS (
        SESSIONS_TO_USERS AS SESSIONS(USER_ID) REFERENCES USERS(USER_ID),
        PURCHASES_TO_USERS AS PURCHASES(USER_ID) REFERENCES USERS(USER_ID),
        GAME_EVENTS_TO_USERS AS GAME_EVENTS(USER_ID) REFERENCES USERS(USER_ID),
        DEMOGRAPHICS_TO_USERS AS DEMOGRAPHICS(USER_ID) REFERENCES USERS(USER_ID),
        RETENTION_TO_USERS AS RETENTION(USER_ID) REFERENCES USERS(USER_ID),
        RANKINGS_TO_USERS AS USER_RANKINGS(USER_ID) REFERENCES USERS(USER_ID)
    )
    FACTS (
        SESSIONS.SESSION_DURATION AS SESSION_DURATION_MINUTES,
        PURCHASES.PURCHASE_AMOUNT AS PURCHASE_AMOUNT,
        PURCHASES.AD_ENGAGEMENT_TIME AS AD_ENGAGEMENT_TIME,
        GAME_EVENTS.KILLS AS KILLS,
        GAME_EVENTS.ASSISTS AS ASSISTS,
        GAME_EVENTS.HEADSHOTS AS HEADSHOTS,
        GAME_EVENTS.DAMAGE_DEALT AS DAMAGE_DEALT,
        GAME_EVENTS.DISTANCE_TRAVELED AS DISTANCE_TRAVELED,
        GAME_EVENTS.HEALS AS HEALS,
        GAME_EVENTS.BOOSTS AS BOOSTS,
        GAME_EVENTS.WEAPONS_ACQUIRED AS WEAPONS_ACQUIRED,
        USER_RANKINGS.TOTAL_POINTS AS TOTAL_POINTS,
        USER_RANKINGS.PERCENTILE AS PERCENTILE
    )
    DIMENSIONS (
        USERS.ALIAS AS ALIAS COMMENT = 'Player gamertag/alias',
        USERS.FIRST_NAME AS FIRST_NAME COMMENT = 'Player first name',
        USERS.LAST_NAME AS LAST_NAME COMMENT = 'Player last name',
        USERS.GENDER AS GENDER COMMENT = 'Player gender',
        USERS.LOCATION AS LOCATION COMMENT = 'Player country/region',
        USERS.ACCOUNT_CREATION AS ACCOUNT_CREATION COMMENT = 'Date the player created their account',
        SESSIONS.DEVICE_TYPE AS DEVICE_TYPE COMMENT = 'Device type used for the session',
        SESSIONS.LOG_IN AS LOG_IN COMMENT = 'Session login timestamp',
        PURCHASES.PURCHASE_TYPE AS PURCHASE_TYPE
            COMMENT = 'Type of purchase: weapon mod, in-game currency, skins, boosters, or none'
            SAMPLE_VALUES ('weapon mod', 'in-game currency', 'skins', 'boosters', 'none') IS_ENUM,
        PURCHASES.AD_TYPE AS AD_TYPE COMMENT = 'Type of advertisement shown',
        PURCHASES.AD_CONVERSION AS AD_CONVERSION COMMENT = 'Whether the ad resulted in a purchase',
        PURCHASES.TIMESTAMP_OF_PURCHASE AS TIMESTAMP_OF_PURCHASE COMMENT = 'When the purchase was made',
        DEMOGRAPHICS.PLAYER_TYPE AS PLAYER_TYPE
            COMMENT = 'Player behavioral segment (casual, hardcore, etc.)' IS_ENUM,
        DEMOGRAPHICS.AGE AS AGE COMMENT = 'Player age in years',
        DEMOGRAPHICS.IS_SPENDER AS IS_SPENDER COMMENT = 'Whether the player has made any purchase',
        DEMOGRAPHICS.HAS_SUPPORT_TICKET AS HAS_SUPPORT_TICKET COMMENT = 'Whether the player has filed a support ticket',
        RETENTION.FIRST_LOGIN_DATE AS FIRST_LOGIN_DATE COMMENT = 'Date of first login',
        RETENTION.LAST_LOGIN_DATE AS LAST_LOGIN_DATE COMMENT = 'Date of most recent login',
        RETENTION.TOTAL_LOGINS AS TOTAL_LOGINS COMMENT = 'Total number of logins',
        RETENTION.DAY1_RETAINED AS LOGGED_IN_AFTER_1_DAY COMMENT = 'Whether player returned within 1 day of first login',
        RETENTION.DAY7_RETAINED AS LOGGED_IN_AFTER_7_DAYS COMMENT = 'Whether player returned within 7 days of first login',
        RETENTION.DAY30_RETAINED AS LOGGED_IN_AFTER_30_DAYS COMMENT = 'Whether player returned within 30 days of first login',
        RETENTION.CHURNED AS CHURNED COMMENT = 'Whether the player has churned (1=churned, 0=active)',
        RETENTION.DAYS_SINCE_LAST_LOGIN AS DAYS_SINCE_LAST_LOGIN COMMENT = 'Days since last login',
        USER_RANKINGS.RANK_NAME AS RANK_NAME
            COMMENT = 'Player rank tier (Bronze, Silver, Gold, Diamond, etc.)' IS_ENUM,
        DAILY_ACTIVE_USERS.ACTIVE_DATE AS ACTIVE_DATE COMMENT = 'Calendar date for DAU metric',
        DAILY_ACTIVE_USERS.DAU_COUNT AS ACTIVE_USER_COUNT COMMENT = 'Number of unique players who logged in on this date'
    )
    METRICS (
        USERS.TOTAL_PLAYERS AS COUNT(USER_ID) COMMENT = 'Total number of registered players',
        SESSIONS.TOTAL_SESSIONS AS COUNT(SESSION_ID) COMMENT = 'Total number of sessions',
        SESSIONS.AVG_SESSION_DURATION AS AVG(sessions.session_duration) COMMENT = 'Average session duration in minutes',
        PURCHASES.TOTAL_REVENUE AS SUM(purchases.purchase_amount) COMMENT = 'Total revenue from purchases in USD',
        PURCHASES.AVG_PURCHASE_AMOUNT AS AVG(purchases.purchase_amount) COMMENT = 'Average purchase amount in USD',
        PURCHASES.TOTAL_PURCHASES AS COUNT(PURCHASE_ID) COMMENT = 'Total number of purchases',
        PURCHASES.AD_CONVERSION_RATE AS AVG(CASE WHEN AD_CONVERSION THEN 1.0 ELSE 0.0 END) COMMENT = 'Ad conversion rate (0 to 1)',
        GAME_EVENTS.TOTAL_MATCHES AS COUNT(MATCH_ID) COMMENT = 'Total number of matches played',
        GAME_EVENTS.AVG_KILLS AS AVG(game_events.kills) COMMENT = 'Average kills per match',
        GAME_EVENTS.AVG_DAMAGE AS AVG(game_events.damage_dealt) COMMENT = 'Average damage dealt per match',
        GAME_EVENTS.TOTAL_KILLS AS SUM(game_events.kills) COMMENT = 'Total kills across all matches',
        RETENTION.CHURN_COUNT AS SUM(CASE WHEN CHURNED = 1 THEN 1 ELSE 0 END) COMMENT = 'Number of churned players',
        RETENTION.DAY1_RETENTION_RATE AS AVG(CASE WHEN LOGGED_IN_AFTER_1_DAY THEN 1.0 ELSE 0.0 END) COMMENT = 'Day 1 retention rate (0 to 1)',
        RETENTION.DAY7_RETENTION_RATE AS AVG(CASE WHEN LOGGED_IN_AFTER_7_DAYS THEN 1.0 ELSE 0.0 END) COMMENT = 'Day 7 retention rate (0 to 1)'
    )
    COMMENT = 'Player 360 analytics for game analysts and product managers. Covers player profiles, sessions, purchases, game performance, retention, and rankings.';
