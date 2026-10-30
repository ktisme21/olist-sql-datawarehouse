USE olist;

-- Sanity check: every revenue query below should add up to this total
-- (query 1 may be slightly lower because some products have no category).
SELECT ROUND(SUM(price), 2) AS total_revenue FROM fact_order_items;

-- NOTE: revenue here includes every order_status (including canceled).
-- Check with: SELECT order_status, COUNT(*) FROM fact_order_items GROUP BY order_status;

-- 1. Revenue by product category
SELECT p.category_name_en AS category, ROUND(SUM(f.price), 2) AS revenue
FROM fact_order_items f
JOIN dim_product p ON p.product_id = f.product_id
GROUP BY p.category_name_en
ORDER BY revenue DESC;

-- 2. Revenue by customer state
SELECT c.state, ROUND(SUM(f.price), 2) AS revenue
FROM fact_order_items f
JOIN dim_customer c ON c.customer_id = f.customer_id
GROUP BY c.state
ORDER BY revenue DESC;

-- 3. Monthly revenue trend
SELECT d.year, d.month, ROUND(SUM(f.price), 2) AS revenue
FROM fact_order_items f
JOIN dim_date d ON d.date_id = f.purchase_date
GROUP BY d.year, d.month
ORDER BY d.year, d.month;

-- 4. Top 5 sellers by revenue
SELECT s.seller_id, ROUND(SUM(f.price), 2) AS revenue
FROM fact_order_items f
JOIN dim_seller s ON s.seller_id = f.seller_id
GROUP BY s.seller_id
ORDER BY revenue DESC
LIMIT 5;

-- 5. Top 3 categories per state (window function)
WITH r AS (
  SELECT c.state, p.category_name_en AS category, SUM(f.price) AS revenue,
         ROW_NUMBER() OVER (PARTITION BY c.state ORDER BY SUM(f.price) DESC) AS rn
  FROM fact_order_items f
  JOIN dim_customer c ON c.customer_id = f.customer_id
  JOIN dim_product p ON p.product_id = f.product_id
  GROUP BY c.state, p.category_name_en
)
SELECT * FROM r WHERE rn <= 3;

-- 6. Delivery performance by state (delivered items only)
SELECT c.state,
       COUNT(DISTINCT f.order_id)                       AS delivered_orders,
       ROUND(AVG(f.delivery_days), 1)                   AS avg_delivery_days,
       ROUND(AVG(f.delivery_delay_days), 1)             AS avg_days_vs_estimate,
       ROUND(100 * AVG(f.delivery_delay_days > 0), 1)   AS pct_late
FROM fact_order_items f
JOIN dim_customer c ON c.customer_id = f.customer_id
WHERE f.delivery_days IS NOT NULL
GROUP BY c.state
ORDER BY avg_delivery_days DESC;

-- 7. Number of repeat customers (customer_unique_id with more than one order)
SELECT COUNT(*) AS repeat_customers
FROM (
    SELECT c.customer_unique_id
    FROM fact_order_items f
    JOIN dim_customer c ON c.customer_id = f.customer_id
    GROUP BY c.customer_unique_id
    HAVING COUNT(DISTINCT f.order_id) > 1
) t;