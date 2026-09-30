USE olist;

-- =====================================================================
-- 0. Repeat customer rate (delivered orders only)
-- =====================================================================
CREATE OR REPLACE VIEW vw_repeat_customer_rate AS
SELECT COUNT(*) AS unique_customers,
       SUM(order_count > 1) AS repeat_customers,
       ROUND(SUM(order_count > 1) * 100.0 / COUNT(*), 2) AS repeat_pct
FROM (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS order_count
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
) t;

SELECT * FROM vw_repeat_customer_rate;

-- =====================================================================
-- 2.1 Top-line business summary (delivered orders)
-- =====================================================================
CREATE OR REPLACE VIEW vw_business_summary AS
SELECT
    COUNT(DISTINCT o.order_id)                                   AS total_delivered_orders,
    COUNT(DISTINCT c.customer_unique_id)                         AS total_unique_buyers,
    COUNT(DISTINCT oi.seller_id)                                 AS active_sellers,
    ROUND(SUM(oi.price), 2)                                      AS total_item_gmv,
    ROUND(SUM(oi.freight_value), 2)                              AS total_freight,
    ROUND(SUM(oi.price + oi.freight_value), 2)                   AS total_gross_revenue,
    ROUND(SUM(oi.price) / COUNT(DISTINCT o.order_id), 2)         AS avg_order_value,
    ROUND(COUNT(oi.order_item_id) / COUNT(DISTINCT o.order_id), 2) AS avg_items_per_order
FROM orders o
JOIN customers c   ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered';

SELECT * FROM vw_business_summary;

-- =====================================================================
-- 2.2 Payment method breakdown
-- =====================================================================
CREATE OR REPLACE VIEW vw_payment_breakdown AS
SELECT
    payment_type,
    COUNT(order_id)                                                              AS transaction_count,
    ROUND(COUNT(order_id) * 100.0 / SUM(COUNT(order_id)) OVER (), 2)             AS transaction_share_pct,
    ROUND(SUM(payment_value), 2)                                                 AS total_payment_value,
    ROUND(SUM(payment_value) * 100.0 / SUM(SUM(payment_value)) OVER (), 2)       AS revenue_share_pct,
    ROUND(AVG(payment_installments), 1)                                          AS avg_installments,
    ROUND(AVG(payment_value), 2)                                                 AS avg_ticket_size
FROM order_payments
GROUP BY payment_type
ORDER BY total_payment_value DESC;

SELECT * FROM vw_payment_breakdown;

-- =====================================================================
-- 2.3 Top 10 states by revenue
-- =====================================================================
CREATE OR REPLACE VIEW vw_state_revenue AS
SELECT
    c.customer_state,
    COUNT(DISTINCT c.customer_unique_id)        AS unique_customers,
    COUNT(DISTINCT o.order_id)                  AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2)  AS total_revenue,
    ROUND(AVG(oi.freight_value), 2)             AS avg_freight_paid
FROM orders o
JOIN customers c    ON o.customer_id = c.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY total_revenue DESC;

SELECT * FROM vw_state_revenue LIMIT 10;

-- =====================================================================
-- 3.1 Month-on-month revenue growth
-- Note: first months (2016) and last months (Sep-Oct 2018) are partial or
-- very small, so ignore their growth % in your findings.
-- =====================================================================
CREATE OR REPLACE VIEW vw_monthly_revenue_growth AS
WITH monthly_sales AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
        COUNT(DISTINCT o.order_id)                       AS total_orders,
        ROUND(SUM(oi.price + oi.freight_value), 2)       AS monthly_revenue
    FROM orders o
    JOIN order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
)
SELECT
    order_month,
    total_orders,
    monthly_revenue,
    LAG(monthly_revenue, 1) OVER (ORDER BY order_month) AS prev_month_revenue,
    ROUND(
        (monthly_revenue - LAG(monthly_revenue, 1) OVER (ORDER BY order_month))
        * 100.0 / LAG(monthly_revenue, 1) OVER (ORDER BY order_month), 2
    ) AS mom_growth_pct
FROM monthly_sales
ORDER BY order_month;

SELECT * FROM vw_monthly_revenue_growth;

-- =====================================================================
-- 3.2 Top product categories by revenue (delivered orders)
-- Review score is averaged per order first, so item rows are not duplicated.
-- =====================================================================
CREATE OR REPLACE VIEW vw_category_revenue AS
SELECT
    COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown') AS category_english,
    COUNT(DISTINCT oi.order_id)  AS total_orders,
    COUNT(oi.order_item_id)      AS total_units_sold,
    ROUND(SUM(oi.price), 2)      AS total_sales_value,
    ROUND(AVG(oi.price), 2)      AS avg_item_price,
    ROUND(AVG(r.review_score), 2) AS avg_customer_rating
FROM order_items oi
JOIN orders o   ON oi.order_id = o.order_id
JOIN products p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t
       ON p.product_category_name = t.product_category_name
LEFT JOIN (
    SELECT order_id, AVG(review_score) AS review_score
    FROM order_reviews
    GROUP BY order_id
) r ON oi.order_id = r.order_id
WHERE o.order_status = 'delivered'
GROUP BY category_english
ORDER BY total_sales_value DESC;

SELECT * FROM vw_category_revenue LIMIT 10;

-- =====================================================================
-- 3.3 Delivery lead time and delay rate by state
-- =====================================================================
CREATE OR REPLACE VIEW vw_delivery_by_state AS
SELECT
    c.customer_state,
    COUNT(o.order_id) AS delivered_orders,
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1) AS avg_delivery_days,
    ROUND(AVG(DATEDIFF(o.order_estimated_delivery_date, o.order_purchase_timestamp)), 1) AS avg_estimated_days,
    SUM(o.order_delivered_customer_date > o.order_estimated_delivery_date)               AS delayed_orders,
    ROUND(SUM(o.order_delivered_customer_date > o.order_estimated_delivery_date) * 100.0
          / COUNT(o.order_id), 2)                                                        AS delay_rate_pct
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY delay_rate_pct DESC;

SELECT * FROM vw_delivery_by_state;

-- =====================================================================
-- 3.4 Impact of delivery delay on review scores
-- =====================================================================
CREATE OR REPLACE VIEW vw_delay_review_impact AS
SELECT
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'Delayed Delivery'
        ELSE 'On-Time / Early Delivery'
    END AS delivery_performance,
    COUNT(r.review_id)                                                                   AS total_reviews,
    ROUND(AVG(r.review_score), 2)                                                        AS avg_review_score,
    ROUND(SUM(r.review_score = 1) * 100.0 / COUNT(r.review_id), 2)                       AS pct_1_star,
    ROUND(SUM(r.review_score = 5) * 100.0 / COUNT(r.review_id), 2)                       AS pct_5_star
FROM orders o
JOIN order_reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_performance;

SELECT * FROM vw_delay_review_impact;