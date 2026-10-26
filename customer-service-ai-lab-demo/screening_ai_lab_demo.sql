/* =====================================================================
   BACKGROUND SCREENING - AI LAB DEMO (all data is synthetic)

   Supports the ~30 min demo flow:
     1. Sandbox      -> governed lab DB + zero-copy clone for the lab team
     2. Insights     -> AI_REDACT / AI_CLASSIFY / AI_SENTIMENT / AI_COMPLETE / AI_AGG
     3. Agent        -> Cortex Search + Semantic View + Cortex Agent (CoWork)
                        + masking policy on candidate PII (re-ask as SUPPORT_AGENT)
     4. Real-time    -> discussion only (nothing built)

   Sections:
     0. Setup              5. Cortex Search
     1. RAW tables         6. Semantic view
     2. Synthetic data     7. Governance (roles + masking)
     3. Status updates     8. Cortex Agent
     4. AI enrichment      9. Sandbox clone + demo queries

   Run top to bottom as ACCOUNTADMIN (or a role that can create DBs,
   roles, policies and Cortex objects). Re-runnable.
   Cortex AI cost: section 4 makes ~5 LLM calls per transcript
   (1,500 transcripts by default). Lower N_TRANSCRIPTS to reduce cost.
   ===================================================================== */

-- =====================================================================
-- 0. SETUP
-- =====================================================================
USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS SCREENING_DEMO_WH
  WAREHOUSE_SIZE = SMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
USE WAREHOUSE SCREENING_DEMO_WH;

CREATE OR REPLACE DATABASE SCREENING_AI_LAB COMMENT = 'Sentinel Screening AI Lab demo (synthetic data)';
CREATE SCHEMA SCREENING_AI_LAB.RAW      COMMENT = 'Landed source data (Salesforce, Amazon Connect, app DB)';
CREATE SCHEMA SCREENING_AI_LAB.ENRICHED COMMENT = 'AI-enriched data';
CREATE SCHEMA SCREENING_AI_LAB.AI       COMMENT = 'Search services, semantic views, agents';
CREATE SCHEMA SCREENING_AI_LAB.GOV      COMMENT = 'Governance policies';
USE SCHEMA SCREENING_AI_LAB.RAW;

-- Transcript count: change ROWCOUNT => 1500 in section 2 to resize

-- =====================================================================
-- 1. RAW TABLES
-- =====================================================================
CREATE OR REPLACE TABLE CLIENTS (
  CLIENT_ID     INT    COMMENT 'Employer client id',
  CLIENT_NAME   STRING COMMENT 'Employer client that ordered the screening',
  INDUSTRY      STRING COMMENT 'Client industry',
  ACCOUNT_TIER  STRING COMMENT 'Strategic, Enterprise, Mid-Market'
) COMMENT = 'Employer clients that order background screenings';

CREATE OR REPLACE TABLE CANDIDATES (
  CANDIDATE_ID  INT    COMMENT 'Candidate id',
  FIRST_NAME    STRING COMMENT 'Candidate first name',
  LAST_NAME     STRING COMMENT 'Candidate last name',
  FULL_NAME     STRING COMMENT 'Candidate full name',
  EMAIL         STRING COMMENT 'Candidate email (PII)',
  PHONE         STRING COMMENT 'Candidate phone (PII)',
  SSN           STRING COMMENT 'Candidate SSN (PII, fake)',
  DOB           DATE   COMMENT 'Candidate date of birth (PII)',
  STATE         STRING COMMENT 'Candidate state of residence'
) COMMENT = 'Candidates being screened. Contains PII (masked for support roles)';

CREATE OR REPLACE TABLE ORDERS (
  ORDER_ID         INT    COMMENT 'Background screening order id (e.g. 4471823)',
  CANDIDATE_ID     INT    COMMENT 'FK to CANDIDATES',
  CLIENT_ID        INT    COMMENT 'FK to CLIENTS',
  PACKAGE          STRING COMMENT 'Screening package ordered',
  ORDER_DATE       DATE   COMMENT 'Date order was placed',
  CURRENT_STATUS   STRING COMMENT 'Current overall order status',
  CURRENT_COMPONENT STRING COMMENT 'Component currently pending (County Criminal Search, Education Verification, ...)',
  STATUS_SINCE     DATE   COMMENT 'Date the order entered its current status',
  DAYS_IN_STATUS   INT    COMMENT 'Days in current status',
  ETA_DATE         DATE   COMMENT 'Estimated completion date',
  COMPLETED_DATE   DATE   COMMENT 'Completion date (NULL if not complete)'
) COMMENT = 'Background screening orders (application data replicated from SQL Server)';

CREATE OR REPLACE TABLE ORDER_STATUS_HISTORY (
  ORDER_ID     INT       COMMENT 'FK to ORDERS',
  STATUS       STRING    COMMENT 'Status value',
  COMPONENT    STRING    COMMENT 'Component the status relates to',
  CHANGED_AT   TIMESTAMP_NTZ COMMENT 'When the status changed'
) COMMENT = 'Order status change history';

CREATE OR REPLACE TABLE OPS_NOTES (
  NOTE_ID      INT       COMMENT 'Note id',
  ORDER_ID     INT       COMMENT 'FK to ORDERS',
  AUTHOR       STRING    COMMENT 'Operations analyst who wrote the note',
  CREATED_AT   TIMESTAMP_NTZ COMMENT 'Note timestamp',
  NOTE_TEXT    STRING    COMMENT 'Free-text fulfillment note'
) COMMENT = 'Free-text notes captured by fulfillment operations';

CREATE OR REPLACE TABLE CALL_TRANSCRIPTS (
  CONTACT_ID     STRING    COMMENT 'Amazon Connect / Salesforce contact id',
  ORDER_ID       INT       COMMENT 'Related order (as captured by IVR / agent)',
  CANDIDATE_ID   INT       COMMENT 'Caller candidate id',
  CHANNEL        STRING    COMMENT 'VOICE or CHAT',
  SOURCE_SYSTEM  STRING    COMMENT 'AMAZON_CONNECT or SALESFORCE',
  AGENT_NAME     STRING    COMMENT 'Customer service agent name',
  STARTED_AT     TIMESTAMP_NTZ COMMENT 'Contact start time',
  DURATION_SEC   INT       COMMENT 'Contact duration seconds',
  TRANSCRIPT     STRING    COMMENT 'Raw transcript (contains PII)'
) COMMENT = 'Raw call and chat transcripts from Amazon Connect and Salesforce';

CREATE OR REPLACE TABLE SFDC_CASES (
  CASE_ID      STRING COMMENT 'Salesforce case number',
  CONTACT_ID   STRING COMMENT 'Related contact',
  ORDER_ID     INT    COMMENT 'Related order',
  SUBJECT      STRING COMMENT 'Case subject',
  STATUS       STRING COMMENT 'Open, Escalated, Closed',
  PRIORITY     STRING COMMENT 'Low, Medium, High',
  CREATED_AT   TIMESTAMP_NTZ COMMENT 'Case created'
) COMMENT = 'Salesforce Service Cloud cases created from contacts';

-- =====================================================================
-- 2. SYNTHETIC DATA
-- =====================================================================
INSERT INTO CLIENTS VALUES
 (1,'Acme Logistics','Transportation','Strategic'),
 (2,'Northwind Health','Healthcare','Strategic'),
 (3,'Contoso Retail','Retail','Enterprise'),
 (4,'Fabrikam Staffing','Staffing','Enterprise'),
 (5,'Blue Harbor Bank','Financial Services','Enterprise'),
 (6,'Summit Rideshare','Gig Economy','Strategic'),
 (7,'Evergreen Senior Living','Healthcare','Mid-Market'),
 (8,'Ironclad Security','Security Services','Mid-Market'),
 (9,'Brightpath Schools','Education','Mid-Market'),
 (10,'Redwood Manufacturing','Manufacturing','Enterprise');

-- 20,000 candidates (candidate 1 = Maria Lopez for the demo prompt)
INSERT INTO CANDIDATES
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS id FROM TABLE(GENERATOR(ROWCOUNT => 20000))),
n AS (
  SELECT id,
    IFF(id = 1, 'Maria',
      ARRAY_CONSTRUCT('James','Maria','Robert','Linda','Michael','Patricia','David','Jennifer','Carlos','Aisha',
                      'Kevin','Sofia','Daniel','Emily','Marcus','Grace','Luis','Hannah','Tyrone','Mei')[MOD(ABS(HASH(id,'fn')),20)]::STRING) AS fn,
    IFF(id = 1, 'Lopez',
      ARRAY_CONSTRUCT('Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis','Rodriguez','Martinez',
                      'Hernandez','Lopez','Wilson','Anderson','Thomas','Taylor','Moore','Jackson','Nguyen','Patel')[MOD(ABS(HASH(id,'ln')),20)]::STRING) AS ln
  FROM g
)
SELECT id, fn, ln, fn || ' ' || ln,
  LOWER(fn || '.' || ln || id) || '@examplemail.com',
  '(' || (200 + MOD(ABS(HASH(id,'a')),799)) || ') 555-' || LPAD(MOD(ABS(HASH(id,'p')),10000)::STRING,4,'0'),
  LPAD((100 + MOD(ABS(HASH(id,'s1')),799))::STRING,3,'0') || '-' ||
    LPAD((10 + MOD(ABS(HASH(id,'s2')),89))::STRING,2,'0') || '-' ||
    LPAD(MOD(ABS(HASH(id,'s3')),10000)::STRING,4,'0'),
  DATEADD(day, -(7300 + MOD(ABS(HASH(id,'dob')),14600)), CURRENT_DATE()),
  ARRAY_CONSTRUCT('FL','CA','TX','NY','GA','IL','OH','NC','AZ','WA')[MOD(ABS(HASH(id,'st')),10)]::STRING
FROM n;

-- 50,000 orders. Order 4471823 is Maria Lopez's (demo prompt).
INSERT INTO ORDERS
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS i FROM TABLE(GENERATOR(ROWCOUNT => 50000))),
o AS (
  SELECT
    4421823 + i                                          AS order_id,
    IFF(4421823 + i = 4471823, 1, 1 + MOD(ABS(HASH(i,'c')), 20000)) AS candidate_id,
    1 + MOD(ABS(HASH(i,'cl')), 10)                       AS client_id,
    DATEADD(day, -MOD(ABS(HASH(i,'od')), 90), CURRENT_DATE()) AS order_date,
    MOD(ABS(HASH(i,'stat')), 100)                        AS r
  FROM g
)
SELECT order_id, candidate_id, client_id,
  ARRAY_CONSTRUCT('Standard Employment','Healthcare Professional','Driver (MVR + Drug)','Financial Services',
                  'Gig Worker Express')[MOD(ABS(HASH(order_id,'pk')),5)]::STRING,
  order_date,
  CASE WHEN order_id = 4471823 THEN 'In Progress'
       WHEN DATEDIFF(day, order_date, CURRENT_DATE()) > 21 OR r < 55 THEN 'Complete'
       WHEN r < 85 THEN 'In Progress'
       WHEN r < 93 THEN 'Awaiting Candidate'
       ELSE 'On Hold' END,
  NULL, NULL, NULL, NULL, NULL
FROM o;

UPDATE ORDERS SET
  CURRENT_COMPONENT = CASE
    WHEN ORDER_ID = 4471823 THEN 'County Criminal Search'
    WHEN CURRENT_STATUS = 'Complete' THEN NULL
    WHEN CURRENT_STATUS = 'Awaiting Candidate' THEN
      ARRAY_CONSTRUCT('Consent Form','Identity Documents','Drug Test Scheduling')[MOD(ABS(HASH(ORDER_ID,'aw')),3)]::STRING
    ELSE ARRAY_CONSTRUCT('County Criminal Search','County Criminal Search','Education Verification',
                         'Employment Verification','Motor Vehicle Record','Drug Screen','Federal Criminal Search',
                         'Professional License Verification')[MOD(ABS(HASH(ORDER_ID,'cmp')),8)]::STRING END;

UPDATE ORDERS SET
  STATUS_SINCE   = IFF(ORDER_ID = 4471823, DATEADD(day,-8,CURRENT_DATE()),
                       LEAST(CURRENT_DATE(), DATEADD(day, MOD(ABS(HASH(ORDER_ID,'ss')), GREATEST(1, DATEDIFF(day,ORDER_DATE,CURRENT_DATE())+1)), ORDER_DATE))),
  COMPLETED_DATE = IFF(CURRENT_STATUS = 'Complete',
                       LEAST(CURRENT_DATE(), DATEADD(day, 2 + MOD(ABS(HASH(ORDER_ID,'cd')), 10), ORDER_DATE)), NULL);
UPDATE ORDERS SET STATUS_SINCE = COMPLETED_DATE WHERE CURRENT_STATUS = 'Complete';
UPDATE ORDERS SET
  DAYS_IN_STATUS = DATEDIFF(day, STATUS_SINCE, CURRENT_DATE()),
  ETA_DATE = IFF(CURRENT_STATUS = 'Complete', NULL,
                 DATEADD(day, 1 + MOD(ABS(HASH(ORDER_ID,'eta')), 7), CURRENT_DATE()));

-- Status history: Ordered -> In Progress (component) -> current
INSERT INTO ORDER_STATUS_HISTORY
SELECT ORDER_ID, 'Ordered', NULL, ORDER_DATE::TIMESTAMP_NTZ + INTERVAL '9 hour' FROM ORDERS
UNION ALL
SELECT ORDER_ID, 'In Progress', 'SSN Trace', ORDER_DATE::TIMESTAMP_NTZ + INTERVAL '1 day' FROM ORDERS
UNION ALL
SELECT ORDER_ID, CURRENT_STATUS, CURRENT_COMPONENT, STATUS_SINCE::TIMESTAMP_NTZ + INTERVAL '14 hour'
FROM ORDERS WHERE STATUS_SINCE > ORDER_DATE;

-- Ops notes for every non-complete order + a sample of complete ones
INSERT INTO OPS_NOTES
SELECT
  ROW_NUMBER() OVER (ORDER BY ORDER_ID, k),
  ORDER_ID,
  ARRAY_CONSTRUCT('J. Rivera','T. Okafor','S. Patel','M. Chen','A. Brooks','D. Kim')[MOD(ABS(HASH(ORDER_ID,k,'au')),6)]::STRING,
  DATEADD(hour, k * 20 + MOD(ABS(HASH(ORDER_ID,k)),10), STATUS_SINCE::TIMESTAMP_NTZ),
  CASE
    WHEN ORDER_ID = 4471823 AND k = 1 THEN
      'County criminal search submitted to Miami-Dade County court runner. Court is reporting a 7-10 business day backlog due to a records system migration. Expected return by end of next week.'
    WHEN ORDER_ID = 4471823 AND k = 2 THEN
      'Candidate called asking for status. Explained county court delay. Promised a callback once the court returns results. Escalated to county team lead for follow-up.'
    WHEN CURRENT_COMPONENT = 'County Criminal Search' THEN
      ARRAY_CONSTRUCT(
        'Court runner dispatched to ' || ARRAY_CONSTRUCT('Cook','Harris','Maricopa','Los Angeles','Fulton','Wake')[MOD(ABS(HASH(ORDER_ID,'cty')),6)]::STRING || ' County. Clerk reports backlog; ETA 3-5 business days.',
        'Possible record match on common name. Requested additional identifiers (DOB, middle name) from court to confirm or rule out.',
        'County court closed for holiday. Search will resume next business day.',
        'Court requires in-person retrieval for records older than 7 years. Runner scheduled.')[MOD(ABS(HASH(ORDER_ID,k,'n')),4)]::STRING
    WHEN CURRENT_COMPONENT = 'Education Verification' THEN
      ARRAY_CONSTRUCT(
        'Registrar has not responded to verification request. Second request sent by email and fax.',
        'School requires signed release from candidate before releasing degree information. Release form sent to candidate.',
        'Institution uses National Student Clearinghouse but no record found under provided name. Asked candidate for maiden or prior name.',
        'International degree; forwarded to international verification partner. Typical turnaround 10-15 business days.')[MOD(ABS(HASH(ORDER_ID,k,'n')),4)]::STRING
    WHEN CURRENT_COMPONENT = 'Employment Verification' THEN
      ARRAY_CONSTRUCT(
        'Prior employer HR left voicemail; awaiting callback.',
        'Employer uses The Work Number; verification fee approved by client.',
        'Employer is out of business. Requested W-2 or pay stub from candidate as alternative proof.')[MOD(ABS(HASH(ORDER_ID,k,'n')),3)]::STRING
    WHEN CURRENT_COMPONENT = 'Drug Screen' OR CURRENT_COMPONENT = 'Drug Test Scheduling' THEN
      ARRAY_CONSTRUCT(
        'Candidate has not visited collection site. Reminder sent; donor pass expires in 3 days.',
        'Specimen received by lab. Results pending MRO review.',
        'Collection site rescheduled due to closure. New donor pass issued.')[MOD(ABS(HASH(ORDER_ID,k,'n')),3)]::STRING
    WHEN CURRENT_STATUS = 'Awaiting Candidate' THEN
      'Waiting on candidate to complete ' || CURRENT_COMPONENT || '. Automated reminder sent by email and SMS.'
    WHEN CURRENT_STATUS = 'On Hold' THEN
      'Order placed on hold at client request pending adjudication matrix review.'
    WHEN CURRENT_STATUS = 'Complete' THEN
      'All components complete. Report released to client portal.'
    ELSE 'Component ' || COALESCE(CURRENT_COMPONENT,'') || ' in progress. No issues noted.'
  END
FROM ORDERS
CROSS JOIN (SELECT 1 AS k UNION ALL SELECT 2) ks
WHERE CURRENT_STATUS <> 'Complete' OR (MOD(ORDER_ID, 10) = 0 AND k = 1);

-- Call / chat transcripts built from realistic templates (deterministic, no LLM cost).
-- Callers skew toward orders that are stuck, so "stuck orders vs calls" has signal.
CREATE OR REPLACE TEMPORARY TABLE _CALL_SEED AS
WITH g AS (SELECT ROW_NUMBER() OVER (ORDER BY SEQ4()) AS i FROM TABLE(GENERATOR(ROWCOUNT => 1500))),
stuck AS (SELECT ORDER_ID, ROW_NUMBER() OVER (ORDER BY ORDER_ID) AS rn
          FROM ORDERS WHERE CURRENT_STATUS <> 'Complete' AND ORDER_ID <> 4471823),
stuck_cnt AS (SELECT COUNT(*) AS cnt FROM stuck),
picks AS (
  SELECT g.i,
         MOD(g.i, 10) < 8 AS pick_stuck,
         1 + MOD(ABS(HASH(g.i,'so')), sc.cnt) AS stuck_rn,
         4421824 + MOD(ABS(HASH(g.i,'ao')), 50000) AS any_order
  FROM g CROSS JOIN stuck_cnt sc
)
SELECT p.i,
  CASE WHEN p.i <= 3 THEN 4471823                 -- 3 calls from Maria Lopez
       WHEN p.pick_stuck THEN s.ORDER_ID          -- 80% of calls come from orders that aren't complete
       ELSE p.any_order END AS order_id
FROM picks p
LEFT JOIN stuck s ON s.rn = p.stuck_rn;

INSERT INTO CALL_TRANSCRIPTS
WITH s AS (
  SELECT c.i, o.ORDER_ID, o.CANDIDATE_ID, o.CURRENT_STATUS, COALESCE(o.CURRENT_COMPONENT,'final report') AS comp,
         o.ETA_DATE, cl.CLIENT_NAME, ca.FULL_NAME, ca.FIRST_NAME, ca.PHONE, ca.EMAIL, ca.DOB,
         RIGHT(ca.SSN, 4) AS ssn4,
         IFF(MOD(c.i,3) = 0, 'CHAT', 'VOICE') AS channel,
         ARRAY_CONSTRUCT('Kayla','Derek','Monique','Andre','Brittany','Jose','Tasha','Ryan')[MOD(ABS(HASH(c.i,'ag')),8)]::STRING AS agent,
         CASE WHEN c.i <= 3 THEN 'STATUS'
              WHEN o.CURRENT_STATUS = 'Awaiting Candidate' THEN IFF(MOD(c.i,2)=0,'PORTAL','DRUG')
              ELSE ARRAY_CONSTRUCT('STATUS','STATUS','STATUS','DELAY','DELAY','EDU','DISPUTE','PORTAL','DRUG','ADVERSE','EMPLOYER')
                     [MOD(ABS(HASH(c.i,'rsn')),11)]::STRING END AS reason
  FROM _CALL_SEED c
  JOIN ORDERS o ON o.ORDER_ID = c.order_id
  JOIN CANDIDATES ca ON ca.CANDIDATE_ID = o.CANDIDATE_ID
  JOIN CLIENTS cl ON cl.CLIENT_ID = o.CLIENT_ID
)
SELECT
  'CT-' || LPAD(i::STRING, 7, '0'),
  ORDER_ID, CANDIDATE_ID, channel,
  IFF(channel = 'VOICE', 'AMAZON_CONNECT', 'SALESFORCE'),
  agent,
  CASE WHEN i <= 3 THEN DATEADD(day, -(7 - i * 2), CURRENT_DATE())::TIMESTAMP_NTZ + INTERVAL '10 hour'
       ELSE TIMESTAMPADD(minute, 480 + MOD(ABS(HASH(i,'min')), 600),
              DATEADD(day, -MOD(ABS(HASH(i,'day')), 45), CURRENT_DATE())::TIMESTAMP_NTZ) END,
  120 + MOD(ABS(HASH(i,'dur')), 900),
  'Agent: Thank you for calling Sentinel Screening, this is ' || agent || '. Can I get your order number?\n' ||
  'Caller: Hi, yes, it is ' || ORDER_ID || '. My name is ' || FULL_NAME || '.\n' ||
  'Agent: Thanks ' || FIRST_NAME || '. To verify, can you confirm your date of birth and the last four of your social?\n' ||
  'Caller: ' || TO_CHAR(DOB, 'MMMM DD, YYYY') || ', and the last four are ' || ssn4 || '.\n' ||
  CASE reason
    WHEN 'STATUS' THEN
      'Caller: I applied with ' || CLIENT_NAME || ' and they said my background check is still pending. Where is it at?\n' ||
      'Agent: I see your order is currently ' || LOWER(CURRENT_STATUS) || ' on the ' || comp || '. ' ||
      IFF(i <= 3, 'The county court is reporting a backlog, which is why it is taking longer than usual.', 'Everything else on the order is complete.') || '\n' ||
      'Caller: ' || IFF(i <= 3, 'This is my ' || ARRAY_CONSTRUCT('first','second','third')[i-1]::STRING || ' time calling. I am supposed to start work next week and I am really worried I will lose the job.',
                       'Okay. Do you know how much longer it will take?') || '\n' ||
      'Agent: ' || IFF(i <= 3, 'I completely understand. I am escalating this to our county team lead and we will call you back as soon as the court returns results. I will also note that you have a start date coming up.',
                       'Our current estimate is ' || COALESCE(TO_CHAR(ETA_DATE,'MMMM DD'),'within a few days') || '. You can also track it in the candidate portal.') || '\n'
    WHEN 'DELAY' THEN
      'Caller: This has been taking forever. It has been over a week and my employer keeps asking me about it.\n' ||
      'Agent: I apologize for the delay. The ' || comp || ' is taking longer than normal on our end.\n' ||
      'Caller: That is really frustrating. Nobody told me anything. I could lose this offer.\n' ||
      'Agent: I understand. I will flag the order for priority review and request an update from the fulfillment team today.\n'
    WHEN 'EDU' THEN
      'Caller: I got an email saying you could not verify my degree. I definitely graduated.\n' ||
      'Agent: I see the registrar has not responded yet. Sometimes schools require a signed release. Did you attend under a different name?\n' ||
      'Caller: Yes, my maiden name was different. Can I just send you my diploma?\n' ||
      'Agent: Yes, you can upload a copy of your diploma or transcript in the portal and we will use it to expedite verification.\n'
    WHEN 'DISPUTE' THEN
      'Caller: My employer said something came up on my report that is not mine. I have never been arrested.\n' ||
      'Agent: I am sorry to hear that. You have the right to dispute any information on your report. I will open a dispute for you.\n' ||
      'Caller: How long does that take? I really need this job.\n' ||
      'Agent: Disputes are typically resolved within 30 days, and often much faster. We will re-verify the record with the court and notify you and the employer.\n'
    WHEN 'PORTAL' THEN
      'Caller: I keep trying to log into the portal to sign the consent form but it says my link expired.\n' ||
      'Agent: I can resend that link to the email on file. The order is waiting on your ' || comp || ' before we can continue.\n' ||
      'Caller: Okay, please send it. My email is ' || EMAIL || '.\n' ||
      'Agent: Done. You should receive it in a few minutes. Once completed, the order will move forward automatically.\n'
    WHEN 'DRUG' THEN
      'Caller: I need to reschedule my drug test. The collection site near me was closed when I went.\n' ||
      'Agent: I am sorry about that. I can issue a new donor pass for a different location. What zip code are you in?\n' ||
      'Caller: I can be reached at ' || PHONE || ' if you need anything else.\n' ||
      'Agent: I have issued a new donor pass. You have five days to complete the collection.\n'
    WHEN 'ADVERSE' THEN
      'Caller: I received a pre-adverse action letter from ' || CLIENT_NAME || '. What does that mean?\n' ||
      'Agent: It means the employer is reviewing information in your report before making a decision. You have a copy of the report and a summary of your rights.\n' ||
      'Caller: Can I talk to someone about what is on it?\n' ||
      'Agent: Yes, I can walk you through it, and if anything is inaccurate we can open a dispute.\n'
    ELSE
      'Caller: I am calling from HR at ' || CLIENT_NAME || '. We have a candidate with a start date Monday and the report is still pending.\n' ||
      'Agent: I see the order is pending on the ' || comp || '. I can provide an ETA and flag it for expedite.\n' ||
      'Caller: Please do. We have several candidates stuck like this.\n' ||
      'Agent: Understood. I will escalate to your account manager as well.\n'
  END ||
  'Agent: Is there anything else I can help you with today?\n' ||
  'Caller: ' || IFF(MOD(i,4)=0, 'No, that is it. Thanks for your help.', 'No. I just hope this gets resolved soon.') || '\n' ||
  'Agent: Thank you for calling Sentinel Screening. Have a great day.'
FROM s;

-- Salesforce cases for a subset of contacts
INSERT INTO SFDC_CASES
SELECT 'CS-' || LPAD(ROW_NUMBER() OVER (ORDER BY CONTACT_ID)::STRING, 6, '0'),
       CONTACT_ID, ORDER_ID,
       'Candidate inquiry - order ' || ORDER_ID,
       ARRAY_CONSTRUCT('Closed','Closed','Open','Escalated')[MOD(ABS(HASH(CONTACT_ID,'cs')),4)]::STRING,
       ARRAY_CONSTRUCT('Low','Medium','High')[MOD(ABS(HASH(CONTACT_ID,'pr')),3)]::STRING,
       STARTED_AT
FROM CALL_TRANSCRIPTS
WHERE MOD(ABS(HASH(CONTACT_ID)), 3) = 0 OR ORDER_ID = 4471823;

-- =====================================================================
-- 3. AI ENRICHMENT  (Cortex AI functions)
-- =====================================================================
USE SCHEMA SCREENING_AI_LAB.ENRICHED;

-- Step 1: redact PII before anything downstream (search / agent) sees it
CREATE OR REPLACE TABLE TRANSCRIPTS_REDACTED AS
SELECT CONTACT_ID, ORDER_ID, CANDIDATE_ID, CHANNEL, SOURCE_SYSTEM, AGENT_NAME, STARTED_AT, DURATION_SEC,
       AI_REDACT(TRANSCRIPT)::STRING AS TRANSCRIPT_REDACTED
FROM SCREENING_AI_LAB.RAW.CALL_TRANSCRIPTS;

-- Step 2: classify, sentiment, summarize
CREATE OR REPLACE TABLE CALL_INSIGHTS AS
SELECT
  t.CONTACT_ID, t.ORDER_ID, t.CANDIDATE_ID, t.CHANNEL, t.SOURCE_SYSTEM, t.AGENT_NAME,
  t.STARTED_AT, t.STARTED_AT::DATE AS CALL_DATE, t.DURATION_SEC,
  t.TRANSCRIPT_REDACTED,
  AI_CLASSIFY(t.TRANSCRIPT_REDACTED,
    ['Order status inquiry','Delay complaint','Education verification issue','Dispute of report findings',
     'Portal or consent form help','Drug test scheduling','Adverse action question','Employer / HR escalation']
  ):labels[0]::STRING AS CALL_REASON,
  AI_SENTIMENT(t.TRANSCRIPT_REDACTED):categories[0]:sentiment::STRING AS SENTIMENT,
  AI_COMPLETE('claude-sonnet-4-5',
    'Summarize this background-screening customer service call in 2 sentences. ' ||
    'Then on a new line starting with "Commitment:" state anything the agent promised the caller, or "None". ' ||
    'Transcript:\n' || t.TRANSCRIPT_REDACTED) AS CALL_SUMMARY
FROM TRANSCRIPTS_REDACTED t;

-- Demo query (run live): top call drivers
-- SELECT AI_AGG(CALL_SUMMARY, 'What are the top reasons candidates are calling and what would reduce call volume? Answer in 5 bullets.')
-- FROM CALL_INSIGHTS WHERE CALL_DATE >= CURRENT_DATE() - 7;

-- Ops notes are internal free text with no candidate PII -> searchable as-is
CREATE OR REPLACE VIEW SEARCH_CORPUS AS
SELECT 'CALL' AS DOC_TYPE, CONTACT_ID AS DOC_ID, ORDER_ID, STARTED_AT AS DOC_TS,
       CALL_REASON, TRANSCRIPT_REDACTED || '\nSummary: ' || CALL_SUMMARY AS CONTENT
FROM CALL_INSIGHTS
UNION ALL
SELECT 'OPS_NOTE', NOTE_ID::STRING, ORDER_ID, CREATED_AT, NULL, NOTE_TEXT
FROM SCREENING_AI_LAB.RAW.OPS_NOTES;

-- =====================================================================
-- 4. CORTEX SEARCH  (only redacted text is indexed)
-- =====================================================================
USE SCHEMA SCREENING_AI_LAB.AI;

CREATE OR REPLACE CORTEX SEARCH SERVICE CS_INTERACTIONS_SEARCH
  ON CONTENT
  ATTRIBUTES DOC_TYPE, ORDER_ID, CALL_REASON
  WAREHOUSE = SCREENING_DEMO_WH
  TARGET_LAG = '1 hour'
  COMMENT = 'Redacted call/chat transcripts and fulfillment ops notes'
AS SELECT CONTENT, DOC_TYPE, DOC_ID, ORDER_ID::STRING AS ORDER_ID, CALL_REASON, DOC_TS
   FROM SCREENING_AI_LAB.ENRICHED.SEARCH_CORPUS;

-- =====================================================================
-- 5. SEMANTIC VIEW  (orders + candidates + clients + call insights)
-- =====================================================================
CREATE OR REPLACE SEMANTIC VIEW ORDERS_SV
  TABLES (
    orders     AS SCREENING_AI_LAB.RAW.ORDERS     PRIMARY KEY (ORDER_ID)
      COMMENT = 'Background screening orders',
    candidates AS SCREENING_AI_LAB.RAW.CANDIDATES PRIMARY KEY (CANDIDATE_ID)
      COMMENT = 'Candidates being screened',
    clients    AS SCREENING_AI_LAB.RAW.CLIENTS    PRIMARY KEY (CLIENT_ID)
      COMMENT = 'Employer clients',
    calls      AS SCREENING_AI_LAB.ENRICHED.CALL_INSIGHTS PRIMARY KEY (CONTACT_ID)
      COMMENT = 'Customer service calls and chats with AI-derived reason, sentiment and summary'
  )
  RELATIONSHIPS (
    orders_to_candidates AS orders (CANDIDATE_ID) REFERENCES candidates,
    orders_to_clients    AS orders (CLIENT_ID)    REFERENCES clients,
    calls_to_orders      AS calls  (ORDER_ID)     REFERENCES orders
  )
  FACTS (
    orders.days_in_status AS DAYS_IN_STATUS COMMENT = 'Days the order has been in its current status',
    calls.duration_sec    AS DURATION_SEC   COMMENT = 'Call duration in seconds'
  )
  DIMENSIONS (
    orders.order_id          AS ORDER_ID          COMMENT = 'Order number, e.g. 4471823',
    orders.package           AS PACKAGE           COMMENT = 'Screening package',
    orders.order_date        AS ORDER_DATE        COMMENT = 'Date ordered',
    orders.current_status    AS CURRENT_STATUS    COMMENT = 'Complete, In Progress, Awaiting Candidate, On Hold',
    orders.current_component AS CURRENT_COMPONENT COMMENT = 'Pending component, e.g. County Criminal Search, Education Verification',
    orders.eta_date          AS ETA_DATE          COMMENT = 'Estimated completion date',
    candidates.candidate_name AS FULL_NAME        COMMENT = 'Candidate full name',
    candidates.candidate_state AS STATE           COMMENT = 'Candidate state',
    clients.client_name      AS CLIENT_NAME       COMMENT = 'Employer client name',
    clients.client_industry  AS INDUSTRY          COMMENT = 'Client industry',
    calls.contact_id         AS CONTACT_ID        COMMENT = 'Call or chat id',
    calls.call_date          AS CALL_DATE         COMMENT = 'Date of the call',
    calls.channel            AS CHANNEL           COMMENT = 'VOICE or CHAT',
    calls.call_reason        AS CALL_REASON       COMMENT = 'AI-classified reason for the call',
    calls.sentiment          AS SENTIMENT         COMMENT = 'AI sentiment: positive, neutral, negative, mixed',
    calls.call_summary       AS CALL_SUMMARY      COMMENT = 'AI summary of the call including commitments made'
  )
  METRICS (
    orders.order_count        AS COUNT(DISTINCT orders.ORDER_ID) COMMENT = 'Number of orders',
    orders.avg_days_in_status AS AVG(orders.DAYS_IN_STATUS)      COMMENT = 'Average days in current status',
    calls.call_count          AS COUNT(calls.CONTACT_ID)         COMMENT = 'Number of calls/chats',
    calls.callers             AS COUNT(DISTINCT calls.CANDIDATE_ID) COMMENT = 'Distinct candidates who contacted us',
    calls.avg_duration_min    AS AVG(calls.DURATION_SEC) / 60    COMMENT = 'Average call duration in minutes'
  )
  COMMENT = 'Background screening orders and customer service interactions. "Stuck" = not Complete and days_in_status > 5.';

-- =====================================================================
-- 6. GOVERNANCE  (roles + masking on candidate PII)
-- =====================================================================
USE SCHEMA SCREENING_AI_LAB.GOV;

CREATE ROLE IF NOT EXISTS LAB_ADMIN      COMMENT = 'AI lab / sandbox role - full PII visibility';
CREATE ROLE IF NOT EXISTS SUPPORT_AGENT COMMENT = 'Customer service agent - PII masked';
GRANT ROLE LAB_ADMIN      TO ROLE SYSADMIN;
GRANT ROLE SUPPORT_AGENT TO ROLE SYSADMIN;
SET ME = CURRENT_USER();
GRANT ROLE LAB_ADMIN      TO USER IDENTIFIER($ME);
GRANT ROLE SUPPORT_AGENT TO USER IDENTIFIER($ME);

CREATE OR REPLACE MASKING POLICY PII_STRING_MASK AS (val STRING) RETURNS STRING ->
  CASE WHEN CURRENT_ROLE() IN ('LAB_ADMIN','ACCOUNTADMIN') THEN val
       ELSE '***MASKED***' END;

CREATE OR REPLACE MASKING POLICY PII_DATE_MASK AS (val DATE) RETURNS DATE ->
  CASE WHEN CURRENT_ROLE() IN ('LAB_ADMIN','ACCOUNTADMIN') THEN val
       ELSE NULL END;

CREATE OR REPLACE MASKING POLICY PII_NAME_MASK AS (val STRING) RETURNS STRING ->
  CASE WHEN CURRENT_ROLE() IN ('LAB_ADMIN','ACCOUNTADMIN') THEN val
       ELSE LEFT(val, 1) || '***' END;

ALTER TABLE SCREENING_AI_LAB.RAW.CANDIDATES MODIFY
  COLUMN SSN       SET MASKING POLICY PII_STRING_MASK,
  COLUMN EMAIL     SET MASKING POLICY PII_STRING_MASK,
  COLUMN PHONE     SET MASKING POLICY PII_STRING_MASK,
  COLUMN DOB       SET MASKING POLICY PII_DATE_MASK,
  COLUMN LAST_NAME SET MASKING POLICY PII_NAME_MASK,
  COLUMN FULL_NAME SET MASKING POLICY PII_NAME_MASK;
ALTER TABLE SCREENING_AI_LAB.RAW.CALL_TRANSCRIPTS MODIFY
  COLUMN TRANSCRIPT SET MASKING POLICY PII_STRING_MASK;   -- raw transcript only visible to the lab

-- Grants (both roles can use the lab objects; masking decides what they see)
GRANT USAGE ON WAREHOUSE SCREENING_DEMO_WH TO ROLE LAB_ADMIN;
GRANT USAGE ON WAREHOUSE SCREENING_DEMO_WH TO ROLE SUPPORT_AGENT;
GRANT USAGE ON DATABASE SCREENING_AI_LAB   TO ROLE LAB_ADMIN;
GRANT USAGE ON DATABASE SCREENING_AI_LAB   TO ROLE SUPPORT_AGENT;
GRANT USAGE ON ALL SCHEMAS IN DATABASE SCREENING_AI_LAB TO ROLE LAB_ADMIN;
GRANT USAGE ON ALL SCHEMAS IN DATABASE SCREENING_AI_LAB TO ROLE SUPPORT_AGENT;
GRANT SELECT ON ALL TABLES IN DATABASE SCREENING_AI_LAB TO ROLE LAB_ADMIN;
GRANT SELECT ON ALL TABLES IN DATABASE SCREENING_AI_LAB TO ROLE SUPPORT_AGENT;
GRANT SELECT ON ALL VIEWS  IN DATABASE SCREENING_AI_LAB TO ROLE LAB_ADMIN;
GRANT SELECT ON ALL VIEWS  IN DATABASE SCREENING_AI_LAB TO ROLE SUPPORT_AGENT;
GRANT SELECT ON SEMANTIC VIEW SCREENING_AI_LAB.AI.ORDERS_SV TO ROLE LAB_ADMIN;
GRANT SELECT ON SEMANTIC VIEW SCREENING_AI_LAB.AI.ORDERS_SV TO ROLE SUPPORT_AGENT;
GRANT USAGE ON CORTEX SEARCH SERVICE SCREENING_AI_LAB.AI.CS_INTERACTIONS_SEARCH TO ROLE LAB_ADMIN;
GRANT USAGE ON CORTEX SEARCH SERVICE SCREENING_AI_LAB.AI.CS_INTERACTIONS_SEARCH TO ROLE SUPPORT_AGENT;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE LAB_ADMIN;
GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE SUPPORT_AGENT;

-- =====================================================================
-- 7. CORTEX AGENT  (publish to Snowflake Intelligence / CoWork)
-- =====================================================================
USE SCHEMA SCREENING_AI_LAB.AI;

CREATE OR REPLACE AGENT CS_INSIGHTS_AGENT
  COMMENT = 'Customer service insights agent over orders, ops notes and call transcripts (demo)'
  PROFILE = '{"display_name": "CS Insights Agent"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto
instructions:
  response: >
    You help Sentinel Screening customer service and AI lab users understand candidate
    orders, call drivers and what was promised to candidates. Be concise. Use tables for
    breakdowns. When asked to draft candidate messaging, be empathetic, plain-language and
    never speculate about criminal record findings.
  orchestration: >
    Use Orders_Analyst for counts, statuses, stuck orders (not Complete and days_in_status > 5),
    call reasons and sentiment trends. Use Interactions_Search for what was said on calls,
    commitments made to candidates, and fulfillment ops notes for a specific order.
    For questions about a specific order or candidate, use both.
tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: Orders_Analyst
      description: Structured data on orders, candidates, clients and AI-enriched call insights.
  - tool_spec:
      type: cortex_search
      name: Interactions_Search
      description: Redacted call/chat transcripts with summaries, plus fulfillment ops notes.
tool_resources:
  Orders_Analyst:
    semantic_view: SCREENING_AI_LAB.AI.ORDERS_SV
    execution_environment:
      type: warehouse
      warehouse: SCREENING_DEMO_WH
  Interactions_Search:
    name: SCREENING_AI_LAB.AI.CS_INTERACTIONS_SEARCH
    max_results: 8
    id_column: DOC_ID
    title_column: DOC_TYPE
$$;

GRANT USAGE ON AGENT SCREENING_AI_LAB.AI.CS_INSIGHTS_AGENT TO ROLE LAB_ADMIN;
GRANT USAGE ON AGENT SCREENING_AI_LAB.AI.CS_INSIGHTS_AGENT TO ROLE SUPPORT_AGENT;

-- To show in Snowflake Intelligence / CoWork (if your account uses the SI object):
-- ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT SCREENING_AI_LAB.AI.CS_INSIGHTS_AGENT;

-- =====================================================================
-- 8. SANDBOX  (demo step 1: zero-copy clone for the lab team - run live)
-- =====================================================================
-- CREATE OR REPLACE DATABASE AI_SANDBOX CLONE SCREENING_AI_LAB;
-- GRANT OWNERSHIP ON DATABASE AI_SANDBOX TO ROLE LAB_ADMIN COPY CURRENT GRANTS;

-- =====================================================================
-- 9. VERIFY + DEMO QUERIES
-- =====================================================================
SELECT 'CLIENTS' t, COUNT(*) n FROM SCREENING_AI_LAB.RAW.CLIENTS UNION ALL
SELECT 'CANDIDATES', COUNT(*) FROM SCREENING_AI_LAB.RAW.CANDIDATES UNION ALL
SELECT 'ORDERS', COUNT(*) FROM SCREENING_AI_LAB.RAW.ORDERS UNION ALL
SELECT 'ORDER_STATUS_HISTORY', COUNT(*) FROM SCREENING_AI_LAB.RAW.ORDER_STATUS_HISTORY UNION ALL
SELECT 'OPS_NOTES', COUNT(*) FROM SCREENING_AI_LAB.RAW.OPS_NOTES UNION ALL
SELECT 'CALL_TRANSCRIPTS', COUNT(*) FROM SCREENING_AI_LAB.RAW.CALL_TRANSCRIPTS UNION ALL
SELECT 'SFDC_CASES', COUNT(*) FROM SCREENING_AI_LAB.RAW.SFDC_CASES UNION ALL
SELECT 'CALL_INSIGHTS', COUNT(*) FROM SCREENING_AI_LAB.ENRICHED.CALL_INSIGHTS;

-- Masking moment (demo step 3): run as each role
-- USE ROLE LAB_ADMIN;      SELECT FULL_NAME, SSN, DOB, PHONE FROM SCREENING_AI_LAB.RAW.CANDIDATES WHERE CANDIDATE_ID = 1;
-- USE ROLE SUPPORT_AGENT; SELECT FULL_NAME, SSN, DOB, PHONE FROM SCREENING_AI_LAB.RAW.CANDIDATES WHERE CANDIDATE_ID = 1;

/* Agent prompts to type live:
   1. "Why are candidates calling us most this week? Break it down by reason and sentiment."
   2. "Which orders have been stuck in county search more than 5 days, and how many of those candidates called in?"
   3. "Summarize the last 3 calls for Maria Lopez and what we promised her."   (re-ask as SUPPORT_AGENT)
   4. "What's the status of order 4471823 and what do the latest ops notes say?"
   5. "Draft what we should tell a candidate waiting on education verification."
*/
