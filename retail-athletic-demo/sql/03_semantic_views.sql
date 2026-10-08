-- =============================================================================
-- Retail Athletic Demo — Step 3: Semantic views for Cortex Analyst
-- Run AFTER 02_load_data.sql.
-- =============================================================================

USE SCHEMA RETAIL_ATHLETIC_DEMO.PUBLIC;

-- ----------------------------------------------- Customer interactions view
CREATE OR REPLACE SEMANTIC VIEW RETAIL_ATHLETIC_DEMO.PUBLIC.CUSTOMER_INTERACTIONS_SV

  TABLES (
    customers AS RETAIL_ATHLETIC_DEMO.PUBLIC.DIM_CUSTOMER
      PRIMARY KEY (CUSTOMER_ID)
      COMMENT = 'Customer dimension with demographics, segmentation, and lifetime value',
    interactions AS RETAIL_ATHLETIC_DEMO.PUBLIC.FACT_CUSTOMER_INTERACTIONS
      PRIMARY KEY (INTERACTION_ID)
      COMMENT = 'Customer interaction events across channels',
    products AS RETAIL_ATHLETIC_DEMO.PUBLIC.DIM_PRODUCT
      PRIMARY KEY (PRODUCT_ID)
      COMMENT = 'Product catalog with lines, categories, materials, and pricing',
    ml_features AS RETAIL_ATHLETIC_DEMO.PUBLIC.ML_CUSTOMER_FEATURES
      PRIMARY KEY (CUSTOMER_ID)
      COMMENT = 'ML-generated customer features including churn and CLV predictions',
    campaigns AS RETAIL_ATHLETIC_DEMO.PUBLIC.DIM_MARKETING_CAMPAIGN
      PRIMARY KEY (CAMPAIGN_ID)
      COMMENT = 'Marketing campaigns',
    campaign_perf AS RETAIL_ATHLETIC_DEMO.PUBLIC.FACT_CAMPAIGN_PERFORMANCE
      PRIMARY KEY (PERF_ID)
      COMMENT = 'Daily campaign performance metrics'
  )

  RELATIONSHIPS (
    interaction_to_customer AS interactions(CUSTOMER_ID) REFERENCES customers,
    interaction_to_product AS interactions(PRODUCT_ID) REFERENCES products,
    ml_to_customer AS ml_features(CUSTOMER_ID) REFERENCES customers,
    perf_to_campaign AS campaign_perf(CAMPAIGN_ID) REFERENCES campaigns
  )

  FACTS (
    interactions.page_views AS interactions.PAGE_VIEWS,
    interactions.session_duration_sec AS interactions.SESSION_DURATION_SEC,
    interactions.rating AS interactions.RATING,
    interactions.sentiment_score AS interactions.SENTIMENT_SCORE COMMENT = 'Sentiment score from review text (-1 to 1)',
    customers.lifetime_value AS customers.LIFETIME_VALUE COMMENT = 'Customer lifetime value in dollars',
    customers.nps_score AS customers.NPS_SCORE COMMENT = 'Net Promoter Score 0-10',
    customers.churn_risk_score AS customers.CHURN_RISK_SCORE,
    ml_features.churn_probability AS ml_features.CHURN_PROBABILITY,
    ml_features.clv_predicted_12m AS ml_features.CLV_PREDICTED_12M,
    ml_features.purchase_frequency AS ml_features.PURCHASE_FREQUENCY,
    ml_features.f_avg_order_value AS ml_features.AVG_ORDER_VALUE,
    ml_features.total_spend_12m AS ml_features.TOTAL_SPEND_12M,
    campaign_perf.impressions AS campaign_perf.IMPRESSIONS,
    campaign_perf.clicks AS campaign_perf.CLICKS,
    campaign_perf.conversions AS campaign_perf.CONVERSIONS,
    campaign_perf.revenue_attributed AS campaign_perf.REVENUE_ATTRIBUTED,
    campaign_perf.campaign_cost AS campaign_perf.COST
  )

  DIMENSIONS (
    customers.customer_name AS CONCAT(customers.FIRST_NAME, ' ', customers.LAST_NAME) WITH SYNONYMS = ('customer name', 'shopper') COMMENT = 'Full name of the customer',
    customers.customer_city AS customers.CITY,
    customers.customer_state AS customers.STATE,
    customers.customer_region AS customers.REGION SAMPLE_VALUES ('West', 'East', 'South', 'Midwest', 'International') IS_ENUM,
    customers.customer_segment AS customers.SEGMENT WITH SYNONYMS = ('segment', 'customer type') COMMENT = 'Customer loyalty segment' SAMPLE_VALUES ('Loyal VIP', 'Active Regular', 'New Customer', 'Lapsed', 'High-Value At-Risk', 'Win-Back Target', 'Browser') IS_ENUM,
    customers.preferred_channel AS customers.PREFERRED_CHANNEL SAMPLE_VALUES ('DTC Website', 'Retail Store', 'Wholesale', 'International DTC') IS_ENUM,
    interactions.interaction_date AS interactions.INTERACTION_DATE COMMENT = 'Date and time of the interaction',
    interactions.interaction_type AS interactions.INTERACTION_TYPE SAMPLE_VALUES ('Page View', 'Search', 'Add to Cart', 'Purchase', 'Return', 'Review', 'Email Click', 'SMS Click', 'Store Visit') IS_ENUM,
    interactions.interaction_channel AS interactions.CHANNEL SAMPLE_VALUES ('DTC Website', 'Retail Store', 'International DTC') IS_ENUM,
    interactions.device_type AS interactions.DEVICE_TYPE SAMPLE_VALUES ('Mobile', 'Desktop', 'Tablet', 'In-Store') IS_ENUM,
    interactions.referral_source AS interactions.REFERRAL_SOURCE SAMPLE_VALUES ('Organic Search', 'Paid Search', 'Social Media', 'Email', 'Direct', 'Referral', 'Influencer') IS_ENUM,
    products.product_name AS products.PRODUCT_NAME,
    products.product_line AS products.PRODUCT_LINE SAMPLE_VALUES ('Performance', 'Everyday', 'Sunday', 'Banks', 'Ponto', 'Clementine', 'Riviera', 'Halo', 'DreamKnit', 'BlueLine') IS_ENUM,
    products.product_category AS products.CATEGORY,
    products.product_material AS products.MATERIAL,
    ml_features.predicted_segment AS ml_features.SEGMENT_PREDICTED,
    campaigns.campaign_name_dim AS campaigns.CAMPAIGN_NAME,
    campaigns.campaign_type AS campaigns.CAMPAIGN_TYPE SAMPLE_VALUES ('Email Blast', 'Social Ads', 'Influencer', 'Retargeting', 'Loyalty Program', 'Seasonal Sale', 'New Launch', 'Brand Awareness') IS_ENUM,
    campaigns.campaign_status AS campaigns.STATUS SAMPLE_VALUES ('Active', 'Completed') IS_ENUM
  )

  METRICS (
    interactions.total_interactions AS COUNT(interactions.INTERACTION_ID) COMMENT = 'Total customer interactions',
    interactions.unique_customers AS COUNT(DISTINCT interactions.CUSTOMER_ID) COMMENT = 'Unique interacting customers',
    interactions.avg_page_views AS AVG(interactions.page_views) COMMENT = 'Average page views per interaction',
    interactions.avg_session_duration AS AVG(interactions.session_duration_sec) COMMENT = 'Average session duration in seconds',
    interactions.avg_sentiment AS AVG(interactions.sentiment_score) COMMENT = 'Average sentiment score',
    interactions.avg_rating AS AVG(interactions.rating) COMMENT = 'Average product rating',
    interactions.purchase_count AS COUNT_IF(interactions.PURCHASED) COMMENT = 'Number of purchases',
    interactions.return_count AS COUNT_IF(interactions.RETURNED) COMMENT = 'Number of returns',
    interactions.cart_add_count AS COUNT_IF(interactions.ADDED_TO_CART) COMMENT = 'Number of add-to-cart events',
    customers.avg_lifetime_value AS AVG(customers.lifetime_value) COMMENT = 'Average customer lifetime value',
    customers.avg_nps AS AVG(customers.nps_score) COMMENT = 'Average NPS',
    ml_features.avg_churn_probability AS AVG(ml_features.churn_probability) COMMENT = 'Average ML churn probability',
    ml_features.avg_predicted_clv AS AVG(ml_features.clv_predicted_12m) COMMENT = 'Average predicted 12-month CLV',
    campaign_perf.total_campaign_revenue AS SUM(campaign_perf.revenue_attributed) COMMENT = 'Total campaign-attributed revenue',
    campaign_perf.total_campaign_cost AS SUM(campaign_perf.campaign_cost) COMMENT = 'Total campaign spend',
    campaign_perf.campaign_roas AS DIV0(SUM(campaign_perf.revenue_attributed), SUM(campaign_perf.campaign_cost)) COMMENT = 'Return on ad spend'
  )

  COMMENT = 'Customer interaction analytics: engagement, segmentation, campaigns, ML churn and CLV predictions.';


-- ------------------------------------------------- Executive KPI / BI view
CREATE OR REPLACE SEMANTIC VIEW RETAIL_ATHLETIC_DEMO.PUBLIC.CONVERSATIONAL_BI_SV

  TABLES (
    daily_kpi AS RETAIL_ATHLETIC_DEMO.PUBLIC.FACT_DAILY_KPI
      COMMENT = 'Daily KPI metrics by channel and region',
    sales AS RETAIL_ATHLETIC_DEMO.PUBLIC.FACT_DAILY_SALES
      PRIMARY KEY (SALE_ID)
      COMMENT = 'Individual sales transactions',
    products AS RETAIL_ATHLETIC_DEMO.PUBLIC.DIM_PRODUCT
      PRIMARY KEY (PRODUCT_ID)
      COMMENT = 'Product catalog',
    stores AS RETAIL_ATHLETIC_DEMO.PUBLIC.DIM_STORE
      PRIMARY KEY (STORE_ID)
      COMMENT = 'Store locations'
  )

  RELATIONSHIPS (
    sale_to_product AS sales(PRODUCT_ID) REFERENCES products,
    sale_to_store AS sales(STORE_ID) REFERENCES stores
  )

  FACTS (
    sales.quantity AS sales.QUANTITY,
    sales.unit_price AS sales.UNIT_PRICE,
    sales.discount_pct AS sales.DISCOUNT_PCT,
    sales.gross_revenue AS sales.GROSS_REVENUE,
    sales.net_revenue AS sales.NET_REVENUE,
    sales.cost_of_goods AS sales.COST_OF_GOODS,
    daily_kpi.kpi_gross_revenue AS daily_kpi.GROSS_REVENUE,
    daily_kpi.kpi_net_revenue AS daily_kpi.NET_REVENUE,
    daily_kpi.kpi_orders AS daily_kpi.ORDERS,
    daily_kpi.kpi_units_sold AS daily_kpi.UNITS_SOLD,
    daily_kpi.kpi_aov AS daily_kpi.AVG_ORDER_VALUE,
    daily_kpi.kpi_return_rate AS daily_kpi.RETURN_RATE,
    daily_kpi.kpi_conversion_rate AS daily_kpi.CONVERSION_RATE,
    daily_kpi.kpi_new_customers AS daily_kpi.NEW_CUSTOMERS,
    daily_kpi.kpi_repeat_customers AS daily_kpi.REPEAT_CUSTOMERS,
    daily_kpi.kpi_gross_margin_pct AS daily_kpi.GROSS_MARGIN_PCT,
    daily_kpi.kpi_cogs AS daily_kpi.COGS,
    daily_kpi.kpi_marketing_spend AS daily_kpi.MARKETING_SPEND,
    daily_kpi.kpi_cac AS daily_kpi.CAC,
    daily_kpi.kpi_ltv_cac_ratio AS daily_kpi.LTV_TO_CAC_RATIO,
    products.unit_cost AS products.UNIT_COST,
    products.msrp AS products.MSRP
  )

  DIMENSIONS (
    daily_kpi.kpi_date AS daily_kpi.KPI_DATE COMMENT = 'KPI date',
    daily_kpi.kpi_channel AS daily_kpi.CHANNEL SAMPLE_VALUES ('DTC Website', 'Retail Store', 'Wholesale', 'International DTC') IS_ENUM,
    daily_kpi.kpi_region AS daily_kpi.REGION SAMPLE_VALUES ('West', 'East', 'South', 'Midwest', 'International') IS_ENUM,
    sales.sale_date AS sales.SALE_DATE COMMENT = 'Sale date',
    sales.sale_channel AS sales.CHANNEL SAMPLE_VALUES ('DTC Website', 'Retail Store', 'Wholesale', 'International DTC') IS_ENUM,
    products.product_name AS products.PRODUCT_NAME,
    products.product_line AS products.PRODUCT_LINE WITH SYNONYMS = ('collection', 'line') SAMPLE_VALUES ('Performance', 'Everyday', 'Sunday', 'Banks', 'Ponto', 'Clementine', 'Riviera', 'Halo', 'DreamKnit', 'BlueLine') IS_ENUM,
    products.product_category AS products.CATEGORY,
    products.product_subcategory AS products.SUBCATEGORY,
    products.product_material AS products.MATERIAL,
    products.product_color AS products.COLOR,
    products.product_season AS products.SEASON,
    products.lifecycle_stage AS products.LIFECYCLE_STAGE SAMPLE_VALUES ('Concept', 'Design', 'Sampling', 'Tech Pack Review', 'Pre-Production', 'Production', 'In Market', 'Markdown', 'Retired') IS_ENUM,
    products.is_sustainable AS products.IS_SUSTAINABLE,
    stores.store_name AS stores.STORE_NAME,
    stores.store_city AS stores.CITY,
    stores.store_state AS stores.STATE,
    stores.store_region AS stores.REGION SAMPLE_VALUES ('West', 'East', 'South', 'Midwest', 'International') IS_ENUM,
    stores.store_channel AS stores.CHANNEL
  )

  METRICS (
    sales.total_gross_revenue AS SUM(sales.gross_revenue) WITH SYNONYMS = ('total revenue', 'gross sales') COMMENT = 'Total gross revenue',
    sales.total_net_revenue AS SUM(sales.net_revenue) WITH SYNONYMS = ('net sales') COMMENT = 'Total net revenue after discounts',
    sales.total_orders AS COUNT(sales.SALE_ID) COMMENT = 'Total orders',
    sales.total_units_sold AS SUM(sales.quantity) COMMENT = 'Total units sold',
    sales.avg_order_value AS DIV0(SUM(sales.net_revenue), COUNT(sales.SALE_ID)) WITH SYNONYMS = ('AOV') COMMENT = 'Average order value',
    sales.total_cogs AS SUM(sales.cost_of_goods) COMMENT = 'Total cost of goods sold',
    sales.gross_margin AS DIV0(SUM(sales.net_revenue) - SUM(sales.cost_of_goods), SUM(sales.net_revenue)) COMMENT = 'Gross margin percentage',
    sales.avg_discount AS AVG(sales.discount_pct) COMMENT = 'Average discount percentage',
    sales.return_rate AS DIV0(COUNT_IF(sales.RETURN_FLAG), COUNT(sales.SALE_ID)) COMMENT = 'Return rate',
    sales.unique_customers AS COUNT(DISTINCT sales.CUSTOMER_ID) COMMENT = 'Unique customers',
    daily_kpi.total_kpi_gross_revenue AS SUM(daily_kpi.kpi_gross_revenue) COMMENT = 'KPI total gross revenue',
    daily_kpi.total_kpi_net_revenue AS SUM(daily_kpi.kpi_net_revenue) COMMENT = 'KPI total net revenue',
    daily_kpi.total_kpi_orders AS SUM(daily_kpi.kpi_orders) COMMENT = 'KPI total orders',
    daily_kpi.total_new_customers AS SUM(daily_kpi.kpi_new_customers) COMMENT = 'Total new customers',
    daily_kpi.total_repeat_customers AS SUM(daily_kpi.kpi_repeat_customers) COMMENT = 'Total repeat customers',
    daily_kpi.avg_gross_margin AS AVG(daily_kpi.kpi_gross_margin_pct) COMMENT = 'Average gross margin',
    daily_kpi.avg_conversion_rate AS AVG(daily_kpi.kpi_conversion_rate) COMMENT = 'Average conversion rate',
    daily_kpi.total_marketing_spend AS SUM(daily_kpi.kpi_marketing_spend) COMMENT = 'Total marketing spend',
    daily_kpi.avg_cac AS AVG(daily_kpi.kpi_cac) COMMENT = 'Average customer acquisition cost',
    daily_kpi.avg_ltv_cac_ratio AS AVG(daily_kpi.kpi_ltv_cac_ratio) COMMENT = 'Average LTV to CAC ratio'
  )

  COMMENT = 'Executive conversational BI: daily revenue KPIs, channel and region performance, product line analytics, store metrics, and marketing efficiency.'

  AI_SQL_GENERATION 'When calculating revenue metrics, use NET_REVENUE as the default unless the user specifically asks for gross. Round monetary values to 2 decimal places. When asked about trends, show data by month unless specified otherwise. Use FACT_DAILY_KPI for high-level KPI questions and FACT_DAILY_SALES for transaction-level analysis.'

  AI_QUESTION_CATEGORIZATION 'This view covers retail business analytics: revenue, orders, margins, marketing efficiency, and store performance. For customer churn, lifetime value, or ML predictions, direct users to the Customer Interactions semantic view.';
