USE olist;

CREATE INDEX  idx_orders_purchase_date  ON orders(order_purchase_timestamp);
CREATE INDEX  idx_customers_unique_id   ON customers(customer_unique_id);
CREATE INDEX  idx_items_product_id      ON order_items(product_id);
CREATE INDEX  idx_items_seller_id       ON order_items(seller_id);
CREATE INDEX  idx_payments_order_id     ON order_payments(order_id);
CREATE INDEX  idx_reviews_order_id      ON order_reviews(order_id);
CREATE INDEX  idx_products_category     ON products(product_category_name);
CREATE INDEX  idx_translation_category  ON product_category_name_translation(product_category_name);


-- =====================================================================
-- 1.2 Duplicate orders check — saved as view
-- =====================================================================
CREATE OR REPLACE VIEW vw_duplicate_orders AS
SELECT order_id, COUNT(*) AS occurrence_count
FROM orders
GROUP BY order_id
HAVING COUNT(*) > 1;

-- If this view returns 0 rows = no duplicates (good!)
SELECT COUNT(*) AS duplicate_order_count FROM vw_duplicate_orders;


-- =====================================================================
-- 1.2b Customer uniqueness audit — saved as view
-- =====================================================================
CREATE OR REPLACE VIEW vw_customer_uniqueness_audit AS
SELECT
    COUNT(customer_id)                AS total_order_customers,
    COUNT(DISTINCT customer_unique_id) AS total_unique_humans,
    COUNT(customer_id) - COUNT(DISTINCT customer_unique_id) AS repeat_customer_transactions
FROM customers;

SELECT * FROM vw_customer_uniqueness_audit;


-- =====================================================================
-- 1.3 Order status & missing delivery dates audit — saved as view
-- =====================================================================
CREATE OR REPLACE VIEW vw_order_status_audit AS
SELECT
    order_status,
    COUNT(*)                                              AS total_orders,
    SUM(order_delivered_customer_date IS NULL)            AS missing_delivery_date_count,
    ROUND(SUM(order_delivered_customer_date IS NULL) * 100.0 / COUNT(*), 2) AS pct_missing
FROM orders
GROUP BY order_status
ORDER BY total_orders DESC;

SELECT * FROM vw_order_status_audit;


-- =====================================================================
-- 1.4 Date boundaries — saved as view
-- =====================================================================
CREATE OR REPLACE VIEW vw_date_boundaries AS
SELECT
    MIN(order_purchase_timestamp) AS earliest_purchase,
    MAX(order_purchase_timestamp) AS latest_purchase,
    TIMESTAMPDIFF(MONTH, MIN(order_purchase_timestamp), MAX(order_purchase_timestamp)) AS active_months_span
FROM orders;

SELECT * FROM vw_date_boundaries;