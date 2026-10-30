-- Olist star schema (MySQL)
CREATE DATABASE IF NOT EXISTS olist;
USE olist;

-- Drop in reverse dependency order so the script can be re-run
DROP TABLE IF EXISTS fact_order_items;
DROP TABLE IF EXISTS dim_customer;
DROP TABLE IF EXISTS dim_seller;
DROP TABLE IF EXISTS dim_product;
DROP TABLE IF EXISTS dim_date;

-- ---------- Dimensions ----------
CREATE TABLE dim_customer (
    customer_id        CHAR(32) PRIMARY KEY,   -- changes with every order
    customer_unique_id CHAR(32) NOT NULL,      -- identifies the real person
    zip_code_prefix    VARCHAR(5),             -- text so leading zeros survive
    city               VARCHAR(100),
    state              CHAR(2)
);

CREATE TABLE dim_seller (
    seller_id        CHAR(32) PRIMARY KEY,
    zip_code_prefix  VARCHAR(5),
    city             VARCHAR(100),
    state            CHAR(2)
);

CREATE TABLE dim_product (
    product_id        CHAR(32) PRIMARY KEY,
    category_name_pt  VARCHAR(100),
    category_name_en  VARCHAR(100),            -- translated at load time
    weight_g          INT,
    length_cm         INT,
    height_cm         INT,
    width_cm          INT
);

CREATE TABLE dim_date (
    date_id  DATE PRIMARY KEY,
    year     SMALLINT,
    month    TINYINT,
    day      TINYINT,
    weekday  TINYINT                           -- 0 = Monday
);

-- ---------- Fact table: one row per item sold ----------
CREATE TABLE fact_order_items (
    order_id             CHAR(32) NOT NULL,
    order_item_id        INT NOT NULL,
    customer_id          CHAR(32) NOT NULL,
    product_id           CHAR(32) NOT NULL,
    seller_id            CHAR(32) NOT NULL,
    purchase_date        DATE NOT NULL,
    order_status         VARCHAR(20),
    price                DECIMAL(10,2),
    freight_value        DECIMAL(10,2),
    delivery_days        INT,                  -- NULL if never delivered
    delivery_delay_days  INT,                  -- delivered minus estimated; >0 = late
    PRIMARY KEY (order_id, order_item_id),
    FOREIGN KEY (customer_id)   REFERENCES dim_customer(customer_id),
    FOREIGN KEY (product_id)    REFERENCES dim_product(product_id),
    FOREIGN KEY (seller_id)     REFERENCES dim_seller(seller_id),
    FOREIGN KEY (purchase_date) REFERENCES dim_date(date_id)
);