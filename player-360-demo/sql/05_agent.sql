-- =============================================================================
-- Player 360 Demo — Step 5: Cortex Agent
-- Run AFTER 04_semantic_view.sql.
-- Requires Cortex cross-region inference if 'auto' models aren't available
-- in your region:  ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
-- =============================================================================

USE SCHEMA PLAYER_360.APP;

CREATE OR REPLACE AGENT PLAYER_360_AGENT
  FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: >
    Format responses clearly with tables when showing data.
    Highlight key takeaways.
    When showing metrics, include context like time periods or player segments when relevant.
  orchestration: >
    You are a Player 360 analytics assistant for game analysts and product managers.
    You help answer questions about player behavior, engagement, monetization, retention,
    and in-game performance. When presenting data, be concise and highlight key insights.
    Use appropriate aggregations and filters based on the question context.
    For revenue questions, exclude records where purchase_type is none
    (those are ad views without purchases).
    For retention rates, express as percentages.

tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: player_analytics
      description: >
        Query player 360 data including player profiles, game sessions,
        in-game purchases, match performance (kills, damage, assists),
        player retention and churn, player rankings, daily active users,
        demographics, and ad engagement metrics. Use this tool for any question
        about players, revenue, engagement, retention, monetization,
        game performance, or user behavior.

tool_resources:
  player_analytics:
    semantic_view: PLAYER_360.APP.PLAYER_360_SEMANTIC_VIEW
    execution_environment:
      type: warehouse
      warehouse: COMPUTE_WH
      query_timeout: 299
$$;

-- Uncomment to grant access to other roles:
-- GRANT USAGE ON AGENT PLAYER_360.APP.PLAYER_360_AGENT TO ROLE <role_name>;
-- GRANT USAGE ON SEMANTIC VIEW PLAYER_360.APP.PLAYER_360_SEMANTIC_VIEW TO ROLE <role_name>;
-- GRANT SELECT ON ALL TABLES IN SCHEMA PLAYER_360.RAW TO ROLE <role_name>;
-- GRANT SELECT ON ALL TABLES IN SCHEMA PLAYER_360.ANALYTIC TO ROLE <role_name>;
-- GRANT SELECT ON ALL DYNAMIC TABLES IN SCHEMA PLAYER_360.ANALYTIC TO ROLE <role_name>;
