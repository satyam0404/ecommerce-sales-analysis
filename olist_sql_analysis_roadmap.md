# 🛒 Brazilian E-Commerce (Olist) — End-to-End SQL Analysis Roadmap & Query Guide

This comprehensive roadmap guides you through analyzing the **Olist Brazilian E-Commerce Public Dataset (9 tables)** loaded in **MySQL**. It covers data validation, exploratory data analysis (EDA), core business metrics, advanced customer/seller analytics (Cohort, RFM, Pareto), production SQL views, and portfolio presentation.

---

## 📑 Table of Contents
1. [Dataset Architecture & ER Diagram](#1-dataset-architecture--er-diagram)
2. [Phase 1: Data Sanity & Quality Validation](#2-phase-1-data-sanity--quality-validation)
3. [Phase 2: Exploratory Data Analysis (EDA)](#3-phase-2-exploratory-data-analysis-eda)
4. [Phase 3: Core E-Commerce KPIs & Logistics](#4-phase-3-core-e-commerce-kpis--logistics)
5. [Phase 4: Advanced SQL (Cohorts, RFM, Pareto)](#5-phase-4-advanced-sql-cohorts-rfm-pareto)
6. [Phase 5: Production Views & Performance Tuning](#6-phase-5-production-views--performance-tuning)
7. [Phase 6: Portfolio & GitHub Presentation Guide](#7-phase-6-portfolio--github-presentation-guide)

---

## 1. Dataset Architecture & ER Diagram

The Olist dataset consists of 9 interrelated tables tracking orders from purchase to delivery, seller fulfillment, product metadata, customer reviews, and payments.

```mermaid
erDiagram
    CUSTOMERS ||--o{ ORDERS : "places"
    ORDERS ||--o{ ORDER_ITEMS : "contains"
    ORDERS ||--o{ ORDER_PAYMENTS : "paid via"
    ORDERS ||--o{ ORDER_REVIEWS : "reviewed by"
    ORDER_ITEMS }o--|| PRODUCTS : "identifies"
    ORDER_ITEMS }o--|| SELLERS : "fulfilled by"
    PRODUCTS }o--|| CATEGORY_TRANSLATION : "translated into"
    CUSTOMERS }o--|| GEOLOCATION : "located at"
    SELLERS }o--|| GEOLOCATION : "located at"

    CUSTOMERS {
        string customer_id PK
        string customer_unique_id
        string customer_zip_code_prefix
        string customer_city
        string customer_state
    }

    ORDERS {
        string order_id PK
        string customer_id FK
        string order_status
        datetime order_purchase_timestamp
        datetime order_approved_at
        datetime order_delivered_carrier_date
        datetime order_delivered_customer_date
        datetime order_estimated_delivery_date
    }

    ORDER_ITEMS {
        string order_id PK_FK
        int order_item_id PK
        string product_id FK
        string seller_id FK
        datetime shipping_limit_date
        decimal price
        decimal freight_value
    }

    ORDER_PAYMENTS {
        string order_id PK_FK
        int payment_sequential PK
        string payment_type
        int payment_installments
        decimal payment_value
    }

    ORDER_REVIEWS {
        string review_id PK
        string order_id FK
        int review_score
        string review_comment_title
        string review_comment_message
        datetime review_creation_date
        datetime review_answer_timestamp
    }

    PRODUCTS {
        string product_id PK
        string product_category_name FK
        int product_weight_g
        int product_length_cm
        int product_height_cm
        int product_width_cm
    }

    SELLERS {
        string seller_id PK
        string seller_zip_code_prefix
        string seller_city
        string seller_state
    }

    CATEGORY_TRANSLATION {
        string product_category_name PK
        string product_category_name_english
    }

    GEOLOCATION {
        string geolocation_zip_code_prefix
        decimal geolocation_lat
        decimal geolocation_lng
        string geolocation_city
        string geolocation_state
    }
```

> [!IMPORTANT]
> **Key Distinctions in Olist Data:**
> - `customer_id`: Assigned per order (changes with every purchase).
> - `customer_unique_id`: Identifies the actual unique human customer across multiple transactions.
> - An order can have multiple items (`order_item_id` 1, 2, 3...) sold by different sellers and paid with multiple payment types (`payment_sequential` 1, 2...).

---

## 2. Phase 1: Data Sanity & Quality Validation

Before reporting any business figures, run data integrity audits to verify row counts, primary key constraints, and date inconsistencies.

### 1.1 Row Count & Volume Audit
Verify that data imported into MySQL matches expected source volumes.

```sql
SELECT 'customers' AS table_name, COUNT(*) AS total_rows FROM olist_customers_dataset
UNION ALL
SELECT 'orders', COUNT(*) FROM olist_orders_dataset
UNION ALL
SELECT 'order_items', COUNT(*) FROM olist_order_items_dataset
UNION ALL
SELECT 'order_payments', COUNT(*) FROM olist_order_payments_dataset
UNION ALL
SELECT 'order_reviews', COUNT(*) FROM olist_order_reviews_dataset
UNION ALL
SELECT 'products', COUNT(*) FROM olist_products_dataset
UNION ALL
SELECT 'sellers', COUNT(*) FROM olist_sellers_dataset
UNION ALL
SELECT 'category_translation', COUNT(*) FROM product_category_name_translation
UNION ALL
SELECT 'geolocation', COUNT(*) FROM olist_geolocation_dataset;
```

### 1.2 Primary Key & Duplicate Check
Confirm that primary entities do not have duplicate entries.

```sql
-- Check for duplicate order IDs
SELECT order_id, COUNT(*) AS occurrence_count
FROM olist_orders_dataset
GROUP BY order_id
HAVING COUNT(*) > 1;

-- Compare total customer records vs distinct unique customers
SELECT 
    COUNT(customer_id) AS total_order_customers,
    COUNT(DISTINCT customer_unique_id) AS total_unique_humans,
    COUNT(customer_id) - COUNT(DISTINCT customer_unique_id) AS repeat_customer_transactions
FROM olist_customers_dataset;
```

### 1.3 Order Status & Missing Delivery Dates Audit
Inspect order states and find any anomalies (e.g., status is `delivered` but `order_delivered_customer_date` is NULL).

```sql
SELECT 
    order_status,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) AS missing_delivery_date_count,
    ROUND(SUM(CASE WHEN order_delivered_customer_date IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS pct_missing
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY total_orders DESC;
```

### 1.4 Date Boundaries Sanity Check
Inspect minimum and maximum purchase dates to establish timeline boundaries.

```sql
SELECT 
    MIN(order_purchase_timestamp) AS earliest_purchase,
    MAX(order_purchase_timestamp) AS latest_purchase,
    TIMESTAMPDIFF(MONTH, MIN(order_purchase_timestamp), MAX(order_purchase_timestamp)) AS active_months_span
FROM olist_orders_dataset;
```

---

## 3. Phase 2: Exploratory Data Analysis (EDA)

Establish baseline metrics and explore payment preferences, geographical clusters, and order structures.

### 2.1 Top-Line Business Summary
Calculate total gross merchandise value (GMV), freight revenue, total orders, and average units per basket.

```sql
SELECT 
    COUNT(DISTINCT o.order_id) AS total_delivered_orders,
    COUNT(DISTINCT c.customer_unique_id) AS total_unique_buyers,
    COUNT(DISTINCT oi.seller_id) AS active_sellers,
    ROUND(SUM(oi.price), 2) AS total_item_gmv,
    ROUND(SUM(oi.freight_value), 2) AS total_freight_revenue,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_gross_revenue,
    ROUND(SUM(oi.price) / COUNT(DISTINCT o.order_id), 2) AS average_order_value_aov,
    ROUND(COUNT(oi.order_item_id) * 1.0 / COUNT(DISTINCT o.order_id), 2) AS avg_items_per_order
FROM olist_orders_dataset o
JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered';
```

### 2.2 Payment Method Breakdown & Installments
Analyze how Brazilian customers pay (Credit Cards vs Boleto Bancário) and how installment options correlate with transaction sizes.

```sql
SELECT 
    payment_type,
    COUNT(order_id) AS transaction_count,
    ROUND(COUNT(order_id) * 100.0 / SUM(COUNT(order_id)) OVER (), 2) AS transaction_share_pct,
    ROUND(SUM(payment_value), 2) AS total_payment_value,
    ROUND(SUM(payment_value) * 100.0 / SUM(SUM(payment_value)) OVER (), 2) AS revenue_share_pct,
    ROUND(AVG(payment_installments), 1) AS avg_installments,
    ROUND(AVG(payment_value), 2) AS avg_ticket_size
FROM olist_order_payments_dataset
GROUP BY payment_type
ORDER BY total_payment_value DESC;
```

### 2.3 Customer Geographical Distribution
Identify the top revenue-generating Brazilian states and cities.

```sql
SELECT 
    c.customer_state,
    COUNT(DISTINCT c.customer_unique_id) AS unique_customers,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_revenue,
    ROUND(AVG(oi.freight_value), 2) AS avg_freight_paid
FROM olist_orders_dataset o
JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY total_revenue DESC
LIMIT 10;
```

---

## 4. Phase 3: Core E-Commerce KPIs & Logistics

Deep dive into revenue trends, product category winners, and delivery logistics (Olist's biggest business driver).

### 3.1 Month-on-Month (MoM) Sales Growth
Track sales velocity and identify high-growth periods (such as November Black Friday).

```sql
WITH monthly_sales AS (
    SELECT 
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month,
        COUNT(DISTINCT o.order_id) AS total_orders,
        ROUND(SUM(oi.price + oi.freight_value), 2) AS monthly_revenue
    FROM olist_orders_dataset o
    JOIN olist_order_items_dataset oi ON o.order_id = oi.order_id
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
        * 100.0 / LAG(monthly_revenue, 1) OVER (ORDER BY order_month), 
        2
    ) AS mom_growth_percentage
FROM monthly_sales
ORDER BY order_month;
```

### 3.2 Top 10 Product Categories by Revenue
Join the English translation table to identify category leaders.

```sql
SELECT 
    COALESCE(t.product_category_name_english, p.product_category_name, 'Unknown') AS category_english,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    COUNT(oi.order_item_id) AS total_units_sold,
    ROUND(SUM(oi.price), 2) AS total_sales_value,
    ROUND(AVG(oi.price), 2) AS avg_item_price,
    ROUND(AVG(r.review_score), 2) AS avg_customer_rating
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
LEFT JOIN olist_order_reviews_dataset r ON oi.order_id = r.order_id
GROUP BY category_english
ORDER BY total_sales_value DESC
LIMIT 10;
```

### 3.3 Logistics: Delivery Lead Time & Delay Rate by State
Measure the speed and reliability of fulfillment across Brazilian states.

```sql
SELECT 
    c.customer_state,
    COUNT(o.order_id) AS delivered_orders,
    -- Average delivery duration in days
    ROUND(AVG(DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp)), 1) AS avg_delivery_days,
    -- Average estimated delivery duration in days
    ROUND(AVG(DATEDIFF(o.order_estimated_delivery_date, o.order_purchase_timestamp)), 1) AS avg_estimated_days,
    -- Delayed deliveries count
    SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) AS delayed_orders,
    -- Percentage of delayed deliveries
    ROUND(
        SUM(CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END) * 100.0 / COUNT(o.order_id), 
        2
    ) AS delay_rate_pct
FROM olist_orders_dataset o
JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY delay_rate_pct DESC;
```

### 3.4 Impact of Delivery Delays on Customer Reviews
Correlate delivery performance with review scores (1-star vs 5-star ratings).

```sql
SELECT 
    CASE 
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'Delayed Delivery'
        ELSE 'On-Time / Early Delivery'
    END AS delivery_performance,
    COUNT(r.review_id) AS total_reviews,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    ROUND(SUM(CASE WHEN r.review_score = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(r.review_id), 2) AS pct_1_star_reviews,
    ROUND(SUM(CASE WHEN r.review_score = 5 THEN 1 ELSE 0 END) * 100.0 / COUNT(r.review_id), 2) AS pct_5_star_reviews
FROM olist_orders_dataset o
JOIN olist_order_reviews_dataset r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_performance;
```

---

## 5. Phase 4: Advanced SQL (Cohorts, RFM, Pareto)

These queries demonstrate mastery of Window Functions, CTEs, and business modeling.

### 4.1 Customer Cohort Retention Analysis
Track how groups of customers acquired in specific months make repeat purchases in subsequent months.

```sql
WITH customer_first_purchase AS (
    SELECT 
        c.customer_unique_id,
        MIN(DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')) AS cohort_month
    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
customer_orders AS (
    SELECT 
        c.customer_unique_id,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m') AS order_month
    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
),
cohort_table AS (
    SELECT 
        fp.cohort_month,
        co.order_month,
        TIMESTAMPDIFF(
            MONTH, 
            STR_TO_DATE(CONCAT(fp.cohort_month, '-01'), '%Y-%m-%d'),
            STR_TO_DATE(CONCAT(co.order_month, '-01'), '%Y-%m-%d')
        ) AS month_index,
        COUNT(DISTINCT fp.customer_unique_id) AS active_users
    FROM customer_first_purchase fp
    JOIN customer_orders co ON fp.customer_unique_id = co.customer_unique_id
    GROUP BY fp.cohort_month, co.order_month, month_index
)
SELECT 
    cohort_month,
    MAX(CASE WHEN month_index = 0 THEN active_users ELSE 0 END) AS month_0_base,
    MAX(CASE WHEN month_index = 1 THEN active_users ELSE 0 END) AS month_1,
    MAX(CASE WHEN month_index = 2 THEN active_users ELSE 0 END) AS month_2,
    MAX(CASE WHEN month_index = 3 THEN active_users ELSE 0 END) AS month_3,
    MAX(CASE WHEN month_index = 6 THEN active_users ELSE 0 END) AS month_6,
    MAX(CASE WHEN month_index = 12 THEN active_users ELSE 0 END) AS month_12
FROM cohort_table
WHERE cohort_month BETWEEN '2017-01' AND '2018-01'
GROUP BY cohort_month
ORDER BY cohort_month;
```

> [!NOTE]
> **Key Finding to Highlight in Portfolio:**
> Olist has a very low repeat customer rate (~3%). This is a key business insight: Olist operates primarily as a lead-generation discovery engine rather than a habitual replenishment marketplace.

### 4.2 Customer RFM Segmentation (Recency, Frequency, Monetary)
Score customers on **Recency** (last order days ago), **Frequency** (total orders placed), and **Monetary** (total spend).

```sql
WITH max_dataset_date AS (
    SELECT MAX(order_purchase_timestamp) AS reference_date FROM olist_orders_dataset
),
customer_rfm_raw AS (
    SELECT 
        c.customer_unique_id,
        DATEDIFF(ref.reference_date, MAX(o.order_purchase_timestamp)) AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency_orders,
        ROUND(SUM(p.payment_value), 2) AS monetary_spend
    FROM olist_orders_dataset o
    JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
    JOIN olist_order_payments_dataset p ON o.order_id = p.order_id
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
        NTILE(4) OVER (ORDER BY recency_days DESC) AS r_score,     -- Lower days = higher score
        CASE WHEN frequency_orders > 1 THEN 4 ELSE 1 END AS f_score, -- Skewed frequency
        NTILE(4) OVER (ORDER BY monetary_spend ASC) AS m_score     -- Higher spend = higher score
    FROM customer_rfm_raw
)
SELECT 
    customer_unique_id,
    recency_days,
    frequency_orders,
    monetary_spend,
    CONCAT(r_score, f_score, m_score) AS rfm_segment_code,
    CASE 
        WHEN r_score >= 3 AND f_score = 4 AND m_score >= 3 THEN 'Champions'
        WHEN r_score >= 3 AND f_score = 4 THEN 'Loyal Customers'
        WHEN r_score >= 3 AND f_score = 1 AND m_score >= 3 THEN 'Promising High-Spenders'
        WHEN r_score = 1 AND f_score = 4 THEN 'Can’t Lose Them (At Risk)'
        WHEN r_score = 1 AND m_score = 1 THEN 'Lost / Churned'
        ELSE 'Standard One-Time Buyers'
    END AS customer_segment
FROM rfm_scores
LIMIT 100;
```

### 4.3 Seller Pareto Analysis (80/20 Distribution)
Verify if the top 20% of sellers generate 80% of Olist's total marketplace revenue.

```sql
WITH seller_sales AS (
    SELECT 
        oi.seller_id,
        s.seller_state,
        ROUND(SUM(oi.price), 2) AS seller_gmv,
        COUNT(oi.order_item_id) AS units_sold
    FROM olist_order_items_dataset oi
    JOIN olist_sellers_dataset s ON oi.seller_id = s.seller_id
    GROUP BY oi.seller_id, s.seller_state
),
cumulative_sellers AS (
    SELECT 
        seller_id,
        seller_state,
        seller_gmv,
        units_sold,
        ROW_NUMBER() OVER (ORDER BY seller_gmv DESC) AS seller_rank,
        COUNT(*) OVER () AS total_sellers,
        SUM(seller_gmv) OVER (ORDER BY seller_gmv DESC) AS running_gmv,
        SUM(seller_gmv) OVER () AS grand_total_gmv
    FROM seller_sales
)
SELECT 
    seller_id,
    seller_state,
    seller_gmv,
    ROUND(seller_rank * 100.0 / total_sellers, 2) AS seller_percentile,
    ROUND(running_gmv * 100.0 / grand_total_gmv, 2) AS cumulative_revenue_pct
FROM cumulative_sellers
WHERE seller_rank IN (1, 10, 50, 100, 500, 1000) 
   OR ROUND(running_gmv * 100.0 / grand_total_gmv, 0) IN (20, 50, 80)
ORDER BY seller_rank;
```

---

## 6. Phase 5: Production Views & Performance Tuning

To make your project scalable and ready to connect with BI tools (Power BI, Tableau) or Python dashboards, encapsulate complex joins in SQL Views and index foreign keys.

### 6.1 Creating Production Views

#### View 1: Clean Order Master View
```sql
CREATE OR REPLACE VIEW vw_order_master AS
SELECT 
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days,
    CASE 
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 
        ELSE 0 
    END AS is_delivery_delayed,
    r.review_score
FROM olist_orders_dataset o
JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
LEFT JOIN olist_order_reviews_dataset r ON o.order_id = r.order_id;
```

#### View 2: Order Revenue & Item Details View
```sql
CREATE OR REPLACE VIEW vw_order_item_details AS
SELECT 
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    COALESCE(t.product_category_name_english, p.product_category_name, 'Other') AS category_english,
    oi.seller_id,
    s.seller_state,
    oi.price,
    oi.freight_value,
    (oi.price + oi.freight_value) AS total_item_cost
FROM olist_order_items_dataset oi
JOIN olist_products_dataset p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t ON p.product_category_name = t.product_category_name
JOIN olist_sellers_dataset s ON oi.seller_id = s.seller_id;
```

### 6.2 Indexing Strategy for Blazing-Fast Querying
Creating indexes on join keys avoids full table scans when running queries across multiple million-record tables.

```sql
-- Orders & Customers Indexes
CREATE INDEX idx_orders_customer_id ON olist_orders_dataset(customer_id);
CREATE INDEX idx_orders_purchase_date ON olist_orders_dataset(order_purchase_timestamp);
CREATE INDEX idx_customers_unique_id ON olist_customers_dataset(customer_unique_id);

-- Order Items Indexes
CREATE INDEX idx_items_order_id ON olist_order_items_dataset(order_id);
CREATE INDEX idx_items_product_id ON olist_order_items_dataset(product_id);
CREATE INDEX idx_items_seller_id ON olist_order_items_dataset(seller_id);

-- Payments & Reviews Indexes
CREATE INDEX idx_payments_order_id ON olist_order_payments_dataset(order_id);
CREATE INDEX idx_reviews_order_id ON olist_order_reviews_dataset(order_id);
```

---

## 7. Phase 6: Portfolio & GitHub Presentation Guide

When showcasing this project to hiring managers or on GitHub, organize your writeup into four standardized pillars for every query:

| Section | Description | Example from Olist |
| :--- | :--- | :--- |
| **1. Business Question** | What problem is management trying to solve? | *Why are customer reviews dropping in northern Brazilian states?* |
| **2. SQL Query** | Clean, formatted, commented SQL script. | *Logistics lead-time query joining orders, customers, and reviews.* |
| **3. Key Finding** | The specific numerical discovery. | *Deliveries to North/Northeast states take 24.8 days on average (42% delay rate), resulting in 1-star reviews in 38% of orders.* |
| **4. Actionable Recommendation**| Strategic business advice. | *Recommend onboarding regional 3PL fulfillment centers in Recife/Salvador rather than shipping exclusively from São Paulo.* |

### Recommended GitHub Repository Structure
```text
ecommerce-sales-analysis/
│
├── README.md                          # Executive project summary & findings
├── schema/
│   └── 01_table_creation.sql          # DDL scripts for all 9 tables
├── queries/
│   ├── 02_data_sanity_checks.sql      # Phase 1 queries
│   ├── 03_exploratory_data_analysis.sql # Phase 2 queries
│   ├── 04_ecommerce_kpis_logistics.sql  # Phase 3 queries
│   ├── 05_advanced_cohort_rfm.sql     # Phase 4 queries
│   └── 06_production_views.sql        # Phase 5 views & indexes
├── docs/
│   ├── olist_sql_analysis_roadmap.md  # Detailed methodology & roadmap
│   └── er_diagram.png                 # Database schema diagram
└── dashboards/                        # Optional Power BI / Tableau assets
```

---
*Created as part of the E-Commerce Sales Analysis Data Project.*
