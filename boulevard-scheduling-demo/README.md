# Boulevard Scheduling Demo — Labor Forecasting & Intelligent Scheduling

A self-contained demo for salon/spa labor forecasting and intelligent scheduling:

- **Synthetic data**: 7 tables, ~13K rows, 10 salon locations across US cities
- **ML.FORECAST model**: Multi-series time-series forecast (50 models in one SQL statement)
- **Stored procedure**: Staffing recommendation engine (custom tool for the agent)
- **Semantic view** for Cortex Analyst
- A **Cortex Agent** (`SCHEDULING_AGENT`) for conversational scheduling in Snowflake CoWork

All objects are created in `SPABOOKINGS.PUBLIC`.

## Contents

```
sql/01_setup_and_tables.sql      database, schema, 7 tables, 1 view
sql/02_load_data.sql             PUT/COPY CSVs + inline INSERTs for small tables
sql/03_semantic_view.sql         SCHEDULING_SEMANTIC_VIEW
sql/04_stored_procedure.sql      RECOMMEND_SCHEDULE (staffing recommendations)
sql/05_forecast_model.sql        ML.FORECAST train + 14-day prediction
sql/06_agent.sql                 SCHEDULING_AGENT (Cortex Agent)
data/boulevard_appointments.csv              4,514 appointment rows
data/boulevard_commerce_order_lines.csv      4,368 order line rows
notebooks/boulevard_labor_scheduling.ipynb   end-to-end walkthrough notebook
scripts/generate_boulevard_sample.py         Python generator (re-creates the CSVs)
scripts/boulevard_ml_pipeline.py             ML pipeline for CLIENT_REBOOKING_PREDICTIONS
```

## Prerequisites

- A role that can create a database, semantic views, agents, and ML models. `ACCOUNTADMIN` is simplest for a demo account.
- A warehouse. The scripts use **`COMPUTE_WH`**; find/replace it in all files if yours has a different name.
- Cortex Agents and CoWork available in the account. If agent creation fails because no model is available in your region, run:
  ```sql
  ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
  ```

## Run order

1. Run `sql/01_setup_and_tables.sql` in Snowsight or via CLI.

2. **Load data (step 02)** — the PUT commands must be run from **SnowSQL or `snow` CLI**, not Snowsight:

   ```bash
   cd boulevard_scheduling_demo_package
   snow sql -f sql/01_setup_and_tables.sql -c <connection>
   snow sql -f sql/02_load_data.sql -c <connection>
   snow sql -f sql/03_semantic_view.sql -c <connection>
   snow sql -f sql/04_stored_procedure.sql -c <connection>
   snow sql -f sql/05_forecast_model.sql -c <connection>
   snow sql -f sql/06_agent.sql -c <connection>
   ```

   Alternatively, you can upload the CSVs manually via Snowsight:
   - Go to **Data → Databases → SPABOOKINGS → PUBLIC → Stages → SPABOOKINGS_LOAD**
   - Upload both CSV files from the `data/` folder
   - Then run the COPY INTO statements from `02_load_data.sql`

2. The last statement of `02` prints row counts. Expect roughly:

   | Table | Rows |
   |---|---|
   | APPOINTMENTS | ~4,500 |
   | ORDERLINES | ~4,400 |
   | PROVIDER_SKILLS | 20 |
   | PROVIDER_AVAILABILITY | 140 |
   | DAILY_APPOINTMENT_VOLUME | ~3,700 |

3. `05_forecast_model.sql` trains the ML model (~1-2 min on XS warehouse) and populates `LABOR_FORECAST_RESULTS` (~700 rows).

4. Open **Snowsight → AI & ML → Snowflake CoWork** and select **Scheduling Agent**.
   Try questions like:
   - "What is the forecasted demand for next week across all locations?"
   - "Are we understaffed anywhere next week?"
   - "Which providers are available on Saturdays?"

5. (Optional) Upload `notebooks/boulevard_labor_scheduling.ipynb` to a Snowflake Notebook for the guided walkthrough. Add `matplotlib` and `snowflake-ml-python` packages if running in Snowsight.

## Re-generating the data (optional)

To regenerate the CSVs from scratch (e.g. to change the date range or number of clients):

```bash
pip install pandas numpy
python scripts/generate_boulevard_sample.py
```

To populate the `CLIENT_REBOOKING_PREDICTIONS` table (250 rows, ML-based churn risk):

```bash
pip install snowflake-ml-python scikit-learn
python scripts/boulevard_ml_pipeline.py
```

This trains a GradientBoosting model, registers it in the Model Registry, and writes predictions to the table.

## Architecture

```
┌─────────────────────────┐
│   APPOINTMENTS (4,500)  │──→ V_DAILY_DEMAND (view) ──→ ML.FORECAST model
│   ORDERLINES  (4,400)   │                                    │
│   CLIENT_REBOOKING (250)│                          LABOR_FORECAST_RESULTS
└─────────────────────────┘                                    │
                                                               ▼
┌─────────────────────────┐       ┌───────────────────────────────────────┐
│   PROVIDER_SKILLS  (20) │──→    │  SCHEDULING_SEMANTIC_VIEW             │
│   PROVIDER_AVAIL  (140) │──→    │  (Cortex Analyst data layer)          │
│   DAILY_VOLUME  (3,700) │──→    └───────────┬───────────────────────────┘
└─────────────────────────┘                   │
                                              ▼
                                 ┌────────────────────────┐
                                 │   SCHEDULING_AGENT     │
                                 │  Tools:                │
                                 │  • Cortex Analyst (SV) │
                                 │  • RECOMMEND_SCHEDULE  │
                                 └────────────────────────┘
```

## What's in the data

- **10 salon businesses** across San Francisco, LA, New York, Chicago, Austin, Seattle, Miami, Denver, Boston, Nashville
- **250 clients** with varying visit frequencies (21-90 day cycles), 30% flagged as at-risk for churn
- **5 service categories**: Hair, Nails, Skin, Massage, Waxing
- **20 providers** with different skill sets and weekly availability schedules
- **Realistic patterns**: weekday/weekend volume, seasonal trends, cancellation/no-show rates (~10%)
