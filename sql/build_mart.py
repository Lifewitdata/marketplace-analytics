"""Build wanderly.db (SQLite) from data/*.csv — the analytics mart for the SQL suite."""
import sqlite3
import pandas as pd

DB = "wanderly.db"
D = "data"

tables = {
    "sessions": "sessions.csv",
    "bookings": "bookings.csv",
    "users": "users.csv",
    "experiences": "experiences.csv",
    "suppliers": "suppliers.csv",
    "marketing_spend": "marketing_spend.csv",
    "experiment": "experiment.csv",
}

con = sqlite3.connect(DB)
for table, csv in tables.items():
    df = pd.read_csv(f"{D}/{csv}")
    df.to_sql(table, con, if_exists="replace", index=False)
    print(f"{table}: {len(df):,} rows")

# Helpful indexes, like a real mart would have
cur = con.cursor()
cur.execute("CREATE INDEX IF NOT EXISTS ix_bookings_date ON bookings(booking_date)")
cur.execute("CREATE INDEX IF NOT EXISTS ix_bookings_status ON bookings(status)")
cur.execute("CREATE INDEX IF NOT EXISTS ix_sessions_date ON sessions(session_date)")
cur.execute("CREATE INDEX IF NOT EXISTS ix_experiment_variant ON experiment(variant)")
con.commit()

# Sanity check
for t in tables:
    n = con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
    print(f"  verified {t}: {n:,}")
con.close()
print("built:", DB)
