USE olist;

-- =====================================================================
-- Phase 4: Advanced SQL — Cohorts, RFM Segmentation, Seller Pareto
-- =====================================================================
-- Roadmap sections covered:
--   4.1  Customer Cohort Retention Analysis
--   4.2  RFM Segmentation (Recency, Frequency, Monetary)
--   4.3  Seller Pareto Analysis (80/20 Revenue Distribution)
-- =====================================================================


-- =====================================================================
-- 4.1 Customer Cohort Retention Analysis
-- -----------------------------------------------------------------------
-- Business Question:
--   Of customers who placed their first order in a given month (cohort),
--   how many come back to buy again in month +1, +2, +3, +6, +12?
--
-- Key Finding (expected):
--   Olist has an extremely low repeat-buyer rate (~3%). Most cohorts
--   show near-zero retention after month_0 — confirming Olist behaves
--   more like a lead-generation engine than a habitual marketplace.
-- =====================================================================
WITH customer_first_purchase AS (
    -- Identify each unique customer's first purchase month (cohort)
    SELECT
        c.customer_unique_id,
        MIN(DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')) AS cohort_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_orders AS (
    -- Every purchase month for every unique customer
    SELECT
        c.customer_unique_id,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
),
cohort_table AS (
    -- For each (cohort, purchase_month) pair, count active users and
    -- calculate month_index = months since cohort month
    SELECT
        fp.cohort_month,
        co.order_month,
        TIMESTAMPDIFF(
            MONTH,
            STR_TO_DATE(CONCAT(fp.cohort_month, '-01'), '%Y-%m-%d'),
            STR_TO_DATE(CONCAT(co.order_month,  '-01'), '%Y-%m-%d')
        ) AS month_index,
        COUNT(DISTINCT fp.customer_unique_id) AS active_users
    FROM customer_first_purchase fp
    JOIN customer_orders co ON fp.customer_unique_id = co.customer_unique_id
    GROUP BY fp.cohort_month, co.order_month, month_index
)
-- Pivot: one row per cohort, columns for each month_index
SELECT
    cohort_month,
    MAX(CASE WHEN month_index = 0  THEN active_users ELSE 0 END) AS month_0_base,
    MAX(CASE WHEN month_index = 1  THEN active_users ELSE 0 END) AS month_1,
    MAX(CASE WHEN month_index = 2  THEN active_users ELSE 0 END) AS month_2,
    MAX(CASE WHEN month_index = 3  THEN active_users ELSE 0 END) AS month_3,
    MAX(CASE WHEN month_index = 6  THEN active_users ELSE 0 END) AS month_6,
    MAX(CASE WHEN month_index = 12 THEN active_users ELSE 0 END) AS month_12
FROM cohort_table
-- Limit to cohorts with at least 12 months of observable history
WHERE cohort_month BETWEEN '2017-01' AND '2018-01'
GROUP BY cohort_month
ORDER BY cohort_month;


-- =====================================================================
-- 4.1b Cohort Retention RATE (%) — easier to read for presentations
-- -----------------------------------------------------------------------
-- Shows month_1 through month_6 as a percentage of the cohort base.
-- =====================================================================
WITH customer_first_purchase AS (
    SELECT
        c.customer_unique_id,
        MIN(DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')) AS cohort_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_orders AS (
    SELECT
        c.customer_unique_id,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
),
cohort_table AS (
    SELECT
        fp.cohort_month,
        TIMESTAMPDIFF(
            MONTH,
            STR_TO_DATE(CONCAT(fp.cohort_month, '-01'), '%Y-%m-%d'),
            STR_TO_DATE(CONCAT(co.order_month,  '-01'), '%Y-%m-%d')
        ) AS month_index,
        COUNT(DISTINCT fp.customer_unique_id) AS active_users
    FROM customer_first_purchase fp
    JOIN customer_orders co ON fp.customer_unique_id = co.customer_unique_id
    GROUP BY fp.cohort_month, month_index
),
pivoted AS (
    SELECT
        cohort_month,
        MAX(CASE WHEN month_index = 0 THEN active_users ELSE 0 END) AS base,
        MAX(CASE WHEN month_index = 1 THEN active_users ELSE 0 END) AS m1,
        MAX(CASE WHEN month_index = 2 THEN active_users ELSE 0 END) AS m2,
        MAX(CASE WHEN month_index = 3 THEN active_users ELSE 0 END) AS m3,
        MAX(CASE WHEN month_index = 6 THEN active_users ELSE 0 END) AS m6
    FROM cohort_table
    WHERE cohort_month BETWEEN '2017-01' AND '2018-01'
    GROUP BY cohort_month
)
SELECT
    cohort_month,
    base                                      AS cohort_size,
    ROUND(m1 * 100.0 / base, 2)              AS retention_month_1_pct,
    ROUND(m2 * 100.0 / base, 2)              AS retention_month_2_pct,
    ROUND(m3 * 100.0 / base, 2)              AS retention_month_3_pct,
    ROUND(m6 * 100.0 / base, 2)              AS retention_month_6_pct
FROM pivoted
ORDER BY cohort_month;


-- =====================================================================
-- 4.2 Customer RFM Segmentation
-- -----------------------------------------------------------------------
-- Business Question:
--   Who are our most valuable customers? Segment the customer base by:
--   R = Recency   (days since last purchase — lower = better)
--   F = Frequency (number of distinct orders placed)
--   M = Monetary  (total payment amount)
--
-- Scoring:
--   R & M -> NTILE(4): 1=worst, 4=best
--   F     -> binary: 4 if repeat buyer (>1 order), 1 if one-time buyer
--            (binary because ~97% of Olist customers buy only once)
-- =====================================================================
WITH max_dataset_date AS (
    -- Use the latest purchase date as reference "today"
    SELECT MAX(order_purchase_timestamp) AS reference_date
    FROM orders
),
customer_rfm_raw AS (
    SELECT
        c.customer_unique_id,
        DATEDIFF(ref.reference_date, MAX(o.order_purchase_timestamp)) AS recency_days,
        COUNT(DISTINCT o.order_id)                                     AS frequency_orders,
        ROUND(SUM(p.payment_value), 2)                                 AS monetary_spend
    FROM orders o
    JOIN customers c        ON o.customer_id    = c.customer_id
    JOIN order_payments p   ON o.order_id       = p.order_id
    CROSS JOIN max_dataset_date ref
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id, ref.reference_date
),
rfm_scores AS (
    SELECT
        customer_unique_id,
        recency_days,
        frequency_orders,
        monetary_spend,
        -- Lower recency days = more recent = higher score
        NTILE(4) OVER (ORDER BY recency_days DESC)  AS r_score,
        -- Frequency is heavily skewed (97% buy once) -> binary scoring
        CASE WHEN frequency_orders > 1 THEN 4 ELSE 1 END AS f_score,
        -- Higher spend = higher score
        NTILE(4) OVER (ORDER BY monetary_spend ASC)  AS m_score
    FROM customer_rfm_raw
)
SELECT
    customer_unique_id,
    recency_days,
    frequency_orders,
    monetary_spend,
    CONCAT(r_score, f_score, m_score)                  AS rfm_code,
    CASE
        WHEN r_score >= 3 AND f_score = 4 AND m_score >= 3 THEN 'Champions'
        WHEN r_score >= 3 AND f_score = 4                  THEN 'Loyal Customers'
        WHEN r_score >= 3 AND f_score = 1 AND m_score >= 3 THEN 'Promising High-Spenders'
        WHEN r_score = 1  AND f_score = 4                  THEN 'Cant Lose Them (At Risk)'
        WHEN r_score = 1  AND m_score = 1                  THEN 'Lost / Churned'
        ELSE 'Standard One-Time Buyers'
    END AS customer_segment
FROM rfm_scores
ORDER BY monetary_spend DESC
LIMIT 100;


-- =====================================================================
-- 4.2b RFM Segment Summary — Aggregate counts & value per segment
-- -----------------------------------------------------------------------
-- Use this for the portfolio write-up and charts.
-- =====================================================================
WITH max_dataset_date AS (
    SELECT MAX(order_purchase_timestamp) AS reference_date FROM orders
),
customer_rfm_raw AS (
    SELECT
        c.customer_unique_id,
        DATEDIFF(ref.reference_date, MAX(o.order_purchase_timestamp)) AS recency_days,
        COUNT(DISTINCT o.order_id)                                     AS frequency_orders,
        ROUND(SUM(p.payment_value), 2)                                 AS monetary_spend
    FROM orders o
    JOIN customers c      ON o.customer_id  = c.customer_id
    JOIN order_payments p ON o.order_id     = p.order_id
    CROSS JOIN max_dataset_date ref
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id, ref.reference_date
),
rfm_scores AS (
    SELECT
        customer_unique_id,
        recency_days,
        frequency_orders,
        monetary_spend,
        NTILE(4) OVER (ORDER BY recency_days DESC)  AS r_score,
        CASE WHEN frequency_orders > 1 THEN 4 ELSE 1 END AS f_score,
        NTILE(4) OVER (ORDER BY monetary_spend ASC)  AS m_score
    FROM customer_rfm_raw
),
segmented AS (
    SELECT
        customer_unique_id,
        monetary_spend,
        CASE
            WHEN r_score >= 3 AND f_score = 4 AND m_score >= 3 THEN 'Champions'
            WHEN r_score >= 3 AND f_score = 4                  THEN 'Loyal Customers'
            WHEN r_score >= 3 AND f_score = 1 AND m_score >= 3 THEN 'Promising High-Spenders'
            WHEN r_score = 1  AND f_score = 4                  THEN 'Cant Lose Them (At Risk)'
            WHEN r_score = 1  AND m_score = 1                  THEN 'Lost / Churned'
            ELSE 'Standard One-Time Buyers'
        END AS customer_segment
    FROM rfm_scores
)
SELECT
    customer_segment,
    COUNT(*)                                                           AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2)               AS pct_of_customers,
    ROUND(SUM(monetary_spend), 2)                                      AS total_revenue,
    ROUND(AVG(monetary_spend), 2)                                      AS avg_spend_per_customer
FROM segmented
GROUP BY customer_segment
ORDER BY total_revenue DESC;


-- =====================================================================
-- 4.3 Seller Pareto Analysis (80/20 Revenue Distribution)
-- -----------------------------------------------------------------------
-- Business Question:
--   Do the top 20% of sellers generate 80% of marketplace revenue?
--   (Classic Pareto / Power-law check for marketplace health)
-- =====================================================================
WITH seller_sales AS (
    SELECT
        oi.seller_id,
        s.seller_state,
        ROUND(SUM(oi.price), 2)       AS seller_gmv,
        COUNT(oi.order_item_id)        AS units_sold
    FROM order_items oi
    JOIN sellers s ON oi.seller_id = s.seller_id
    GROUP BY oi.seller_id, s.seller_state
),
cumulative_sellers AS (
    SELECT
        seller_id,
        seller_state,
        seller_gmv,
        units_sold,
        ROW_NUMBER() OVER (ORDER BY seller_gmv DESC)      AS seller_rank,
        COUNT(*)     OVER ()                               AS total_sellers,
        SUM(seller_gmv) OVER (ORDER BY seller_gmv DESC)   AS running_gmv,
        SUM(seller_gmv) OVER ()                            AS grand_total_gmv
    FROM seller_sales
)
SELECT
    seller_id,
    seller_state,
    seller_gmv,
    units_sold,
    seller_rank,
    ROUND(seller_rank * 100.0 / total_sellers, 2)       AS seller_percentile,
    ROUND(running_gmv * 100.0 / grand_total_gmv, 2)     AS cumulative_revenue_pct
FROM cumulative_sellers
-- Show milestone ranks + rows where cumulative revenue crosses 20%, 50%, 80%
WHERE seller_rank IN (1, 10, 50, 100, 500, 1000)
   OR ROUND(running_gmv * 100.0 / grand_total_gmv, 0) IN (20, 50, 80)
ORDER BY seller_rank;


-- =====================================================================
-- 4.3b Top 20 Sellers Detailed View
-- -----------------------------------------------------------------------
-- For portfolio: highlight the top sellers with full metrics.
-- =====================================================================
WITH seller_sales AS (
    SELECT
        oi.seller_id,
        s.seller_state,
        s.seller_city,
        ROUND(SUM(oi.price), 2)         AS seller_gmv,
        ROUND(SUM(oi.freight_value), 2) AS total_freight_earned,
        COUNT(DISTINCT oi.order_id)     AS total_orders,
        COUNT(oi.order_item_id)         AS units_sold,
        ROUND(AVG(r.review_score), 2)   AS avg_review_score
    FROM order_items oi
    JOIN sellers s ON oi.seller_id = s.seller_id
    LEFT JOIN (
        SELECT order_id, AVG(review_score) AS review_score
        FROM order_reviews
        GROUP BY order_id
    ) r ON oi.order_id = r.order_id
    GROUP BY oi.seller_id, s.seller_state, s.seller_city
)
SELECT
    seller_id,
    seller_state,
    seller_city,
    seller_gmv,
    total_freight_earned,
    total_orders,
    units_sold,
    avg_review_score,
    ROUND(seller_gmv * 100.0 / SUM(seller_gmv) OVER (), 2) AS gmv_share_pct
FROM seller_sales
ORDER BY seller_gmv DESC
LIMIT 20;
