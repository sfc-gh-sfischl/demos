# Customer Service AI Lab Demo (Sentinel Screening)

A fictional background-screening company, "Sentinel Screening", used to demo Snowflake Cortex AI for customer service. All the data is synthetic.

## Contents
- `screening_ai_lab_demo.sql` builds the `SCREENING_AI_LAB` database (schemas RAW, ENRICHED, AI and GOV) and everything in it.

The script creates:
- **Synthetic data:**
  - clients, candidates and orders
  - order status history
  - ops notes
  - call transcripts
  - SFDC cases
- **Enrichment with Cortex AI functions:**
  - AI_REDACT, AI_CLASSIFY, AI_SENTIMENT and AI_COMPLETE
  - results land in `ENRICHED.CALL_INSIGHTS`
- **AI layer:**
  - Cortex Search service `AI.CS_INTERACTIONS_SEARCH`
  - semantic view `AI.ORDERS_SV`
  - Cortex Agent `AI.CS_INSIGHTS_AGENT`
- **Governance:**
  - PII masking policies based on `CURRENT_ROLE()`
  - roles `LAB_ADMIN` (unmasked) and `SUPPORT_AGENT` (masked)

## Run
Run the script as ACCOUNTADMIN, using warehouse `SCREENING_DEMO_WH` (the script creates it).

## Demo prompts
- Why is order 4471823 delayed, and how often has the candidate called?
- What are the top call reasons, and how is sentiment trending?
- Which clients have the most orders stuck longer than 7 days?
- Summarize negative drug-test calls and the suggested next steps.
- Switch to SUPPORT_AGENT and re-run a prompt to show masking.

Deck: https://docs.google.com/presentation/d/1PuWh-pbI4xVJqlHaO-uke1gIctXemYsq74aoLqSyVl4/edit
