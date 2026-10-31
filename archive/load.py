# step 4, write etl script (extract, transform, load)
# e: transform csv with pandas
# t: clean and reshape them to match the schema
# l: insert them into mysql
# step 5, load the dimension tables first, then the fact table (because it points at the dimensions)
# step 6, validate the row counts
# step 7, write queries
# step 8, record the performance using EXPLAIN ANALYZE 


"""Load the Olist CSVs into the MySQL star schema (run schema.sql first).

Usage:
    export OLIST_DB_URL="mysql+pymysql://root:YOUR_PASSWORD@127.0.0.1:3306/olist"
    python3 load.py

CSVs are read from the same folder as this script, or from OLIST_DATA_DIR.
"""
import os
from pathlib import Path

import pandas as pd
from sqlalchemy import create_engine, text

DATA_DIR = Path(os.environ.get("OLIST_DATA_DIR", Path(__file__).resolve().parent))

# 1. CONNECT (credentials come from the environment, never from the code)
db_url = os.environ.get("OLIST_DB_URL")
if not db_url:
    raise SystemExit(
        'Set OLIST_DB_URL first, e.g.\n'
        'export OLIST_DB_URL="mysql+pymysql://root:YOUR_PASSWORD@127.0.0.1:3306/olist"'
    )
engine = create_engine(db_url)

# 2. CLEAR old data so the script can be re-run safely (fact table first,
#    because it points at the dimensions)
with engine.begin() as conn:
    for t in ["fact_order_items", "dim_customer", "dim_seller", "dim_product", "dim_date"]:
        conn.execute(text(f"DELETE FROM {t}"))

# 3. dim_customer
customers = pd.read_csv(DATA_DIR / "olist_customers_dataset.csv", dtype=str)
dim_customer = pd.DataFrame({
    "customer_id": customers["customer_id"],
    "customer_unique_id": customers["customer_unique_id"],
    "zip_code_prefix": customers["customer_zip_code_prefix"].str.zfill(5),
    "city": customers["customer_city"],
    "state": customers["customer_state"],
})
dim_customer.to_sql("dim_customer", engine, if_exists="append", index=False, chunksize=5000)

# 4. dim_seller
sellers = pd.read_csv(DATA_DIR / "olist_sellers_dataset.csv", dtype=str)
dim_seller = pd.DataFrame({
    "seller_id": sellers["seller_id"],
    "zip_code_prefix": sellers["seller_zip_code_prefix"].str.zfill(5),
    "city": sellers["seller_city"],
    "state": sellers["seller_state"],
})
dim_seller.to_sql("dim_seller", engine, if_exists="append", index=False, chunksize=5000)

# 5. dim_product (products + English category names; left merge keeps
#    products that have no translation)
products = pd.read_csv(DATA_DIR / "olist_products_dataset.csv")
translation = pd.read_csv(DATA_DIR / "product_category_name_translation.csv")
products = products.merge(translation, on="product_category_name", how="left")
dim_product = pd.DataFrame({
    "product_id": products["product_id"],
    "category_name_pt": products["product_category_name"],
    "category_name_en": products["product_category_name_english"],
    "weight_g": products["product_weight_g"],
    "length_cm": products["product_length_cm"],
    "height_cm": products["product_height_cm"],
    "width_cm": products["product_width_cm"],
})
dim_product.to_sql("dim_product", engine, if_exists="append", index=False, chunksize=5000)

# 6. dim_date (one row per day between the first and last purchase)
orders = pd.read_csv(
    DATA_DIR / "olist_orders_dataset.csv",
    parse_dates=["order_purchase_timestamp",
                 "order_delivered_customer_date",
                 "order_estimated_delivery_date"],
)
days = pd.date_range(orders["order_purchase_timestamp"].min().normalize(),
                     orders["order_purchase_timestamp"].max().normalize())
dim_date = pd.DataFrame({
    "date_id": days.date,
    "year": days.year,
    "month": days.month,
    "day": days.day,
    "weekday": days.day_of_week,
})
dim_date.to_sql("dim_date", engine, if_exists="append", index=False)

# 7. fact_order_items: order_items + orders merged on order_id
items = pd.read_csv(DATA_DIR / "olist_order_items_dataset.csv")
df = items.merge(
    orders[["order_id", "customer_id", "order_status",
            "order_purchase_timestamp",
            "order_delivered_customer_date",
            "order_estimated_delivery_date"]],
    on="order_id", how="inner",
)

# Whole-day delivery metrics (NULL when the order was never delivered)
purchase = df["order_purchase_timestamp"].dt.normalize()
delivered = df["order_delivered_customer_date"].dt.normalize()
estimated = df["order_estimated_delivery_date"].dt.normalize()

fact = pd.DataFrame({
    "order_id": df["order_id"],
    "order_item_id": df["order_item_id"],
    "customer_id": df["customer_id"],
    "product_id": df["product_id"],
    "seller_id": df["seller_id"],
    "purchase_date": purchase.dt.date,
    "order_status": df["order_status"],
    "price": df["price"],
    "freight_value": df["freight_value"],
    "delivery_days": (delivered - purchase).dt.days.astype("Int64"),
    "delivery_delay_days": (delivered - estimated).dt.days.astype("Int64"),
})

# pandas' missing-value marker -> real NULLs for MySQL
fact = fact.astype(object).where(fact.notna(), None)
fact.to_sql("fact_order_items", engine, if_exists="append", index=False, chunksize=5000)

# 8. VERIFY row counts
with engine.connect() as conn:
    for t in ["dim_customer", "dim_seller", "dim_product", "dim_date", "fact_order_items"]:
        n = conn.execute(text(f"SELECT COUNT(*) FROM {t}")).scalar()
        print(t, n)
print("expected fact_order_items:", len(fact))