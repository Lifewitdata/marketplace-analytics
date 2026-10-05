-- ============================================================================
-- Wanderly Marketplace Analytics — SQL suite (basic -> advanced)
-- Run against wanderly.db (built by sql/build_mart.py).
-- Every query reproduces a number from the Python analysis; see sql/verify_sql.py.
-- Techniques: CTEs, window functions (LAG, RANK, running totals), conditional
-- aggregation, funnel math, cohort retention, experiment readout.
-- ============================================================================

-- Q1 -------------------------------------------------------------------------
-- KPI SCORECARD (basic): bookings, GMV, AOV, conversion, cancellation rate
-- ----------------------------------------------------------------------------
SELECT
    COUNT(*)                                        AS completed_bookings,
    ROUND(SUM(gross_usd), 0)                        AS gmv_usd,
    ROUND(AVG(gross_usd), 2)                        AS aov_usd,
    ROUND(AVG(CASE WHEN status IN ('cancelled','refunded') THEN 1.0 ELSE 0 END), 4)
                                                    AS cancel_refund_rate
FROM bookings
WHERE status = 'completed';

SELECT ROUND(AVG(converted), 4) AS session_to_booking_conv FROM sessions;

-- Q2 -------------------------------------------------------------------------
-- MONTHLY GMV TREND + MoM GROWTH (window: LAG)
-- ----------------------------------------------------------------------------
WITH monthly AS (
    SELECT substr(booking_date, 1, 7) AS month,
           COUNT(*)                  AS bookings,
           ROUND(SUM(gross_usd), 0)  AS gmv
    FROM bookings
    WHERE status = 'completed'
    GROUP BY 1
)
SELECT month, bookings, gmv,
       LAG(gmv) OVER (ORDER BY month) AS prev_gmv,
       ROUND(100.0 * (gmv - LAG(gmv) OVER (ORDER BY month))
             / NULLIF(LAG(gmv) OVER (ORDER BY month), 0), 1) AS mom_pct
FROM monthly
ORDER BY month;

-- Q3 -------------------------------------------------------------------------
-- CONVERSION FUNNEL (conditional aggregation): how many sessions reached each
-- stage, and the step-to-step conversion that exposes the biggest leak.
-- ----------------------------------------------------------------------------
WITH stage_ord(stage, ord) AS (
    VALUES ('landing',1), ('listing',2), ('product',3), ('checkout',4), ('booked',5)
),
reached AS (
    SELECT st.stage,
           SUM(CASE WHEN s2.ord >= st.ord THEN 1 ELSE 0 END) AS n
    FROM stage_ord st
    CROSS JOIN (SELECT s.stage_reached, o.ord
                FROM sessions s JOIN stage_ord o ON o.stage = s.stage_reached) s2
    GROUP BY st.stage, st.ord
)
SELECT stage, n AS sessions_reached,
       ROUND(100.0 * n / NULLIF(LAG(n) OVER (ORDER BY
           CASE stage WHEN 'landing' THEN 1 WHEN 'listing' THEN 2 WHEN 'product' THEN 3
                      WHEN 'checkout' THEN 4 WHEN 'booked' THEN 5 END), 0), 1)
           AS step_conv_pct
FROM reached
ORDER BY CASE stage WHEN 'landing' THEN 1 WHEN 'listing' THEN 2 WHEN 'product' THEN 3
                   WHEN 'checkout' THEN 4 WHEN 'booked' THEN 5 END;

-- Q4 -------------------------------------------------------------------------
-- FUNNEL BREAKDOWN BY CHANNEL x DEVICE (where does the funnel break?)
-- ----------------------------------------------------------------------------
WITH stage_ord(stage, ord) AS (
    VALUES ('landing',1), ('listing',2), ('product',3), ('checkout',4), ('booked',5)
)
SELECT s.channel, s.device,
       COUNT(*) AS sessions,
       ROUND(100.0 * AVG(s.converted), 2) AS conv_pct,
       ROUND(100.0 * AVG(CASE WHEN o.ord >= 4 THEN 1.0 ELSE 0 END), 2) AS reached_checkout_pct
FROM sessions s JOIN stage_ord o ON o.stage = s.stage_reached
GROUP BY s.channel, s.device
ORDER BY sessions DESC;

-- Q5 -------------------------------------------------------------------------
-- CHANNEL ATTRIBUTION + ROAS (join to marketing spend)
-- ----------------------------------------------------------------------------
WITH attr AS (
    SELECT channel,
           COUNT(*)              AS bookings,
           ROUND(SUM(gross_usd), 0) AS revenue
    FROM bookings
    WHERE status = 'completed'
    GROUP BY channel
),
spend AS (
    SELECT channel, ROUND(SUM(spend_usd), 0) AS spend
    FROM marketing_spend
    GROUP BY channel
)
SELECT a.channel, a.bookings, a.revenue,
       COALESCE(s.spend, 0) AS spend,
       CASE WHEN COALESCE(s.spend, 0) = 0 THEN NULL
            ELSE ROUND(a.revenue * 1.0 / s.spend, 2) END AS roas
FROM attr a LEFT JOIN spend s ON s.channel = a.channel
ORDER BY a.revenue DESC;

-- Q6 -------------------------------------------------------------------------
-- COHORT RETENTION (advanced): by signup month, what share of bookers came
-- back for a 2nd+ booking? Classic product-health metric.
-- ----------------------------------------------------------------------------
WITH user_bookings AS (
    SELECT user_id, COUNT(*) AS n_bookings
    FROM bookings
    WHERE status = 'completed'
    GROUP BY user_id
),
cohorts AS (
    SELECT substr(u.signup_date, 1, 7) AS cohort_month,
           u.user_id,
           CASE WHEN COALESCE(ub.n_bookings, 0) >= 2 THEN 1 ELSE 0 END AS is_repeat
    FROM users u LEFT JOIN user_bookings ub ON ub.user_id = u.user_id
)
SELECT cohort_month,
       COUNT(*) AS users,
       SUM(is_repeat) AS repeat_users,
       ROUND(100.0 * AVG(is_repeat), 1) AS repeat_rate_pct
FROM cohorts
GROUP BY cohort_month
ORDER BY cohort_month;

-- Q7 -------------------------------------------------------------------------
-- SUPPLY-SIDE ECONOMICS: GMV share by supplier tier + top suppliers (RANK)
-- ----------------------------------------------------------------------------
WITH supplier_gmv AS (
    SELECT sp.supplier_id, sp.tier, sp.city,
           COUNT(b.booking_id) AS bookings,
           ROUND(SUM(b.gross_usd), 0) AS gmv
    FROM bookings b
    JOIN experiences e ON e.experience_id = b.experience_id
    JOIN suppliers sp  ON sp.supplier_id = e.supplier_id
    WHERE b.status = 'completed'
    GROUP BY sp.supplier_id, sp.tier, sp.city
)
SELECT tier,
       COUNT(*) AS n_suppliers,
       SUM(bookings) AS bookings,
       SUM(gmv) AS gmv,
       ROUND(100.0 * SUM(gmv) / SUM(SUM(gmv)) OVER (), 1) AS gmv_share_pct
FROM supplier_gmv
GROUP BY tier
ORDER BY gmv DESC;

SELECT supplier_id, tier, city, bookings, gmv,
       RANK() OVER (ORDER BY gmv DESC) AS gmv_rank
FROM (
    SELECT sp.supplier_id, sp.tier, sp.city,
           COUNT(b.booking_id) AS bookings,
           ROUND(SUM(b.gross_usd), 0) AS gmv
    FROM bookings b
    JOIN experiences e ON e.experience_id = b.experience_id
    JOIN suppliers sp  ON sp.supplier_id = e.supplier_id
    WHERE b.status = 'completed'
    GROUP BY sp.supplier_id, sp.tier, sp.city
)
ORDER BY gmv_rank
LIMIT 10;

-- Q8 -------------------------------------------------------------------------
-- BOOKING LEAD TIME: distribution buckets (impulse vs. planned demand)
-- ----------------------------------------------------------------------------
SELECT
    CASE WHEN lead_days < 7 THEN '0-6 days (last-minute)'
         WHEN lead_days < 21 THEN '7-20 days'
         WHEN lead_days < 60 THEN '21-59 days'
         ELSE '60+ days (planners)' END AS lead_bucket,
    COUNT(*) AS bookings,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct,
    ROUND(AVG(gross_usd), 0) AS avg_gmv
FROM (SELECT julianday(travel_date) - julianday(booking_date) AS lead_days, gross_usd
      FROM bookings WHERE status = 'completed')
GROUP BY lead_bucket
ORDER BY MIN(lead_days);

-- Q9 -------------------------------------------------------------------------
-- EXPERIMENT READOUT: free-cancellation badge A/B test
-- ----------------------------------------------------------------------------
SELECT variant,
       COUNT(*) AS n,
       ROUND(100.0 * AVG(converted), 2) AS conv_pct,
       ROUND(SUM(revenue_usd), 0) AS revenue_usd
FROM experiment
GROUP BY variant;

-- Q10 ------------------------------------------------------------------------
-- CITY GMV MIX + RUNNING SHARE (window: cumulative share)
-- ----------------------------------------------------------------------------
WITH city AS (
    SELECT e.city,
           COUNT(b.booking_id) AS bookings,
           ROUND(SUM(b.gross_usd), 0) AS gmv
    FROM bookings b JOIN experiences e ON e.experience_id = b.experience_id
    WHERE b.status = 'completed'
    GROUP BY e.city
)
SELECT city, bookings, gmv,
       ROUND(100.0 * gmv / SUM(gmv) OVER (), 1) AS share_pct,
       ROUND(100.0 * SUM(gmv) OVER (ORDER BY gmv DESC
                                    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             / SUM(gmv) OVER (), 1) AS running_share_pct
FROM city
ORDER BY gmv DESC;
