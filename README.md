# Olist E-commerce Data Warehouse (MySQL + Python)

A star-schema data warehouse built from the Brazilian Olist e-commerce dataset,
with analytical SQL queries and a measured query-optimisation study using
`EXPLAIN ANALYZE`.

**Stack:** MySQL, Python (pandas, SQLAlchemy), MySQL Workbench

## Dataset

[Brazilian E-Commerce Public Dataset by Olist (Kaggle)](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce):
9 related CSV files (~100k orders). The CSVs are not included in this repo;
download them and place them next to `load.py`.

## Star schema

```
                  dim_date
                     |
dim_customer ─── fact_order_items ─── dim_product
                     |
                 dim_seller
```

- **`fact_order_items`**: one row per item sold. Measures: `price`,
  `freight_value`, `delivery_days`, `delivery_delay_days`.
- **Dimensions:** `dim_customer`, `dim_seller`, `dim_product`, `dim_date`.
- Primary keys on every table; foreign keys from the fact table to each dimension.

### Design decisions

- **Why a star schema?** The raw data is normalised across 9 files, which suits
  running a shop but makes analysis join-heavy. Analytical questions here group
  by product, region and time, so putting the measures in one fact table and the
  descriptions in dimensions turns most questions into one or two joins.
- **Grain = one order item.** An order can have several items, so the fact
  table's primary key is `(order_id, order_item_id)`.
- **Delivery metrics precomputed at load time.** `delivery_days` and
  `delivery_delay_days` do not exist in the source files; they are derived from
  the order timestamps and are NULL for undelivered orders.
- **`dim_date`** is generated, so queries can group by year and month without
  date functions.
- **`dim_customer` keeps both IDs.** `customer_id` changes with every order, so
  repeat-customer analysis uses `customer_unique_id`.
- **Category translation merged into `dim_product`** so queries don't join the
  translation file.
- **Zip codes stored as text** so leading zeros are preserved.
- **Geolocation (~1M rows) and reviews are not loaded**; they are not needed
  for the questions below.

## How to run

```bash
# 1. Create the schema
mysql -u root -p < schema.sql

# 2. Load the data (CSVs in the same folder as load.py)
pip install -r requirements.txt
export OLIST_DB_URL="mysql+pymysql://root:YOUR_PASSWORD@127.0.0.1:3306/olist"
python3 archive/load.py

# 3. Run queries.sql in MySQL Workbench or the mysql client
```

Row counts after loading: `dim_customer` 99,441, `dim_seller` 3,095,
`dim_product` 32,951, `dim_date` 774, `fact_order_items` 112,650.

## Analytical queries (`queries.sql`)

1. Revenue by product category
2. Revenue by customer state
3. Monthly revenue trend
4. Top 5 sellers by revenue
5. Top 3 categories per state (window function)
6. Delivery performance by state
7. Repeat customers

## Query optimisation

Method: `EXPLAIN ANALYZE` in front of each query, 3 runs where possible,
median of the top-line `actual time`. One change at a time. Environment:
MySQL `<run SELECT VERSION(); and fill in>` on `<your machine>`, ~112k-row fact table.

| Query | Before (ms) | After (ms) | Change |
|---|---|---|---|
| 2. Revenue by state | 370, 372 (median 371) | 200, 208, 205 (median 205) | ~45% faster |
| 4. Top 5 sellers | 234, 236 (median 235) | 88.6, 95.4, 96 (median 95.4) | ~59% faster |
| 5. Top 3 categories per state | 382, 384 (median 383) | 356, 354, 357 (median 356) | ~7%, index not kept |

**What changed:** the automatic foreign-key indexes on `customer_id` and
`seller_id` were replaced by covering indexes `(customer_id, price)` and
`(seller_id, price)`.

**Why it helped (queries 2 and 4):** the plans were already index-driven, but
the old index did not contain `price`, so each of ~100k matches needed an extra
lookup into the main table row. With the covering index, the plan changed from
`Index lookup` to `Covering index lookup` and the per-lookup cost roughly
halved or better. Rows examined stayed the same (112,650); the gain comes from
cheaper reads, not fewer rows.

**Query 5:** its cost is mostly ~225,000 primary-key lookups into the two
dimension tables, which no index removes. A 3-column index gave only ~7%, so it
was dropped: the benefit did not justify the extra storage and slower loads.

**Limitations:** the "before" figures for queries 2 and 4 are 2 runs each;
timings come from a single local machine; the dataset is small, so absolute
gains are modest. All measurements are on the real data (no synthetic scaling).

## Findings

- **Revenue is concentrated geographically.** São Paulo (SP) generates
  R$5.20M of R$13.59M total (~38%); SP, RJ and MG together are ~63%.
- **Top categories:** health_beauty (R$1.26M), watches_gifts (R$1.21M) and
  bed_bath_table (R$1.04M). Products with no category account for R$185k (~1.4%).
- **Growth in 2017:** monthly revenue rose from ~R$120k (Jan 2017) to ~R$1.01M
  (Nov 2017), then stayed around R$850k–R$1.0M through Aug 2018.
- **Delivery is much slower outside the south-east.** Average delivery time is
  8.7 days in SP versus 28.2 days in AP and RR. Every state's average delivery
  beats the estimated date, so estimates look conservative, but AL (20.8%) and
  MA (18.0%) have the highest share of late items.
- **Repeat buyers:** 2,913 customers placed more than one order.

## Data notes

- Some products have no category, so they appear as NULL in category queries.
- Revenue includes all order statuses, including canceled orders.
- The final months of the dataset may be incomplete; treat any drop at the end
  of the monthly trend with caution.
- Delivery columns are NULL for orders that were never delivered.

## Files

- `schema.sql`: tables, keys
- `load.py`: Python ETL (CSV → clean → MySQL)
- `queries.sql`: analytical queries
- `optimisation.sql`: indexing experiments