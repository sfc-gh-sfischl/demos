# Retail Athletic Demo — Snowflake Conversational BI + ML

A self-contained demo for a specialty athletic apparel retailer:

- **Synthetic data**: 13 tables, ~140K rows, Oct 2024 to Sep 2025
- **Two semantic views** for Cortex Analyst
- A **Cortex Agent** (`RETAIL_ANALYTICS_AGENT`) for conversational BI in Snowflake CoWork
- An **ML notebook** that trains a churn model, logs it to the Model Registry, runs batch inference in-warehouse, and attaches a Model Monitor

All objects are created in `RETAIL_ATHLETIC_DEMO.PUBLIC`.

## Contents

```
sql/01_setup_and_tables.sql   database, schema, 13 empty tables
sql/02_load_data.sql          synthetic data (deterministic, re-runnable, ~1-2 min on XS)
sql/03_semantic_views.sql     CUSTOMER_INTERACTIONS_SV, CONVERSATIONAL_BI_SV
sql/04_agent.sql              RETAIL_ANALYTICS_AGENT (+ optional grants for other roles)
notebooks/churn_prediction.ipynb   train -> registry -> batch inference -> monitor
```

## Prerequisites

- A role that can create a database, semantic views, agents, models and model monitors. `ACCOUNTADMIN` or `SYSADMIN` is simplest for a demo account.
- A warehouse. The scripts use **`COMPUTE_WH`**; find/replace it in all files if yours has a different name.
- Cortex Agents and CoWork available in the account. If agent creation fails because no model is available in your region, an ACCOUNTADMIN can run:
  `ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';`
- For the notebook, either:
  - a **Snowflake Notebook** (upload the .ipynb; add `xgboost` and `snowflake-ml-python` packages), or
  - local Python 3.10/3.11: `pip install "snowflake-ml-python>=1.7.1" xgboost scikit-learn pandas`, and set `CONNECTION_NAME` in the first cell to a connection in `~/.snowflake/connections.toml`.

## Run order

1. Open a Snowsight SQL worksheet and run each script top to bottom, **in order**: `01`, then `02`, `03`, `04`.
   Or from a terminal with Snowflake CLI: `snow sql -f sql/01_setup_and_tables.sql -c <connection>` (repeat for each file).
2. The last statement of `02` prints row counts. Expect roughly:

   | Table | Rows |
   |---|---|
   | DIM_PRODUCT / DIM_STORE / DIM_CUSTOMER | 500 / 25 / 5,000 |
   | FACT_DAILY_SALES | ~40-60K |
   | FACT_CUSTOMER_INTERACTIONS | 20,000 |
   | FACT_INVENTORY_SNAPSHOT | 49,920 |
   | FACT_DEMAND_FORECAST | 7,200 |
   | FACT_DAILY_KPI | ~7K |
   | ML_CUSTOMER_FEATURES | 5,000 |
   | DIM_MARKETING_CAMPAIGN / FACT_CAMPAIGN_PERFORMANCE | 40 / ~1.2K |
   | ASSORTMENT_PLAN / PRODUCT_DEVELOPMENT_PIPELINE | 200 / 80 |

3. Open **Snowsight → AI & ML → Snowflake CoWork (Intelligence)** and select **Retail Analytics Assistant**.
   If other users or roles will use it, uncomment the grant block at the bottom of `04_agent.sql`.
4. Run `notebooks/churn_prediction.ipynb` top to bottom. It is safe to re-run: it replaces the model and the monitor.

## What's in the data

The data has deliberate patterns so the demo questions return interesting answers:

- **Sales seasonality**: weekend lift, a Black Friday / holiday peak, a summer bump, a Jan-Feb dip, and ~25% year-over-year growth across the window. Best-seller products are skewed. Markdown items and the holiday sale carry deeper discounts. Wholesale sells at wholesale price. DTC has higher return rates.
- **Consistent numbers**: `FACT_DAILY_KPI` is rolled up from `FACT_DAILY_SALES`, so KPI and transaction totals reconcile. Net revenue never exceeds gross, MSRP is set from unit cost, and campaign ROAS follows from cost, impressions, clicks, conversions and revenue.
- **Churn signal**: a customer's churn risk depends on recency, purchase frequency, email engagement, web visits, return rate and NPS, plus noise. The ML model has something real to learn and should beat the legacy `CHURN_PROBABILITY` score, which the notebook prints for comparison. Lapsed customers stop appearing in sales after their last purchase date.
- **Product reviews**: each product has a quality score, so ratings, review text and sentiment agree with each other and differ between products.
- **Planning stories**: forecast model `v1.0` (Oct-Mar) has about twice the error of `v2.1` (Apr-Sep). The assortment plan has closed seasons with actuals, an in-season plan (Fall 2025) and a future plan (Holiday 2025). Inventory stockouts rise in November and December.

## Demo script (CoWork)

1. "What is our total net revenue by channel?"
2. "Show me the monthly revenue trend by region."
3. "Which customer segments have the highest churn risk?"
4. "What is our marketing ROAS by campaign type?"
5. "Which product lines have the best average rating, and what are customers saying about the worst one?"

## Objects created

| Type | Name |
|---|---|
| Tables | 13 tables listed above, plus `CHURN_PREDICTIONS`, `CHURN_MONITOR_SOURCE` and `CHURN_MONITOR_BASELINE` from the notebook |
| View | `CHURN_FEATURES_V` (notebook) |
| Semantic views | `CUSTOMER_INTERACTIONS_SV`, `CONVERSATIONAL_BI_SV` |
| Agent | `RETAIL_ANALYTICS_AGENT` |
| Model | `CHURN_PREDICTION_MODEL` version `V1` |
| Model monitor | `CHURN_MODEL_MONITOR` |

## Teardown

```sql
DROP DATABASE RETAIL_ATHLETIC_DEMO;   -- removes everything above
```
