"""Verify every SQL query reproduces the Python findings. Fails loudly on mismatch."""
import re
import sqlite3

con = sqlite3.connect("wanderly.db")
sql = open("sql/analysis_queries.sql").read()

# Split on the Q-markers; each chunk starts with its SELECT(s)
markers = [(m.group(1), m.start()) for m in re.finditer(r"-- Q(\d+) ", sql)]
markers.append((None, len(sql)))
queries = {}
for (qid, start), (_, end) in zip(markers, markers[1:]):
    ch = sql[start:end]
    m = re.search(r"(SELECT|WITH)\b", ch)
    body = ch[m.start():] if m else ch
    parts = [p.strip() for p in re.split(r";\s*\n\s*\nSELECT", body) if p.strip()]
    fixed = [("SELECT " + p if i > 0 else p) for i, p in enumerate(parts)]
    queries["Q" + qid] = fixed

def run(q):
    return con.execute(q).fetchall()

ok = True
def check(name, actual, expected, tol=0.011):
    global ok
    good = abs(actual - expected) <= tol * max(1, abs(expected))
    print(("PASS " if good else "FAIL ") + f"{name}: sql={actual} expected={expected}")
    ok = ok and good

# Q1 — KPI scorecard
r = run(queries["Q1"][0])[0]
check("Q1 bookings", r[0], 5785, tol=0)
check("Q1 gmv", r[1], 1245086, tol=0.001)
check("Q1 aov", r[2], 215.23, tol=0.001)
r = run(queries["Q1"][1])[0]
check("Q1 session conv", r[0], 0.0545, tol=0.01)

# Q3 — funnel step conversions
rows = run(queries["Q3"][0])
step = {s: c for s, n, c in rows}
check("Q3 listing step", step["listing"] / 100, 0.556, tol=0.01)
check("Q3 product step", step["product"] / 100, 0.463, tol=0.01)
check("Q3 checkout step", step["checkout"] / 100, 0.363, tol=0.01)
check("Q3 booked step", step["booked"] / 100, 0.583, tol=0.01)

# Q5 — ROAS by channel
rows = run(queries["Q5"][0])
roas = {c: r_ for c, b, rev, s, r_ in rows}
check("Q5 email ROAS", roas["email"], 5.3, tol=0.05)
check("Q5 paid_search ROAS", roas["paid_search"], 2.0, tol=0.05)
check("Q5 affiliates ROAS", roas["affiliates"], 1.9, tol=0.05)
check("Q5 social ROAS", roas["social"], 0.5, tol=0.05)

# Q9 — experiment readout
rows = run(queries["Q9"][0])
exp = {v: (n, c) for v, n, c, rev in rows}
check("Q9 control n", exp["A"][0], 8000, tol=0)
check("Q9 treatment n", exp["B"][0], 8000, tol=0)
check("Q9 control conv", exp["A"][1] / 100, 0.0478, tol=0.02)
check("Q9 treatment conv", exp["B"][1] / 100, 0.0585, tol=0.02)

# Q2/Q10 smoke: right months, all cities present
rows = run(queries["Q2"][0])
assert rows[0][0] == "2024-07" and rows[-1][0] == "2025-06", "Q2 month range"
print(f"PASS Q2 month range 2024-07..2025-06 ({len(rows)} months)")
rows = run(queries["Q10"][0])
assert len(rows) == 8, "Q10 cities"
print("PASS Q10 8 cities")

print("\nALL CHECKS PASSED" if ok else "\nMISMATCHES FOUND")
raise SystemExit(0 if ok else 1)
