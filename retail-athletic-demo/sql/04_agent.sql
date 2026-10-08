-- =============================================================================
-- Retail Athletic Demo — Step 4: Cortex Agent + access for CoWork
-- Run AFTER 03_semantic_views.sql.
-- If the agent is to be used by a role other than the one that creates it,
-- uncomment and edit the GRANT block at the bottom.
-- Requires Cortex cross-region inference if 'auto' models aren't available
-- in your region:  ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
-- =============================================================================

USE SCHEMA RETAIL_ATHLETIC_DEMO.PUBLIC;

CREATE OR REPLACE AGENT RETAIL_ATHLETIC_DEMO.PUBLIC.RETAIL_ANALYTICS_AGENT
  COMMENT = 'Retail analytics agent for customer interactions, sales KPIs, and conversational BI'
  PROFILE = '{"display_name": "Retail Analytics Assistant"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: >
    You are a retail analytics assistant for a specialty athletic apparel brand.
    You help business users analyze customer interactions, marketing campaign performance,
    sales trends, and key business KPIs. Be conversational but data-driven.
    Always include specific numbers and percentages in your answers.
    When showing revenue, round to 2 decimal places and format with dollar signs.
    When showing trends, default to monthly unless the user specifies otherwise.
    The data covers October 2024 through September 2025.
    If the user asks a vague question, suggest 2-3 specific angles they could explore.
  orchestration: >
    For questions about customer behavior, engagement, segmentation, churn, CLV,
    marketing campaigns, or ML predictions, use the customer_interactions_analyst tool.
    For questions about revenue, sales, orders, product performance, store metrics,
    margins, marketing spend efficiency, or executive KPIs, use the business_kpi_analyst tool.
    If a question spans both domains, use both tools and synthesize the results.
    Always generate a chart when the data supports visualization.
  sample_questions:
    - question: "What are our top product lines by net revenue?"
    - question: "Which customer segments have the highest churn risk?"
    - question: "How does DTC Website compare to Retail Store on revenue and margin?"
    - question: "What is our marketing ROAS by campaign type?"
    - question: "Show me the monthly revenue trend by region"
    - question: "Which referral sources drive the most purchases?"

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "customer_interactions_analyst"
      description: >
        Use this tool for questions about customer behavior and engagement.
        Covers: customer interactions (page views, purchases, returns, reviews),
        customer segmentation (Loyal VIP, Active Regular, New Customer, Lapsed, etc.),
        customer sentiment and NPS scores, ML-predicted churn probability and CLV,
        marketing campaign performance (impressions, clicks, conversions, ROAS),
        product-level conversion rates, and device/channel/referral source analysis.
        Do NOT use for revenue totals, order counts, store performance, or executive KPIs.
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "business_kpi_analyst"
      description: >
        Use this tool for executive business intelligence and financial metrics.
        Covers: daily/weekly/monthly revenue (gross and net), order volume, units sold,
        average order value (AOV), gross margin, cost of goods sold (COGS),
        return rates, conversion rates, marketing spend and CAC, LTV-to-CAC ratio,
        product line performance, store-level analytics, channel comparison
        (DTC Website, Retail Store, Wholesale, International DTC),
        and regional performance (West, East, South, Midwest, International).
        Do NOT use for individual customer behavior, churn predictions, or campaign-level metrics.
  - tool_spec:
      type: "data_to_chart"
      name: "data_to_chart"
      description: "Generates visualizations from structured data returned by analyst tools. Use when the user asks for charts, trends, comparisons, or when data has 3+ rows."

tool_resources:
  customer_interactions_analyst:
    semantic_view: "RETAIL_ATHLETIC_DEMO.PUBLIC.CUSTOMER_INTERACTIONS_SV"
    execution_environment:
      type: "warehouse"
      warehouse: "COMPUTE_WH"
  business_kpi_analyst:
    semantic_view: "RETAIL_ATHLETIC_DEMO.PUBLIC.CONVERSATIONAL_BI_SV"
    execution_environment:
      type: "warehouse"
      warehouse: "COMPUTE_WH"
$$;

DESCRIBE AGENT RETAIL_ATHLETIC_DEMO.PUBLIC.RETAIL_ANALYTICS_AGENT;

-- ------------------------------------------------------------------ access
-- Users chat with the agent in CoWork (Snowsight > AI & ML > CoWork / Snowflake
-- Intelligence). A role needs USAGE on the agent and SELECT on the semantic views.
-- SET demo_role = 'ANALYST';   -- <-- change
-- GRANT USAGE ON DATABASE RETAIL_ATHLETIC_DEMO TO ROLE IDENTIFIER($demo_role);
-- GRANT USAGE ON SCHEMA RETAIL_ATHLETIC_DEMO.PUBLIC TO ROLE IDENTIFIER($demo_role);
-- GRANT SELECT ON ALL SEMANTIC VIEWS IN SCHEMA RETAIL_ATHLETIC_DEMO.PUBLIC TO ROLE IDENTIFIER($demo_role);
-- GRANT SELECT ON ALL TABLES IN SCHEMA RETAIL_ATHLETIC_DEMO.PUBLIC TO ROLE IDENTIFIER($demo_role);
-- GRANT USAGE ON AGENT RETAIL_ATHLETIC_DEMO.PUBLIC.RETAIL_ANALYTICS_AGENT TO ROLE IDENTIFIER($demo_role);
-- GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE IDENTIFIER($demo_role);
