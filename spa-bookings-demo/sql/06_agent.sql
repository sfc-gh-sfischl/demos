-- =============================================================================
-- Spa Bookings Demo — Step 6: Cortex Agent
-- Run AFTER 03_semantic_view.sql and 04_stored_procedure.sql.
-- Requires Cortex cross-region inference if 'auto' models aren't available
-- in your region:  ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
-- =============================================================================

USE SCHEMA SPABOOKINGS.PUBLIC;

CREATE OR REPLACE AGENT SCHEDULING_AGENT
  COMMENT = 'AI scheduling assistant for salon managers'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

instructions:
  response: >
    You are a scheduling assistant for salon and spa locations.
    Help managers understand staffing needs, view demand forecasts, and generate optimized schedules.
    When presenting data, use clear tables and summaries.
    Always specify the location and service category when discussing staffing.
  orchestration: >
    For questions about historical appointment data, trends, provider info, or forecasted demand,
    use the scheduling_analyst tool.
    For questions about specific staffing recommendations or schedule optimization for a date range,
    use the recommend_schedule tool with START_DATE and END_DATE in YYYY-MM-DD format.
  sample_questions:
    - question: "What is the forecasted demand for next week across all locations?"
    - question: "What's the forecasted demand for next week in Denver?"
    - question: "Are we understaffed anywhere next week?"
    - question: "Which providers are available on Saturdays?"

tools:
  - tool_spec:
      type: cortex_analyst_text_to_sql
      name: scheduling_analyst
      description: >
        Query historical appointment data, provider skills and availability,
        demand forecasts, and daily appointment volume.
        Use for questions about trends, provider info, forecasts, and historical patterns.
  - tool_spec:
      type: generic
      name: recommend_schedule
      description: >
        Generate staffing recommendations for a date range.
        Returns forecasted demand, available providers, recommended staff count,
        and staffing status (Understaffed/Adequate/Overstaffed).
        Requires START_DATE and END_DATE as strings in YYYY-MM-DD format.
      input_schema:
        type: object
        properties:
          START_DATE:
            description: "Start date in YYYY-MM-DD format, e.g. 2026-04-09"
            type: string
          END_DATE:
            description: "End date in YYYY-MM-DD format, e.g. 2026-04-16"
            type: string
        required:
          - START_DATE
          - END_DATE

tool_resources:
  scheduling_analyst:
    semantic_view: SPABOOKINGS.PUBLIC.SCHEDULING_SEMANTIC_VIEW
  recommend_schedule:
    type: function
    identifier: SPABOOKINGS.PUBLIC.RECOMMEND_SCHEDULE
    execution_environment:
      type: warehouse
      warehouse: COMPUTE_WH
$$;

-- Uncomment the following to grant access to other roles:
-- GRANT USAGE ON AGENT SPABOOKINGS.PUBLIC.SCHEDULING_AGENT TO ROLE <role_name>;
-- GRANT USAGE ON SEMANTIC VIEW SPABOOKINGS.PUBLIC.SCHEDULING_SEMANTIC_VIEW TO ROLE <role_name>;
-- GRANT SELECT ON ALL TABLES IN SCHEMA SPABOOKINGS.PUBLIC TO ROLE <role_name>;
