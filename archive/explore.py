# step 1, explore the raw data,print the row counts and columns names of every csv
import glob
import pandas as pd

for f in sorted(glob.glob("*.csv")):
    df = pd.read_csv(f)
    print("\n=====", f, "=====")
    print("rows:", len(df))
    print("columns:", list(df.columns))


# step 2, design dimensional models, -> decide grain (the level of detail), decide fact and dimension tables
# decision:
# star schema>snowflake schema
# grain: one order item one row
# fact table: fact_order_items
# dimension tables: dim_customer, dim_seller, dim_product, dim_date