-- 02_data_import.sql
-- Olist E-Commerce Analysis: load CSV files into MySQL tables
-- Change the folder path below if your CSVs are stored somewhere else.
-- If a table imports 0 rows, replace '\n' with '\r\n' for that table.

USE olist;
SET GLOBAL local_infile = 1;

-- Import order matters: customers before orders (foreign key)

-- 1. customers
LOAD DATA LOCAL INFILE 'C:/Users/ACER/Desktop/ecommerce-sales-analysis/ecommerce-sales-analysis/Data/raw_data/olist_customers_dataset.csv'
INTO TABLE customers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 2. orders (empty dates become NULL)
LOAD DATA LOCAL INFILE 'C:/Users/ACER/Desktop/ecommerce-sales-analysis/ecommerce-sales-analysis/Data/raw_data/olist_orders_dataset.csv'
INTO TABLE orders
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(order_id, customer_id, order_status, order_purchase_timestamp,
 @approved, @carrier, @delivered, order_estimated_delivery_date)
SET order_approved_at = NULLIF(@approved, ''),
    order_delivered_carrier_date = NULLIF(@carrier, ''),
    order_delivered_customer_date = NULLIF(@delivered, '');

-- 3. products (empty numeric values become NULL)
LOAD DATA LOCAL INFILE 'C:/Users/ACER/Desktop/ecommerce-sales-analysis/ecommerce-sales-analysis/Data/raw_data/olist_products_dataset.csv'
INTO TABLE products
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(product_id, product_category_name, @nl, @dl, @pq, @w, @l, @h, @wd)
SET product_name_lenght = NULLIF(@nl,''),
    product_description_lenght = NULLIF(@dl,''),
    product_photos_qty = NULLIF(@pq,''),
    product_weight_g = NULLIF(@w,''),
    product_length_cm = NULLIF(@l,''),
    product_height_cm = NULLIF(@h,''),
    product_width_cm = NULLIF(@wd,'');

-- 4. sellers
LOAD DATA LOCAL INFILE 'C:/Users/ACER/Desktop/ecommerce-sales-analysis/ecommerce-sales-analysis/Data/raw_data/olist_sellers_dataset.csv'
INTO TABLE sellers
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 5. order_items
LOAD DATA LOCAL INFILE 'C:/Users/ACER/Desktop/ecommerce-sales-analysis/ecommerce-sales-analysis/Data/raw_data/olist_order_items_dataset.csv'
INTO TABLE order_items
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 6. order_payments
LOAD DATA LOCAL INFILE 'C:/Users/ACER/Desktop/ecommerce-sales-analysis/ecommerce-sales-analysis/Data/raw_data/olist_order_payments_dataset.csv'
INTO TABLE order_payments
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 7. order_reviews
LOAD DATA LOCAL INFILE 'C:/Users/ACER/Desktop/ecommerce-sales-analysis/ecommerce-sales-analysis/Data/raw_data/olist_order_reviews_dataset.csv'
INTO TABLE order_reviews
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 8. product_category_name_translation
LOAD DATA LOCAL INFILE 'C:/Users/ACER/Desktop/ecommerce-sales-analysis/ecommerce-sales-analysis/Data/raw_data/product_category_name_translation.csv'
INTO TABLE product_category_name_translation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- 9. geolocation (largest file, ~1M rows)
LOAD DATA LOCAL INFILE 'C:/Users/ACER/Desktop/ecommerce-sales-analysis/ecommerce-sales-analysis/Data/raw_data/olist_geolocation_dataset.csv'
INTO TABLE geolocation
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

-- -----------------------------------------------------------------------
-- Row count audit — view returns live row counts from all raw tables
-- -----------------------------------------------------------------------
CREATE OR REPLACE VIEW vw_row_count_audit AS
SELECT 'customers'   AS table_name, COUNT(*) AS total_rows FROM customers
UNION ALL SELECT 'orders',         COUNT(*) FROM orders
UNION ALL SELECT 'order_items',    COUNT(*) FROM order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL SELECT 'order_reviews',  COUNT(*) FROM order_reviews
UNION ALL SELECT 'products',       COUNT(*) FROM products
UNION ALL SELECT 'sellers',        COUNT(*) FROM sellers
UNION ALL SELECT 'translation',    COUNT(*) FROM product_category_name_translation
UNION ALL SELECT 'geolocation',    COUNT(*) FROM geolocation;

-- Quick verify:
SELECT * FROM vw_row_count_audit;
