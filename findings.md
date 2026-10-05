# Wanderly Marketplace Analytics — Findings

*Fictional experiences marketplace. 8 cities · 300 experiences · 60 suppliers ·
120,000 sessions · 5,785 completed bookings · $1.25M GMV · Jul 2024 – Jun 2025.
Deterministic synthetic data (seed 42).*

## KPI scorecard

| KPI | Value |
|---|---|
| Completed bookings | 5,785 |
| GMV | $1,245,086 |
| Average order value | $215.23 |
| Session → booking conversion | 5.45% |
| Cancellation + refund rate | 11.52% |
| Unique bookers | 3,452 |
| Repeat booker rate | 42.0% |
| Avg booking lead time | 12.6 days |

## 1. Demand trend
GMV and bookings build steadily into a year-end holiday peak (Nov–Dec), then reset in
January. Implication: supplier capacity negotiations and marketing budgets should be
locked by Q3 — the peak is predictable, being unprepared for it is a choice.

## 2. Conversion funnel
| Step | Conversion |
|---|---|
| landing → listing | 55.6% |
| listing → product | 46.3% |
| product → checkout | **36.3%** ← biggest leak |
| checkout → booked | 58.3% |

Only ~9% of sessions ever start checkout. Two compounding problems: mobile is 65% of
traffic but converts below desktop, and the product → checkout step is where intent dies.
Hypotheses worth testing: price shock at checkout (fees revealed late), weak urgency
signals, and a mobile checkout flow with too much friction.

## 3. Channel & device breakdown
- Paid search converts best (intent-rich traffic), email second.
- Social converts at roughly half the rate of paid search — yet absorbs $144k/year in spend.
- Mobile checkout lags desktop; tablet is negligible volume.

## 4. Attribution & ROAS
| Channel | Bookings | Revenue | Spend | ROAS |
|---|---|---|---|---|
| paid_search | 2,017 | $432,048 | $216,000 | 2.0x |
| organic | 1,576 | $339,661 | $0 | — |
| referral | 646 | $143,134 | $0 | — |
| affiliates | 626 | $135,519 | $72,000 | 1.9x |
| email | 596 | $126,122 | $24,000 | **5.3x** |
| social | 324 | $68,602 | $144,000 | **0.5x** |

Email is the efficiency king; social destroys value. Recommendation: cut social 50%,
reallocate to email + paid search. Organic + referral drive 38% of bookings at zero
marginal cost — invest in the referral loop instead of paid social.

## 5. Supply-side economics
- Silver-tier suppliers (50% of base) drive 53.5% of GMV; platinum only 7.9% — the
  long tail carries the marketplace.
- High-rated experiences cluster at high capacity utilization: demand exists that
  supply cannot fulfill. Levers: recruit capacity from top-rated suppliers, dynamic
  pricing on constrained inventory, waitlists to capture intent.

## 6. Lead time
Median 12.6 days; the distribution is heavily front-loaded (most trips booked <3 weeks
out). Demand is impulse-driven → retargeting windows in days, not weeks; a 48-hour
pre-travel nudge can rescue part of the 11.5% cancellation rate.

## 7. Experiment: free-cancellation badge
- Control: 4.78% (n=8,000) · Treatment: 5.85% (n=8,000)
- Lift: **+22.5%**, z = 3.03, **p = 0.0024**, 95% CI [+0.38pp, +1.77pp]
- Verdict: **ship it**. Rough value at current traffic: ~+1,500 bookings/year.
- Caveat: watch cancellation rate post-ship — the badge may attract more tentative
  bookers. Guardrail metric: net completed bookings, not gross conversion.

## 8. Geographic mix
No city dominates GMV — healthy diversification across 8 markets, at the cost of
managing 8 separate supply relationships.

## 9. Experiment rigor (new in v2)
- **SRM check**: allocation exactly 8,000/8,000, χ² = 0.000 — no sample-ratio mismatch.
- **Power**: baseline 4.78%, n = 8,000/arm → MDE at 80% power = 0.94pp; observed lift +1.08pp
  clears it. The test was powered to detect this effect — the +22.5% is trustworthy.

## 10. Cohort retention (new in v2)
Repeat-booker rate (2+ completed bookings) by signup cohort — see
`visuals/10_cohort_retention.png`. Acquisition without retention is a leaky bucket.

## 11. Mobile leak, quantified (new in v2)
Product → checkout by device: mobile 34.2% vs. desktop 39.9%. **11,987** mobile sessions
died at that one step — the single largest addressable pool of lost intent.

## 12. SQL layer (new in v2)
`sql/build_mart.py` loads all 7 CSVs into `wanderly.db` (SQLite, indexed like a real mart).
`sql/analysis_queries.sql` holds 10 queries, basic → advanced: KPI scorecard, MoM trend with
LAG, funnel math, channel × device breakdown, attribution + ROAS, cohort retention, supplier
tier share with RANK, lead-time buckets, experiment readout, city mix with running share.
`sql/verify_sql.py` runs 20 assertions — every SQL number matches the Python findings.

## Recommendations (prioritized)
1. Fix product → checkout (36.3%) — mobile checkout UX first.
2. Reallocate social budget → email + paid search (~$60k/year saved at equal bookings).
3. Ship the free-cancellation badge (+22.5% lift, p=0.002).
4. Unlock constrained high-rated supply (capacity or dynamic pricing).
5. Attack the 11.5% cancellation rate with a 48-hour pre-travel nudge.

## Limitations
Synthetic data: effect sizes are designed, not discovered. The value here is the
analytical machinery — funnel math, attribution logic, experiment readout — which
transfers directly to real marketplace data.
