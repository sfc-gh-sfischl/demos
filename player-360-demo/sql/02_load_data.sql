-- =============================================================================
-- Player 360 Demo — Step 2: Load data (~22M sessions, ~5.6M purchases, ~22M events)
--
-- All data is generated deterministically via SQL GENERATOR + HASH.
-- WARNING: The large tables take ~5-10 min on an XS warehouse.
--          Use a MEDIUM or larger for faster loading.
--
-- Run AFTER 01_setup_and_tables.sql.  Safe to re-run (truncates first).
-- =============================================================================

USE WAREHOUSE COMPUTE_WH;   -- <-- change to your warehouse

-- ============================================================
-- RAW.USERS (6,000 players, IDs 1001-16000 with gaps)
-- ============================================================
USE SCHEMA PLAYER_360.RAW;
TRUNCATE TABLE USERS;

INSERT INTO USERS
WITH base AS (
    SELECT 1000 + ROW_NUMBER() OVER (ORDER BY SEQ4()) AS USER_ID
    FROM TABLE(GENERATOR(ROWCOUNT => 6000))
),
first_names_f AS (
    SELECT column1 AS IDX, column2 AS NAME FROM VALUES
    (0,'Regina'),(1,'Heather'),(2,'Kara'),(3,'Miranda'),(4,'Toni'),
    (5,'Sarah'),(6,'Emily'),(7,'Jessica'),(8,'Amanda'),(9,'Lisa'),
    (10,'Nicole'),(11,'Ashley'),(12,'Lauren'),(13,'Rachel'),(14,'Megan'),
    (15,'Hannah'),(16,'Olivia'),(17,'Sophia'),(18,'Isabella'),(19,'Emma')
),
first_names_m AS (
    SELECT column1 AS IDX, column2 AS NAME FROM VALUES
    (0,'James'),(1,'Robert'),(2,'Michael'),(3,'David'),(4,'Richard'),
    (5,'Joseph'),(6,'Thomas'),(7,'Charles'),(8,'Daniel'),(9,'Matthew'),
    (10,'Anthony'),(11,'Mark'),(12,'Steven'),(13,'Paul'),(14,'Andrew'),
    (15,'Joshua'),(16,'Kenneth'),(17,'Kevin'),(18,'Brian'),(19,'George')
),
last_names AS (
    SELECT column1 AS IDX, column2 AS NAME FROM VALUES
    (0,'Johnson'),(1,'Davis'),(2,'Jones'),(3,'Miller'),(4,'Rodriguez'),
    (5,'Smith'),(6,'Williams'),(7,'Brown'),(8,'Taylor'),(9,'Anderson'),
    (10,'Thomas'),(11,'Wilson'),(12,'Garcia'),(13,'Martinez'),(14,'Clark'),
    (15,'Lee'),(16,'Walker'),(17,'Hall'),(18,'Allen'),(19,'Young')
),
locations AS (
    SELECT column1 AS IDX, column2 AS LOC FROM VALUES
    (0,'USA'),(1,'Brazil'),(2,'Korea'),(3,'Australia'),(4,'UK'),
    (5,'Germany'),(6,'Canada'),(7,'France'),(8,'Mexico'),(9,'Poland'),(10,'China')
),
email_domains AS (
    SELECT column1 AS IDX, column2 AS DOM FROM VALUES
    (0,'gmail.com'),(1,'yahoo.com'),(2,'aol.com'),(3,'outlook.com'),(4,'hotmail.com')
),
photos AS (
    SELECT column1 AS IDX, column2 AS URL FROM VALUES
    (0,'https://github.com/sfc-gh-jholt/jgh-images/blob/main/female1.jpeg?raw=true'),
    (1,'https://github.com/sfc-gh-jholt/jgh-images/blob/main/female2.jpeg?raw=true'),
    (2,'https://github.com/sfc-gh-jholt/jgh-images/blob/main/female3.jpeg?raw=true'),
    (3,'https://github.com/sfc-gh-jholt/jgh-images/blob/main/female4.jpeg?raw=true'),
    (4,'https://github.com/sfc-gh-jholt/jgh-images/blob/main/female5.jpeg?raw=true'),
    (5,'https://github.com/sfc-gh-jholt/jgh-images/blob/main/male1.jpeg?raw=true'),
    (6,'https://github.com/sfc-gh-jholt/jgh-images/blob/main/male2.jpeg?raw=true'),
    (7,'https://github.com/sfc-gh-jholt/jgh-images/blob/main/male3.jpeg?raw=true'),
    (8,'https://github.com/sfc-gh-jholt/jgh-images/blob/main/male4.jpeg?raw=true'),
    (9,'https://github.com/sfc-gh-jholt/jgh-images/blob/main/male5.jpeg?raw=true')
),
adjectives AS (
    SELECT column1 AS IDX, column2 AS WORD FROM VALUES
    (0,'black'),(1,'friend'),(2,'writer'),(3,'science'),(4,'discuss'),
    (5,'fast'),(6,'storm'),(7,'night'),(8,'blue'),(9,'shadow'),
    (10,'dark'),(11,'wild'),(12,'cool'),(13,'bright'),(14,'quick')
),
nouns AS (
    SELECT column1 AS IDX, column2 AS WORD FROM VALUES
    (0,'win'),(1,'threat'),(2,'star'),(3,'room'),(4,'show'),
    (5,'fox'),(6,'rider'),(7,'hawk'),(8,'wolf'),(9,'bear'),
    (10,'blade'),(11,'fire'),(12,'storm'),(13,'moon'),(14,'sky')
)
SELECT
    b.USER_ID,
    adj.WORD || noun.WORD || (ABS(HASH(b.USER_ID, 'alias')) % 100)::VARCHAR AS ALIAS,
    CASE WHEN ABS(HASH(b.USER_ID, 'gender')) % 2 = 0
         THEN fnf.NAME ELSE fnm.NAME END AS FIRST_NAME,
    ln.NAME AS LAST_NAME,
    CASE WHEN ABS(HASH(b.USER_ID, 'gender')) % 2 = 0 THEN 'Female' ELSE 'Male' END AS GENDER,
    LOWER(
        CASE WHEN ABS(HASH(b.USER_ID, 'gender')) % 2 = 0 THEN fnf.NAME ELSE fnm.NAME END
        || '.' || ln.NAME || '@' || ed.DOM
    ) AS EMAIL,
    loc.LOC AS LOCATION,
    DATEADD('day', -(ABS(HASH(b.USER_ID, 'acct_days')) % 2500), '2026-07-14'::DATE) AS ACCOUNT_CREATION,
    (ABS(HASH(b.USER_ID, 'consent')) % 100 > 5) AS CONSENT,
    CASE WHEN ABS(HASH(b.USER_ID, 'gender')) % 2 = 0
         THEN ph_f.URL ELSE ph_m.URL END AS PHOTO_URL,
    DATEADD('day', -(ABS(HASH(b.USER_ID, 'bday')) % 18250 + 6570), '2026-07-14'::DATE) AS BIRTHDATE
FROM base b
JOIN first_names_f fnf ON fnf.IDX = ABS(HASH(b.USER_ID, 'fname')) % 20
JOIN first_names_m fnm ON fnm.IDX = ABS(HASH(b.USER_ID, 'fname')) % 20
JOIN last_names ln ON ln.IDX = ABS(HASH(b.USER_ID, 'lname')) % 20
JOIN locations loc ON loc.IDX = ABS(HASH(b.USER_ID, 'loc')) % 11
JOIN email_domains ed ON ed.IDX = ABS(HASH(b.USER_ID, 'email')) % 5
JOIN photos ph_f ON ph_f.IDX = ABS(HASH(b.USER_ID, 'photo')) % 5
JOIN photos ph_m ON ph_m.IDX = 5 + ABS(HASH(b.USER_ID, 'photo')) % 5
JOIN adjectives adj ON adj.IDX = ABS(HASH(b.USER_ID, 'adj')) % 15
JOIN nouns noun ON noun.IDX = ABS(HASH(b.USER_ID, 'noun')) % 15;

-- ============================================================
-- RAW.SESSIONS (~22.8M rows = 6,000 users x ~3,800 sessions each)
-- ~3,600 days from 2016-08-20 to 2026-07-14
-- ============================================================
TRUNCATE TABLE SESSIONS;

INSERT INTO SESSIONS
WITH users AS (
    SELECT USER_ID FROM PLAYER_360.RAW.USERS
),
seq AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS N
    FROM TABLE(GENERATOR(ROWCOUNT => 3900))
),
devices AS (
    SELECT column1 AS IDX, column2 AS DEV FROM VALUES
    (0,'ios'),(1,'android'),(2,'ps4'),(3,'ps5'),(4,'xbox'),(5,'switch')
)
SELECT
    u.USER_ID,
    800000000000 + (u.USER_ID * 100000 + s.N) AS SESSION_ID,
    DATEADD('second',
        ABS(HASH(u.USER_ID, s.N, 'time')) % 86400,
        DATEADD('day',
            ABS(HASH(u.USER_ID, s.N, 'day')) % 3616,
            '2016-08-20'::DATE
        )
    )::TIMESTAMP_NTZ AS LOG_IN,
    DATEADD('minute',
        (ABS(HASH(u.USER_ID, s.N, 'dur')) % 50 + 1),
        DATEADD('second',
            ABS(HASH(u.USER_ID, s.N, 'time')) % 86400,
            DATEADD('day',
                ABS(HASH(u.USER_ID, s.N, 'day')) % 3616,
                '2016-08-20'::DATE
            )
        )
    )::TIMESTAMP_NTZ AS LOG_OUT,
    (ABS(HASH(u.USER_ID, s.N, 'dur')) % 50 + 1)::NUMBER(3,1) AS SESSION_DURATION_MINUTES,
    d.DEV AS DEVICE_TYPE
FROM users u
CROSS JOIN seq s
JOIN devices d ON d.IDX = ABS(HASH(u.USER_ID, 'device')) % 6
WHERE s.N <= (3500 + ABS(HASH(u.USER_ID, 'sess_count')) % 700);

-- ============================================================
-- RAW.PURCHASES (~5.6M rows = 6,000 users x ~950 each)
-- ============================================================
TRUNCATE TABLE PURCHASES;

INSERT INTO PURCHASES
WITH users AS (
    SELECT USER_ID FROM PLAYER_360.RAW.USERS
),
seq AS (
    SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS N
    FROM TABLE(GENERATOR(ROWCOUNT => 1100))
),
ad_types AS (
    SELECT column1 AS IDX, column2 AS ATYPE FROM VALUES
    (0,'banner_ad'),(1,'email'),(2,'facebook'),(3,'instagram'),(4,'tik_tok')
),
purchase_types AS (
    SELECT column1 AS IDX, column2 AS PTYPE FROM VALUES
    (0,'none'),(1,'none'),(2,'none'),(3,'skins'),(4,'in-game currency'),
    (5,'weapon mod'),(6,'boosters'),(7,'none'),(8,'none'),(9,'none')
)
SELECT
    u.USER_ID,
    4000000000 + (u.USER_ID * 1000 + s.N) AS PURCHASE_ID,
    CASE WHEN pt.PTYPE = 'none' THEN 0.00
         ELSE ROUND(ABS(HASH(u.USER_ID, s.N, 'amt')) % 1500 / 100.0 + 0.99, 2)
    END::NUMBER(4,2) AS PURCHASE_AMOUNT,
    pt.PTYPE AS PURCHASE_TYPE,
    DATEADD('second',
        ABS(HASH(u.USER_ID, s.N, 'ptime')) % 86400,
        DATEADD('day',
            ABS(HASH(u.USER_ID, s.N, 'pday')) % 730,
            '2024-07-14'::DATE
        )
    )::TIMESTAMP_NTZ AS TIMESTAMP_OF_PURCHASE,
    600000000 + (u.USER_ID * 1000 + s.N) AS AD_INTERACTION_ID,
    at.ATYPE AS AD_TYPE,
    (ABS(HASH(u.USER_ID, s.N, 'engage')) % 28 + 1)::NUMBER(2,0) AS AD_ENGAGEMENT_TIME,
    (pt.PTYPE != 'none') AS AD_CONVERSION
FROM users u
CROSS JOIN seq s
JOIN ad_types at ON at.IDX = ABS(HASH(u.USER_ID, s.N, 'ad')) % 5
JOIN purchase_types pt ON pt.IDX = ABS(HASH(u.USER_ID, s.N, 'ptype')) % 10
WHERE s.N <= (800 + ABS(HASH(u.USER_ID, 'purch_count')) % 400);

-- ============================================================
-- RAW.GAME_EVENTS (~22.8M rows, 1 event per session)
-- ============================================================
TRUNCATE TABLE GAME_EVENTS;

INSERT INTO GAME_EVENTS
SELECT
    (ABS(HASH(SESSION_ID, 'assists')) % 15)::NUMBER(2,0) AS ASSISTS,
    (ABS(HASH(SESSION_ID, 'boosts')) % 20)::NUMBER(2,0) AS BOOSTS,
    ROUND(ABS(HASH(SESSION_ID, 'damage')) % 40000 / 100.0, 2)::NUMBER(6,2) AS DAMAGE_DEALT,
    ROUND(ABS(HASH(SESSION_ID, 'dist')) % 10000 / 100.0, 2)::NUMBER(5,2) AS DISTANCE_TRAVELED,
    SUBSTR(MD5(SESSION_ID::VARCHAR || 'grp'), 1, 12) AS GROUP_ID,
    (ABS(HASH(SESSION_ID, 'headshots')) % 12)::NUMBER(2,0) AS HEADSHOTS,
    (ABS(HASH(SESSION_ID, 'heals')) % 10)::NUMBER(2,0) AS HEALS,
    (ABS(HASH(SESSION_ID, 'kills')) % 12)::NUMBER(2,0) AS KILLS,
    SUBSTR(MD5(SESSION_ID::VARCHAR || 'match'), 1, 12) AS MATCH_ID,
    SESSION_ID::VARCHAR AS SESSION_ID,
    USER_ID,
    (ABS(HASH(SESSION_ID, 'weapons')) % 6)::NUMBER(1,0) AS WEAPONS_ACQUIRED
FROM PLAYER_360.RAW.SESSIONS;

-- ============================================================
-- RAW.ACHIEVEMENTS (1 row per user, random booleans)
-- ============================================================
TRUNCATE TABLE ACHIEVEMENTS;

INSERT INTO ACHIEVEMENTS
SELECT
    USER_ID,
    (ABS(HASH(USER_ID, 'vr')) % 100 < 35) AS VICTORY_ROYALE,
    (ABS(HASH(USER_ID, 'em')) % 100 < 50) AS ELIMINATION_MILESTONES,
    (ABS(HASH(USER_ID, 'sa')) % 100 < 60) AS SURVIVAL_ACHIEVEMENTS,
    (ABS(HASH(USER_ID, 'br')) % 100 < 45) AS BUILDING_RESOURCES,
    (ABS(HASH(USER_ID, 'et')) % 100 < 55) AS EXPLORATION_TRAVEL,
    (ABS(HASH(USER_ID, 'wu')) % 100 < 65) AS WEAPON_USAGE,
    (ABS(HASH(USER_ID, 'at')) % 100 < 40) AS ASSIST_TEAMMATES,
    (ABS(HASH(USER_ID, 'ec')) % 100 < 30) AS EVENT_CHALLENGES,
    (ABS(HASH(USER_ID, 'cm')) % 100 < 25) AS CREATIVE_MODE,
    (ABS(HASH(USER_ID, 'so')) % 100 < 20) AS SOCIAL_ACHIEVEMENTS
FROM PLAYER_360.RAW.USERS;

-- ============================================================
-- RAW.SUPPORT_TICKETS (~676 tickets for ~11% of users)
-- ============================================================
TRUNCATE TABLE SUPPORT_TICKETS;

INSERT INTO SUPPORT_TICKETS
WITH ticket_users AS (
    SELECT USER_ID, ROW_NUMBER() OVER (ORDER BY USER_ID) AS RN
    FROM PLAYER_360.RAW.USERS
    WHERE ABS(HASH(USER_ID, 'ticket')) % 100 < 11
),
categories AS (
    SELECT column1 AS IDX, column2 AS CAT FROM VALUES
    (0,'Account Management'),(1,'Technical Support'),(2,'Payments and Billing')
),
templates AS (
    SELECT column1 AS IDX, column2 AS TMPL FROM VALUES
    (0, 'Subject: Account Management Issue with GAME101  Dear COMPANY101 Support Team, I have encountered an issue related to account management. I am unable to log in to my account despite multiple attempts.'),
    (1, 'Subject: Technical Support Request for GAME101  Dear COMPANY101 Support Team, I have encountered a technical issue. The game crashes after the splash screen without any error message.'),
    (2, 'Subject: Payments and Billing Issue for GAME101  Dear COMPANY101 Support Team, I was charged twice for the same purchase on my credit card. Please look into this matter.')
)
SELECT
    59999 + tu.RN AS CASE_ID,
    tu.USER_ID,
    c.CAT AS CATEGORY,
    t.TMPL AS CASE_DESCRIPTION,
    ROUND((ABS(HASH(tu.USER_ID, 'sentiment')) % 1000 - 200) / 1000.0, 9)::NUMBER(10,9) AS SENTIMENT_ANALYSIS,
    DATEADD('second',
        ABS(HASH(tu.USER_ID, 'ttime')) % 86400,
        DATEADD('day', ABS(HASH(tu.USER_ID, 'tday')) % 2000, '2019-01-01'::DATE)
    )::TIMESTAMP_NTZ AS DATE_CREATED
FROM ticket_users tu
JOIN categories c ON c.IDX = ABS(HASH(tu.USER_ID, 'cat')) % 3
JOIN templates t ON t.IDX = ABS(HASH(tu.USER_ID, 'cat')) % 3;

-- ============================================================
-- ANALYTIC.DAILY_ACTIVE_USERS (from SESSIONS)
-- ============================================================
USE SCHEMA PLAYER_360.ANALYTIC;
TRUNCATE TABLE DAILY_ACTIVE_USERS;

INSERT INTO DAILY_ACTIVE_USERS
SELECT DATE(LOG_IN) AS ACTIVE_DATE, COUNT(DISTINCT USER_ID) AS ACTIVE_USER_COUNT
FROM PLAYER_360.RAW.SESSIONS
GROUP BY DATE(LOG_IN)
ORDER BY ACTIVE_DATE;

-- ============================================================
-- ANALYTIC.MONTHLY_ACTIVE_USERS (from SESSIONS)
-- ============================================================
TRUNCATE TABLE MONTHLY_ACTIVE_USERS;

INSERT INTO MONTHLY_ACTIVE_USERS
SELECT DATE_TRUNC('month', LOG_IN)::DATE AS ACTIVE_MONTH, COUNT(DISTINCT USER_ID) AS ACTIVE_USER_COUNT
FROM PLAYER_360.RAW.SESSIONS
GROUP BY DATE_TRUNC('month', LOG_IN)
ORDER BY ACTIVE_MONTH;

-- ============================================================
-- ANALYTIC.POINTS_MAPPING_TABLE (8 rows)
-- ============================================================
TRUNCATE TABLE POINTS_MAPPING_TABLE;

INSERT INTO POINTS_MAPPING_TABLE VALUES
('Assists', 0.2),
('Boosts', 0.1),
('Damage Dealt', 0.1),
('Distance Traveled', 0.2),
('Head Shots', 0.3),
('Heals', 0.2),
('Kills', 1.0),
('Weapons Acquired', 0.1);

-- ============================================================
-- ANALYTIC.RANKING_MAPPING_TABLE (8 rows)
-- ============================================================
TRUNCATE TABLE RANKING_MAPPING_TABLE;

INSERT INTO RANKING_MAPPING_TABLE VALUES
('Bronze', 0, 25944.68425),
('Silver', 25944.68425, 53514.402),
('Gold', 53514.402, 95115.43875),
('Platinum', 95115.43875, 149274.7655),
('Diamond', 149274.7655, 204122.327625),
('Elite', 204122.327625, 257617.645),
('Champion', 257617.645, 309498.88175),
('Unreal', 309498.88175, 999999999);

-- ============================================================
-- Verify row counts
-- ============================================================
SELECT 'USERS' AS TBL, COUNT(*) AS ROWS FROM PLAYER_360.RAW.USERS
UNION ALL SELECT 'SESSIONS', COUNT(*) FROM PLAYER_360.RAW.SESSIONS
UNION ALL SELECT 'PURCHASES', COUNT(*) FROM PLAYER_360.RAW.PURCHASES
UNION ALL SELECT 'GAME_EVENTS', COUNT(*) FROM PLAYER_360.RAW.GAME_EVENTS
UNION ALL SELECT 'ACHIEVEMENTS', COUNT(*) FROM PLAYER_360.RAW.ACHIEVEMENTS
UNION ALL SELECT 'SUPPORT_TICKETS', COUNT(*) FROM PLAYER_360.RAW.SUPPORT_TICKETS
UNION ALL SELECT 'DAILY_ACTIVE_USERS', COUNT(*) FROM PLAYER_360.ANALYTIC.DAILY_ACTIVE_USERS
UNION ALL SELECT 'MONTHLY_ACTIVE_USERS', COUNT(*) FROM PLAYER_360.ANALYTIC.MONTHLY_ACTIVE_USERS
ORDER BY TBL;
