USE olist;

-- =====================================================================
-- Phase 5: Production Views & Materialized Result Tables
-- =====================================================================
-- Roadmap sections covered:
--   5.1  vw_order_master        — Clean order + customer + review view
--   5.2  vw_order_item_details  — Item + product + category + seller view
--   5.3  rfm_customer_segments  — Materialized RFM result table
--   5.4  cohort_retention       — Materialized cohort retention table
--   5.5  Indexing strategy
-- =====================================================================


-- =====================================================================
-- 5.1 View: vw_order_master
-- -----------------------------------------------------------------------
-- Purpose: Single source of truth for order-level data.
--   Joins orders + customers + reviews.
--   Adds computed columns: delivery_days, is_delivery_delayed.
--   Use as base for any order-level reporting query.
-- =====================================================================
CREATE OR REPLACE VIEW vw_order_master AS
SELECT
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    -- Computed: actual delivery duration in days
    DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)  AS delivery_days,
    -- Computed: 1 if late, 0 if on time or early
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1
        ELSE 0
    END AS is_delivery_delayed,
    r.review_score
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
LEFT JOIN order_reviews r ON o.order_id = r.order_id;

-- Quick test:
-- SELECT * FROM vw_order_master WHERE order_status = 'delivered' LIMIT 5;


-- =====================================================================
-- 5.2 View: vw_order_item_details
-- -----------------------------------------------------------------------
-- Purpose: Item-level revenue view with English category names.
--   Joins order_items + products + category translation + sellers.
--   Use for category/seller revenue reports.
-- =====================================================================
CREATE OR REPLACE VIEW vw_order_item_details AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    COALESCE(t.product_category_name_english, p.product_category_name, 'Other') AS category_english,
    oi.seller_id,
    s.seller_state,
    s.seller_city,
    oi.price,
    oi.freight_value,
    (oi.price + oi.freight_value)  AS total_item_cost
FROM order_items oi
JOIN products p    ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t
       ON p.product_category_name = t.product_category_name
JOIN sellers s     ON oi.seller_id = s.seller_id;

-- Quick test:
-- SELECT category_english, ROUND(SUM(price),2) AS gmv
-- FROM vw_order_item_details GROUP BY category_english ORDER BY gmv DESC LIMIT 5;


-- =====================================================================
-- 5.3 Materialized Table: rfm_customer_segments
-- -----------------------------------------------------------------------
-- Purpose: Save RFM result permanently so it can be:
--   - Joined with other tables without re-running the heavy query
--   - Exported to Power BI / Tableau / Python for visualization
--
-- NOTE: Views cannot use window functions like NTILE reliably in all
--   MySQL versions, so we materialize this as a real table.
-- =====================================================================

-- Drop if re-running
DROP TABLE IF EXISTS rfm_customer_segments;

CREATE TABLE rfm_customer_segments AS
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
        NTILE(4) OVER (ORDER BY recency_days DESC)    AS r_score,
        CASE WHEN frequency_orders > 1 THEN 4 ELSE 1 END AS f_score,
        NTILE(4) OVER (ORDER BY monetary_spend ASC)   AS m_score
    FROM customer_rfm_raw
)
SELECT
    customer_unique_id,
    recency_days,
    frequency_orders,
    monetary_spend,
    r_score,
    f_score,
    m_score,
    CONCAT(r_score, f_score, m_score) AS rfm_code,
    CASE
        WHEN r_score >= 3 AND f_score = 4 AND m_score >= 3 THEN 'Champions'
        WHEN r_score >= 3 AND f_score = 4                  THEN 'Loyal Customers'
        WHEN r_score >= 3 AND f_score = 1 AND m_score >= 3 THEN 'Promising High-Spenders'
        WHEN r_score = 1  AND f_score = 4                  THEN 'Cant Lose Them (At Risk)'
        WHEN r_score = 1  AND m_score = 1                  THEN 'Lost / Churned'
        ELSE 'Standard One-Time Buyers'
    END AS customer_segment
FROM rfm_scores;

-- Add index for fast lookups
ALTER TABLE rfm_customer_segments ADD PRIMARY KEY (customer_unique_id);
CREATE INDEX idx_rfm_segment ON rfm_customer_segments(customer_segment);

-- Quick test:
-- SELECT customer_segment, COUNT(*) AS cnt, ROUND(AVG(monetary_spend),2) AS avg_spend
-- FROM rfm_customer_segments GROUP BY customer_segment ORDER BY cnt DESC;


-- =====================================================================
-- 5.4 Materialized Table: cohort_retention
-- -----------------------------------------------------------------------
-- Purpose: Save cohort retention counts permanently.
--   Useful for trend charts in Python/Power BI without re-running
--   the expensive cohort CTE every time.
-- =====================================================================

DROP TABLE IF EXISTS cohort_retention;

CREATE TABLE cohort_retention AS
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
)
SELECT
    cohort_month,
    MAX(CASE WHEN month_index = 0  THEN active_users ELSE 0 END) AS month_0_base,
    MAX(CASE WHEN month_index = 1  THEN active_users ELSE 0 END) AS month_1,
    MAX(CASE WHEN month_index = 2  THEN active_users ELSE 0 END) AS month_2,
    MAX(CASE WHEN month_index = 3  THEN active_users ELSE 0 END) AS month_3,
    MAX(CASE WHEN month_index = 6  THEN active_users ELSE 0 END) AS month_6,
    MAX(CASE WHEN month_index = 12 THEN active_users ELSE 0 END) AS month_12,
    -- Retention rate columns (%) — ready for charting
    ROUND(MAX(CASE WHEN month_index = 1  THEN active_users ELSE 0 END) * 100.0
          / NULLIF(MAX(CASE WHEN month_index = 0 THEN active_users ELSE 0 END), 0), 2) AS retention_m1_pct,
    ROUND(MAX(CASE WHEN month_index = 3  THEN active_users ELSE 0 END) * 100.0
          / NULLIF(MAX(CASE WHEN month_index = 0 THEN active_users ELSE 0 END), 0), 2) AS retention_m3_pct,
    ROUND(MAX(CASE WHEN month_index = 6  THEN active_users ELSE 0 END) * 100.0
          / NULLIF(MAX(CASE WHEN month_index = 0 THEN active_users ELSE 0 END), 0), 2) AS retention_m6_pct
FROM cohort_table
WHERE cohort_month BETWEEN '2017-01' AND '2018-01'
GROUP BY cohort_month
ORDER BY cohort_month;

-- Add primary key
ALTER TABLE cohort_retention ADD PRIMARY KEY (cohort_month);

-- Quick test:
-- SELECT * FROM cohort_retention;


-- =====================================================================
-- 5.5 Indexing Strategy — Faster joins on all analysis queries
-- -----------------------------------------------------------------------
-- Run once after data import. These indexes prevent full table scans
-- on the most frequently joined columns.
-- =====================================================================

-- Orders
CREATE INDEX IF NOT EXISTS idx_orders_customer_id    ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_status         ON orders(order_status);
CREATE INDEX IF NOT EXISTS idx_orders_purchase_date  ON orders(order_purchase_timestamp);

-- Customers
CREATE INDEX IF NOT EXISTS idx_customers_unique_id   ON customers(customer_unique_id);
CREATE INDEX IF NOT EXISTS idx_customers_state        ON customers(customer_state);

-- Order Items
CREATE INDEX IF NOT EXISTS idx_items_order_id        ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_items_product_id      ON order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_items_seller_id       ON order_items(seller_id);

-- Payments & Reviews
CREATE INDEX IF NOT EXISTS idx_payments_order_id     ON order_payments(order_id);
CREATE INDEX IF NOT EXISTS idx_reviews_order_id      ON order_reviews(order_id);

-- Products
CREATE INDEX IF NOT EXISTS idx_products_category     ON products(product_category_name);

-- =====================================================================
-- Verify all views and tables created successfully
-- =====================================================================
SHOW FULL TABLES WHERE Table_type = 'VIEW';
SHOW TABLES LIKE 'rfm_%';
SHOW TABLES LIKE 'cohort_%';
