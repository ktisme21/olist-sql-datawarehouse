-- Step 9, add covering indexes to speed up the queries
-- step 10, compare results with and without indexes using EXPLAIN ANALYZE
USE olist;

-- BASELINE: only the automatic foreign-key indexes exist.
-- Method: run EXPLAIN ANALYZE in front of each query 3 times in its own
-- script and record the top-line "actual time" (ms).

-- EXPERIMENT 1: covering index for revenue-by-state (query 2)
CREATE INDEX idx_fact_cust_price ON fact_order_items (customer_id, price);

-- EXPERIMENT 2: covering index for top-sellers (query 4)
CREATE INDEX idx_fact_seller_price ON fact_order_items (seller_id, price);

ANALYZE TABLE fact_order_items;

-- EXPERIMENT 3 (REJECTED): 3-column index for query 5. Gain was only ~7%,
-- not worth the extra storage and slower loads, so it was dropped.
-- CREATE INDEX idx_fact_cust_prod_price
--     ON fact_order_items (customer_id, product_id, price);
-- DROP INDEX idx_fact_cust_prod_price ON fact_order_items;

-- Inspect the indexes that remain
SHOW INDEX FROM fact_order_items;