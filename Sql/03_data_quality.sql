CREATE INDEX idx_orders_purchase_date ON orders(order_purchase_timestamp);
CREATE INDEX idx_customers_unique_id ON customers(customer_unique_id);
CREATE INDEX idx_items_product_id ON order_items(product_id);
CREATE INDEX idx_items_seller_id ON order_items(seller_id);
CREATE INDEX idx_payments_order_id ON order_payments(order_id);
CREATE INDEX idx_reviews_order_id ON order_reviews(order_id);
CREATE INDEX idx_products_category ON products(product_category_name);
CREATE INDEX idx_translation_category ON product_category_name_translation(product_category_name);


-- 1.2 Duplicate check and unique customers
SELECT order_id, COUNT(*) FROM orders GROUP BY order_id HAVING COUNT(*) > 1;

SELECT COUNT(customer_id) AS total_order_customers,
       COUNT(DISTINCT customer_unique_id) AS total_unique_humans
FROM customers;

-- 1.3 Order status and missing delivery dates
SELECT order_status,
       COUNT(*) AS total_orders,
       SUM(order_delivered_customer_date IS NULL) AS missing_delivery_date_count,
       ROUND(SUM(order_delivered_customer_date IS NULL) * 100.0 / COUNT(*), 2) AS pct_missing
FROM orders
GROUP BY order_status
ORDER BY total_orders DESC;

-- 1.4 Date range
SELECT MIN(order_purchase_timestamp) AS earliest_purchase,
       MAX(order_purchase_timestamp) AS latest_purchase
FROM orders;