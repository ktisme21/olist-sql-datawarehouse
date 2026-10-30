import glob
import pandas as pd

for f in sorted(glob.glob("*.csv")):
    df = pd.read_csv(f)
    print("\n=====", f, "=====")
    print("rows:", len(df))
    print("columns:", list(df.columns))
