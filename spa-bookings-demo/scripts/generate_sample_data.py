import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import random
import uuid

np.random.seed(42)
random.seed(42)

TODAY = datetime(2026, 4, 7)

BUSINESSES = [
    ("BIZ001", "Luxe Hair Studio", "San Francisco"),
    ("BIZ002", "Bloom Salon & Spa", "Los Angeles"),
    ("BIZ003", "The Glam Room", "New York"),
    ("BIZ004", "Serenity Spa", "Chicago"),
    ("BIZ005", "Revive Beauty Bar", "Austin"),
    ("BIZ006", "Radiance Salon", "Seattle"),
    ("BIZ007", "The Beauty Loft", "Miami"),
    ("BIZ008", "Posh Nails & Spa", "Denver"),
    ("BIZ009", "Glow Studio", "Boston"),
    ("BIZ010", "Elevate Salon", "Nashville"),
]

SERVICES = {
    "Hair": [
        ("Haircut & Style", 65, 30),
        ("Color - Single Process", 110, 60),
        ("Color - Highlights", 165, 120),
        ("Blowout", 50, 45),
        ("Keratin Treatment", 275, 120),
        ("Balayage", 220, 150),
        ("Root Touch-Up", 85, 60),
    ],
    "Nails": [
        ("Manicure", 35, 30),
        ("Pedicure", 55, 45),
        ("Gel Manicure", 50, 45),
        ("Dip Powder Nails", 65, 60),
        ("Nail Art Add-On", 20, 15),
    ],
    "Skin": [
        ("Classic Facial", 95, 60),
        ("Deep Cleansing Facial", 120, 75),
        ("Chemical Peel", 145, 60),
        ("Microdermabrasion", 130, 60),
        ("LED Light Therapy", 85, 45),
    ],
    "Massage": [
        ("Swedish Massage 60min", 110, 60),
        ("Deep Tissue 60min", 125, 60),
        ("Hot Stone Massage", 140, 75),
        ("Prenatal Massage", 110, 60),
    ],
    "Waxing": [
        ("Brow Wax & Shape", 25, 15),
        ("Full Leg Wax", 75, 45),
        ("Brazilian Wax", 65, 30),
        ("Lip & Chin Wax", 20, 15),
    ],
}

PROVIDERS = [f"PRV{str(i).zfill(4)}" for i in range(1, 51)]
PAYMENT_METHODS = ["credit_card", "debit_card", "apple_pay", "google_pay", "cash", "gift_card"]
BOOKING_SOURCES = ["online_booking", "app", "phone", "walk_in", "referral"]
CANCELLATION_REASONS = [
    "schedule_conflict", "illness", "forgot", "weather", "no_reason_given",
    "rescheduled", "personal_emergency", None, None, None
]

NUM_CLIENTS = 250
clients = [f"CLT{str(i).zfill(5)}" for i in range(1, NUM_CLIENTS + 1)]

client_profiles = {}
for cid in clients:
    biz = random.choice(BUSINESSES)
    category_prefs = random.choices(list(SERVICES.keys()), weights=[40, 20, 20, 10, 10], k=2)
    visit_freq_days = random.choices([21, 35, 45, 60, 90], weights=[15, 30, 25, 20, 10])[0]
    is_high_value = random.random() < 0.25
    is_at_risk = random.random() < 0.30

    if is_at_risk:
        last_visit_offset = random.randint(90, 270)
    else:
        last_visit_offset = random.randint(1, 60)

    client_profiles[cid] = {
        "business_id": biz[0],
        "business_name": biz[1],
        "city": biz[2],
        "preferred_categories": category_prefs,
        "visit_freq_days": visit_freq_days,
        "is_high_value": is_high_value,
        "is_at_risk": is_at_risk,
        "last_visit_offset": last_visit_offset,
    }

appointments = []
order_lines = []

appt_id_counter = 1
order_id_counter = 1
line_id_counter = 1

for cid, profile in client_profiles.items():
    last_visit = TODAY - timedelta(days=profile["last_visit_offset"])
    freq = profile["visit_freq_days"]
    lookback_days = 730

    visit_dates = []
    d = last_visit
    while d > TODAY - timedelta(days=lookback_days):
        jitter = random.randint(-7, 7)
        d = d - timedelta(days=freq + jitter)
        if d > TODAY - timedelta(days=lookback_days):
            visit_dates.append(d)

    visit_dates = sorted(visit_dates)
    if last_visit <= TODAY:
        visit_dates.append(last_visit)

    is_first = True
    for vdate in visit_dates:
        appt_id = f"APT{str(appt_id_counter).zfill(7)}"
        order_id = f"ORD{str(order_id_counter).zfill(7)}"
        appt_id_counter += 1
        order_id_counter += 1

        cat = random.choice(profile["preferred_categories"])
        service = random.choice(SERVICES[cat])
        service_name, base_price, duration = service

        if profile["is_at_risk"] and vdate == last_visit:
            status_roll = random.random()
            if status_roll < 0.35:
                appt_status = "no_show"
            elif status_roll < 0.55:
                appt_status = "late_cancel"
            else:
                appt_status = "completed"
        else:
            status_roll = random.random()
            if status_roll < 0.07:
                appt_status = "cancelled"
            elif status_roll < 0.10:
                appt_status = "no_show"
            else:
                appt_status = "completed"

        cancellation_reason = None
        if appt_status in ("cancelled", "no_show", "late_cancel"):
            cancellation_reason = random.choice(CANCELLATION_REASONS)

        days_advance = random.choices([0, 1, 3, 7, 14, 21], weights=[5, 15, 25, 30, 15, 10])[0]
        booked_at = vdate - timedelta(days=days_advance)
        appt_hour = random.randint(9, 18)
        appt_minute = random.choice([0, 15, 30, 45])
        provider = random.choice(PROVIDERS[:20])

        appointments.append({
            "appointment_id": appt_id,
            "order_id": order_id,
            "client_id": cid,
            "business_id": profile["business_id"],
            "business_name": profile["business_name"],
            "location_city": profile["city"],
            "provider_id": provider,
            "appointment_date": vdate.date(),
            "appointment_time": f"{appt_hour:02d}:{appt_minute:02d}:00",
            "service_duration_mins": duration,
            "appointment_status": appt_status,
            "booking_source": random.choice(BOOKING_SOURCES),
            "booked_at": booked_at.date(),
            "days_booked_in_advance": days_advance,
            "cancellation_reason": cancellation_reason,
            "is_first_visit": is_first,
            "service_category": cat,
        })
        is_first = False

        if appt_status == "completed":
            price_var = round(base_price * random.uniform(0.9, 1.15), 2)
            discount = round(price_var * random.uniform(0, 0.1), 2) if random.random() < 0.2 else 0.0
            tip_pct = random.choices([0, 0.15, 0.18, 0.20, 0.25], weights=[20, 25, 30, 20, 5])[0]
            tip = round((price_var - discount) * tip_pct, 2)
            line_total = round(price_var - discount + tip, 2)

            order_lines.append({
                "order_line_id": f"OL{str(line_id_counter).zfill(8)}",
                "order_id": order_id,
                "appointment_id": appt_id,
                "client_id": cid,
                "business_id": profile["business_id"],
                "service_date": vdate.date(),
                "service_category": cat,
                "service_name": service_name,
                "provider_id": provider,
                "unit_price": price_var,
                "quantity": 1,
                "discount_amount": discount,
                "tip_amount": tip,
                "line_total": line_total,
                "order_status": "completed",
                "payment_method": random.choice(PAYMENT_METHODS),
            })
            line_id_counter += 1

            if profile["is_high_value"] and random.random() < 0.4:
                add_on_cat = "Nails" if cat != "Nails" else "Waxing"
                add_on = random.choice(SERVICES[add_on_cat])
                ao_name, ao_price, ao_dur = add_on
                ao_price_var = round(ao_price * random.uniform(0.95, 1.05), 2)
                ao_tip = round(ao_price_var * random.choice([0, 0.15, 0.18, 0.20]), 2)
                order_lines.append({
                    "order_line_id": f"OL{str(line_id_counter).zfill(8)}",
                    "order_id": order_id,
                    "appointment_id": appt_id,
                    "client_id": cid,
                    "business_id": profile["business_id"],
                    "service_date": vdate.date(),
                    "service_category": add_on_cat,
                    "service_name": ao_name,
                    "provider_id": provider,
                    "unit_price": ao_price_var,
                    "quantity": 1,
                    "discount_amount": 0.0,
                    "tip_amount": ao_tip,
                    "line_total": round(ao_price_var + ao_tip, 2),
                    "order_status": "completed",
                    "payment_method": random.choice(PAYMENT_METHODS),
                })
                line_id_counter += 1

df_appts = pd.DataFrame(appointments)
df_orders = pd.DataFrame(order_lines)

df_appts.to_csv("appointments.csv", index=False)
df_orders.to_csv("order_lines.csv", index=False)

print(f"Appointments: {len(df_appts)} rows")
print(f"Order Lines:  {len(df_orders)} rows")
print(f"Clients:      {df_appts['client_id'].nunique()}")
print(f"Businesses:   {df_appts['business_id'].nunique()}")
print(f"Date range:   {df_appts['appointment_date'].min()} → {df_appts['appointment_date'].max()}")
print(f"\nAppointment status breakdown:")
print(df_appts['appointment_status'].value_counts())
print(f"\nService category breakdown (order lines):")
print(df_orders['service_category'].value_counts())
