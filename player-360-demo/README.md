# Player 360 Demo — Game Analytics with Cortex Agent

A self-contained demo for a gaming analytics platform:

- **Synthetic data**: 6,000 players, ~22M sessions, ~5.6M purchases, ~22M game events
- **Dynamic tables**: Demographics, retention, player rankings, ad engagement, points tracking
- **Analytic views**: DAU, MAU, ARPDAU, DARPPU, cohort LTV, churn rates, ad conversion
- **Semantic view** for Cortex Analyst
- A **Cortex Agent** (`PLAYER_360_AGENT`) for conversational game analytics in Snowflake CoWork

All objects are created in the `PLAYER_360` database across three schemas: `RAW`, `ANALYTIC`, `APP`.

## Contents

```
sql/01_setup_and_tables.sql      database, schemas, all table DDL
sql/02_load_data.sql             generate all RAW data + small lookup tables via SQL (~5-10 min)
sql/03_analytic_objects.sql      dynamic tables (6) + analytic views (7)
sql/04_semantic_view.sql         PLAYER_360_SEMANTIC_VIEW in APP schema
sql/05_agent.sql                 PLAYER_360_AGENT (Cortex Agent)
```

## Prerequisites

- A role that can create a database, dynamic tables, semantic views, and agents. `ACCOUNTADMIN` is simplest.
- A warehouse. The scripts use **`COMPUTE_WH`** for data loading and create **`PLAYER_360_BUILD_WH`** (XS) for dynamic tables. Find/replace `COMPUTE_WH` if yours is named differently.
- Cortex Agents and CoWork available in the account. If agent creation fails:
  ```sql
  ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
  ```

## Run order

1. Run each SQL script in order: `01` → `02` → `03` → `04` → `05`.

   ```bash
   # From terminal with Snowflake CLI:
   snow sql -f sql/01_setup_and_tables.sql -c <connection>
   snow sql -f sql/02_load_data.sql -c <connection>
   snow sql -f sql/03_analytic_objects.sql -c <connection>
   snow sql -f sql/04_semantic_view.sql -c <connection>
   snow sql -f sql/05_agent.sql -c <connection>
   ```

2. **Step 02 takes the longest** (~5-10 min on XS, ~2-3 min on MEDIUM). It generates:

   | Table | Rows |
   |---|---|
   | RAW.USERS | 6,000 |
   | RAW.SESSIONS | ~22M |
   | RAW.PURCHASES | ~5.6M |
   | RAW.GAME_EVENTS | ~22M |
   | RAW.ACHIEVEMENTS | 6,000 |
   | RAW.SUPPORT_TICKETS | ~660 |
   | ANALYTIC.DAILY_ACTIVE_USERS | ~3,600 |
   | ANALYTIC.MONTHLY_ACTIVE_USERS | ~120 |

3. **Step 03** creates dynamic tables that will auto-refresh. Initial refresh may take a few minutes. Wait for them to finish before running 04.

4. Open **Snowsight → AI & ML → Snowflake CoWork** and select **Player 360 Agent**.
   Try questions like:
   - "How many daily active users did we have last month?"
   - "What is the average revenue per paying user?"
   - "Show me day-1 and day-7 retention rates"
   - "Which countries have the most players?"
   - "What percentage of players are in the Diamond rank or above?"

## Architecture

```
RAW Schema                          ANALYTIC Schema (Dynamic Tables)
┌─────────────────────┐            ┌──────────────────────────┐
│ USERS (6K)          │──────┐     │ DEMOGRAPHICS (DT)        │
│ SESSIONS (22M)      │──┐   ├────→│ RETENTION (DT)           │
│ PURCHASES (5.6M)    │──┤   │     │ AD_ENGAGEMENT (DT)       │
│ GAME_EVENTS (22M)   │──┤   │     │ POINTS_PER_EVENT (DT)    │
│ ACHIEVEMENTS (6K)   │  │   │     │ POINTS_PER_USER (DT)     │
│ SUPPORT_TICKETS     │  │   │     │ USER_RANKINGS (DT)       │
└─────────────────────┘  │   │     │ + 7 analytic views       │
                         │   │     │ + DAU/MAU lookup tables   │
                         │   │     └───────────┬──────────────┘
                         │   │                 │
                         ▼   ▼                 ▼
                    ┌────────────────────────────────┐
                    │ APP.PLAYER_360_SEMANTIC_VIEW    │
                    └──────────┬─────────────────────┘
                               │
                               ▼
                    ┌────────────────────────────────┐
                    │ APP.PLAYER_360_AGENT           │
                    │  Tool: Cortex Analyst (SV)     │
                    └────────────────────────────────┘
```

## What's in the data

- **6,000 players** (IDs 1001–7000) across 11 countries
- **~22M sessions** spanning 2016-08-20 to 2026-07-14, 6 device types
- **~5.6M purchases** with 5 ad types, 5 purchase types (60% are ad views with no purchase)
- **~22M game events** with kills, assists, damage, headshots, heals, boosts, weapons, distance
- **Ranking system**: Bronze → Silver → Gold → Platinum → Diamond → Elite → Champion → Unreal
- **Dynamic tables** compute demographics, retention, points, rankings, and ad engagement in real time
