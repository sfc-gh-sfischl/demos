import os
import warnings
import pickle
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from snowpark_session import create_snowpark_session
from snowflake.snowpark.functions import col
from snowflake.ml.registry import Registry
from snowflake.ml.model.task import Task
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score,
    f1_score, roc_auc_score, classification_report
)
from sklearn.ensemble import GradientBoostingClassifier

warnings.filterwarnings("ignore")

REFERENCE_DATE = pd.Timestamp("2026-04-08")
REBOOK_WINDOW_DAYS = 30
MODEL_NAME = "REBOOKING_RISK"
VERSION_NAME = "V1"
DATABASE = "SPABOOKINGS"
SCHEMA = "PUBLIC"
PREDICTIONS_TABLE = "CLIENT_REBOOKING_PREDICTIONS"
MONITOR_NAME = "REBOOKING_RISK_MONITOR"
WAREHOUSE = "AIWH"

print("=" * 60)
print("Spa Bookings — Client Rebooking Risk Prediction Pipeline")
print("=" * 60)

print("\n[1/7] Connecting to Snowflake...")
session = create_snowpark_session()
session.use_database(DATABASE)
session.use_schema(SCHEMA)
print(f"  Connected: {DATABASE}.{SCHEMA}")

print("\n[2/7] Loading data...")
appointments_df = session.table("APPOINTMENTS").to_pandas()
orderlines_df = session.table("ORDERLINES").to_pandas()
print(f"  Appointments: {len(appointments_df)} rows")
print(f"  OrderLines:   {len(orderlines_df)} rows")

print("\n[3/7] Engineering features per client...")

appointments_df["APPOINTMENT_DATE"] = pd.to_datetime(appointments_df["APPOINTMENT_DATE"])
orderlines_df["SERVICE_DATE"] = pd.to_datetime(orderlines_df["SERVICE_DATE"])

completed_appts = appointments_df[appointments_df["APPOINTMENT_STATUS"] == "completed"].copy()

client_features = []
for client_id, grp in appointments_df.groupby("CLIENT_ID"):
    completed = grp[grp["APPOINTMENT_STATUS"] == "completed"]
    cancelled = grp[grp["APPOINTMENT_STATUS"] == "cancelled"]
    no_showed = grp[grp["APPOINTMENT_STATUS"] == "no_show"]

    if len(completed) == 0:
        continue

    last_visit = completed["APPOINTMENT_DATE"].max()
    first_visit = completed["APPOINTMENT_DATE"].min()
    days_since_last_visit = (REFERENCE_DATE - last_visit).days
    tenure_days = (REFERENCE_DATE - first_visit).days

    total_appts = len(grp)
    completed_count = len(completed)
    cancelled_count = len(cancelled)
    no_show_count = len(no_showed)
    no_show_rate = no_show_count / total_appts if total_appts > 0 else 0
    cancellation_rate = cancelled_count / total_appts if total_appts > 0 else 0

    if len(completed) >= 2:
        dates_sorted = completed["APPOINTMENT_DATE"].sort_values()
        gaps = dates_sorted.diff().dropna().dt.days
        avg_days_between_visits = gaps.mean()
    else:
        avg_days_between_visits = 0

    avg_duration = completed["SERVICE_DURATION_MINS"].mean()
    avg_days_booked_advance = grp["DAYS_BOOKED_IN_ADVANCE"].mean()

    booking_sources = grp["BOOKING_SOURCE"].value_counts()
    top_booking_source = booking_sources.index[0] if len(booking_sources) > 0 else "unknown"
    app_booking_pct = booking_sources.get("app", 0) / total_appts if total_appts > 0 else 0

    service_categories = grp["SERVICE_CATEGORY"].nunique()

    client_orders = orderlines_df[orderlines_df["CLIENT_ID"] == client_id]
    if len(client_orders) > 0:
        total_spend = client_orders["LINE_TOTAL"].sum()
        avg_order_value = client_orders["LINE_TOTAL"].mean()
        avg_tip = client_orders["TIP_AMOUNT"].mean()
        avg_discount = client_orders["DISCOUNT_AMOUNT"].mean()
        tip_rate = client_orders["TIP_AMOUNT"].sum() / total_spend if total_spend > 0 else 0

        orders_sorted = client_orders.sort_values("SERVICE_DATE")
        if len(orders_sorted) >= 4:
            half = len(orders_sorted) // 2
            first_half_avg = orders_sorted.iloc[:half]["LINE_TOTAL"].mean()
            second_half_avg = orders_sorted.iloc[half:]["LINE_TOTAL"].mean()
            spend_trend = (second_half_avg - first_half_avg) / first_half_avg if first_half_avg > 0 else 0
        else:
            spend_trend = 0
    else:
        total_spend = avg_order_value = avg_tip = avg_discount = tip_rate = spend_trend = 0

    is_at_risk = 1 if days_since_last_visit > REBOOK_WINDOW_DAYS else 0

    client_features.append({
        "CLIENT_ID": client_id,
        "DAYS_SINCE_LAST_VISIT": days_since_last_visit,
        "TENURE_DAYS": tenure_days,
        "TOTAL_APPOINTMENTS": total_appts,
        "COMPLETED_COUNT": completed_count,
        "NO_SHOW_RATE": round(no_show_rate, 4),
        "CANCELLATION_RATE": round(cancellation_rate, 4),
        "AVG_DAYS_BETWEEN_VISITS": round(avg_days_between_visits, 2),
        "AVG_DURATION_MINS": round(avg_duration, 2),
        "AVG_DAYS_BOOKED_ADVANCE": round(avg_days_booked_advance, 2),
        "APP_BOOKING_PCT": round(app_booking_pct, 4),
        "SERVICE_CATEGORIES": service_categories,
        "TOTAL_SPEND": round(total_spend, 2),
        "AVG_ORDER_VALUE": round(avg_order_value, 2),
        "AVG_TIP": round(avg_tip, 2),
        "TIP_RATE": round(tip_rate, 4),
        "SPEND_TREND": round(spend_trend, 4),
        "AT_RISK": is_at_risk,
    })

features_df = pd.DataFrame(client_features)
print(f"  Clients with features: {len(features_df)}")
print(f"  At-risk clients: {features_df['AT_RISK'].sum()} ({features_df['AT_RISK'].mean()*100:.1f}%)")
print(f"  Not at-risk:     {(features_df['AT_RISK']==0).sum()} ({(1-features_df['AT_RISK'].mean())*100:.1f}%)")

FEATURE_COLS = [
    "DAYS_SINCE_LAST_VISIT", "TENURE_DAYS", "TOTAL_APPOINTMENTS",
    "COMPLETED_COUNT", "NO_SHOW_RATE", "CANCELLATION_RATE",
    "AVG_DAYS_BETWEEN_VISITS", "AVG_DURATION_MINS", "AVG_DAYS_BOOKED_ADVANCE",
    "APP_BOOKING_PCT", "SERVICE_CATEGORIES", "TOTAL_SPEND",
    "AVG_ORDER_VALUE", "AVG_TIP", "TIP_RATE", "SPEND_TREND",
]

print("\n[4/7] Training GradientBoosting classifier...")
X = features_df[FEATURE_COLS]
y = features_df["AT_RISK"]

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

model = GradientBoostingClassifier(
    n_estimators=200,
    max_depth=5,
    learning_rate=0.1,
    subsample=0.8,
    random_state=42,
)
model.fit(X_train, y_train)

y_pred = model.predict(X_test)
y_prob = model.predict_proba(X_test)[:, 1]

accuracy = accuracy_score(y_test, y_pred)
precision = precision_score(y_test, y_pred)
recall = recall_score(y_test, y_pred)
f1 = f1_score(y_test, y_pred)
auc = roc_auc_score(y_test, y_prob)

print(f"\n  === Model Evaluation (Holdout) ===")
print(f"  Accuracy:  {accuracy:.4f}")
print(f"  Precision: {precision:.4f}")
print(f"  Recall:    {recall:.4f}")
print(f"  F1 Score:  {f1:.4f}")
print(f"  AUC-ROC:   {auc:.4f}")
print(f"\n  {classification_report(y_test, y_pred, target_names=['Not At Risk', 'At Risk'])}")

importances = pd.Series(model.feature_importances_, index=FEATURE_COLS).sort_values(ascending=False)
print("  Top 5 Feature Importances:")
for feat, imp in importances.head(5).items():
    print(f"    {feat}: {imp:.4f}")

model_path = "/Users/sfischl/.snowflake/cortex/playground/workspace/rebooking_model.pkl"
with open(model_path, "wb") as f:
    pickle.dump(model, f)
print(f"\n  Model saved to: {model_path}")

print("\n[5/7] Registering model in Snowflake Model Registry...")
reg = Registry(session=session, database_name=DATABASE, schema_name=SCHEMA)

sample_input = X_train.head(5)

mv = reg.log_model(
    model,
    model_name=MODEL_NAME,
    version_name=VERSION_NAME,
    sample_input_data=sample_input,
    conda_dependencies=["scikit-learn"],
    target_platforms=["SNOWPARK_CONTAINER_SERVICES"],
    comment="Spa Bookings — Client Rebooking Risk Prediction - GradientBoosting binary classifier predicting if a salon client will not rebook within 30 days",
    task=Task.TABULAR_BINARY_CLASSIFICATION,
    metrics={
        "accuracy": accuracy,
        "precision": precision,
        "recall": recall,
        "f1_score": f1,
        "auc_roc": auc,
    },
)
print(f"  Model registered: {MODEL_NAME} version {VERSION_NAME}")
print(f"  Functions: {mv.show_functions()}")

print("\n[6/7] Running batch inference and writing predictions table...")
all_predictions = model.predict(X)
all_probabilities = model.predict_proba(X)[:, 1]

predictions_df = features_df[["CLIENT_ID"] + FEATURE_COLS].copy()
predictions_df["RISK_SCORE"] = np.round(all_probabilities, 4)
predictions_df["PREDICTED_AT_RISK"] = all_predictions
predictions_df["ACTUAL_AT_RISK"] = features_df["AT_RISK"].values
predictions_df["PREDICTION_TIMESTAMP"] = pd.Timestamp.now().strftime("%Y-%m-%d %H:%M:%S")

snowpark_predictions = session.create_dataframe(predictions_df)
snowpark_predictions.write.mode("overwrite").save_as_table(PREDICTIONS_TABLE)

count = session.table(PREDICTIONS_TABLE).count()
print(f"  Predictions written to {DATABASE}.{SCHEMA}.{PREDICTIONS_TABLE}")
print(f"  Total rows: {count}")
print(f"  High-risk clients (score > 0.5): {(all_probabilities > 0.5).sum()}")

print("\n[7/7] Creating Model Monitor...")

alter_ts_sql = f"""
ALTER TABLE {DATABASE}.{SCHEMA}.{PREDICTIONS_TABLE}
ALTER COLUMN PREDICTION_TIMESTAMP SET DATA TYPE TIMESTAMP_NTZ
"""
try:
    session.sql(alter_ts_sql).collect()
except Exception:
    session.sql(f"""
    CREATE OR REPLACE TABLE {DATABASE}.{SCHEMA}.{PREDICTIONS_TABLE}_TMP AS
    SELECT *,
           TO_TIMESTAMP_NTZ(PREDICTION_TIMESTAMP) AS PREDICTION_TS
    FROM {DATABASE}.{SCHEMA}.{PREDICTIONS_TABLE}
    """).collect()
    session.sql(f"DROP TABLE IF EXISTS {DATABASE}.{SCHEMA}.{PREDICTIONS_TABLE}").collect()
    session.sql(f"ALTER TABLE {DATABASE}.{SCHEMA}.{PREDICTIONS_TABLE}_TMP RENAME TO {DATABASE}.{SCHEMA}.{PREDICTIONS_TABLE}").collect()

try:
    session.sql(f"DROP MODEL MONITOR IF EXISTS {MONITOR_NAME}").collect()
except Exception:
    pass

monitor_sql = f"""
CREATE MODEL MONITOR {MONITOR_NAME} WITH
    MODEL = {MODEL_NAME}
    VERSION = '{VERSION_NAME}'
    FUNCTION = 'PREDICT'
    SOURCE = {DATABASE}.{SCHEMA}.{PREDICTIONS_TABLE}
    WAREHOUSE = {WAREHOUSE}
    REFRESH_INTERVAL = '1 day'
    AGGREGATION_WINDOW = '1 day'
    TIMESTAMP_COLUMN = PREDICTION_TS
    PREDICTION_SCORE_COLUMNS = ('RISK_SCORE')
    ACTUAL_SCORE_COLUMNS = ('ACTUAL_AT_RISK')
"""
try:
    session.sql(monitor_sql).collect()
    print(f"  Model Monitor '{MONITOR_NAME}' created successfully!")
    print(f"  Monitoring: drift (PSI), prediction distribution")
    print(f"  Refresh: daily | Aggregation: 1 day")
except Exception as e:
    print(f"  Note: Model Monitor creation returned: {e}")
    print(f"  This may require the model to be deployed on WAREHOUSE target.")
    print(f"  You can manually create via Snowsight: AI&ML -> Models -> {MODEL_NAME} -> Monitors")

print("\n" + "=" * 60)
print("Pipeline Complete!")
print("=" * 60)
print(f"""
Summary:
  Model:       {DATABASE}.{SCHEMA}.{MODEL_NAME} (version {VERSION_NAME})
  Predictions: {DATABASE}.{SCHEMA}.{PREDICTIONS_TABLE}
  Monitor:     {MONITOR_NAME}

  Accuracy:  {accuracy:.4f}  |  F1: {f1:.4f}  |  AUC: {auc:.4f}

  Feature Store: Not used (batch pipeline; Feature Store is for
  online serving with low-latency feature lookups - not needed here)

Next Steps:
  - View model in Snowsight: AI&ML -> Models -> {MODEL_NAME}
  - Query predictions: SELECT * FROM {DATABASE}.{SCHEMA}.{PREDICTIONS_TABLE}
    WHERE PREDICTED_AT_RISK = 1 ORDER BY RISK_SCORE DESC
  - Monitor drift: Snowsight -> AI&ML -> Models -> Monitors
""")

session.close()
