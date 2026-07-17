-- ── CREATE TABLES ────────────────────────────────────────────────

CREATE TABLE customers (
    customer_id   INT PRIMARY KEY,
    first_name    VARCHAR(100),
    last_name     VARCHAR(100),
    email         VARCHAR(200),
    phone         VARCHAR(50),
    city          VARCHAR(100),
    state         VARCHAR(10),
    country       VARCHAR(100),
    age           VARCHAR(10),       -- stored as text intentionally (messy)
    gender        VARCHAR(30),
    signup_date   VARCHAR(30),       -- stored as text intentionally (messy)
    segment       VARCHAR(30),
    prime_member  VARCHAR(10),
    total_spent   NUMERIC(12,2),
    total_orders  INT
);

CREATE TABLE sellers (
    seller_id    INT PRIMARY KEY,
    seller_name  VARCHAR(200),
    contact_name VARCHAR(100),
    email        VARCHAR(200),
    phone        VARCHAR(50),
    city         VARCHAR(100),
    state        VARCHAR(10),
    country      VARCHAR(100),
    avg_rating   NUMERIC(3,1),
    year_joined  INT
);

CREATE TABLE categories (
    category_id   INT PRIMARY KEY,
    category_name VARCHAR(100),
    description   TEXT,
    parent_cat_id INT REFERENCES categories(category_id)
);

CREATE TABLE products (
    product_id   INT PRIMARY KEY,
    product_name VARCHAR(300),
    category_id  INT REFERENCES categories(category_id),
    seller_id    INT REFERENCES sellers(seller_id),
    price        NUMERIC(10,2),
    cost_price   NUMERIC(10,2),
    stock_qty    INT,
    discount_pct NUMERIC(5,2),
    asin         VARCHAR(50),
    status       VARCHAR(20),
    weight_kg    NUMERIC(8,2),
    rating       NUMERIC(3,1),
    description  TEXT
);

CREATE TABLE orders (
    order_id       INT PRIMARY KEY,
    customer_id    INT REFERENCES customers(customer_id),
    order_date     VARCHAR(20),      -- text intentionally (messy)
    delivery_date  VARCHAR(20),
    status         VARCHAR(30),
    shipping_cost  NUMERIC(8,2),
    total_amount   VARCHAR(20),      -- text intentionally (messy)
    payment_method VARCHAR(50),
    ship_method    VARCHAR(30),
    coupon_code    VARCHAR(20),
    ship_city      VARCHAR(100),
    ship_country   VARCHAR(100)
);

CREATE TABLE order_items (
    item_id      INT PRIMARY KEY,
    order_id     INT REFERENCES orders(order_id),
    product_id   INT REFERENCES products(product_id),
    quantity     INT,
    unit_price   NUMERIC(10,2),
    discount_amt NUMERIC(10,2)
);

CREATE TABLE payments (
    payment_id     INT PRIMARY KEY,
    order_id       INT REFERENCES orders(order_id),
    payment_date   VARCHAR(20),
    amount         NUMERIC(10,2),
    method         VARCHAR(50),
    status         VARCHAR(30),
    transaction_id VARCHAR(50)
);

CREATE TABLE returns (
    return_id     INT PRIMARY KEY,
    order_id      INT REFERENCES orders(order_id),
    return_date   VARCHAR(20),
    reason        VARCHAR(300),
    refund_amount NUMERIC(10,2),
    status        VARCHAR(30)
);

CREATE TABLE reviews (
    review_id     INT PRIMARY KEY,
    product_id    INT REFERENCES products(product_id),
    customer_id   INT REFERENCES customers(customer_id),
    review_date   VARCHAR(20),
    rating        INT,
    review_text   TEXT,
    helpful_votes INT,
    purchase_type VARCHAR(30)
);

-- ============================================================================================================================
-- PROJECT      : Amazon-Style E-Commerce Database — End-to-End SQL Analysis
-- FILE         : 01_data_cleaning.sql
-- DESCRIPTION  : Full data cleaning pipeline using staging tables and clean views.
--                Each table follows the same pattern:
--                  1. Duplicate audit  (ROW_NUMBER window function)
--                  2. Staging table    (isolated copy of raw data)
--                  3. Clean VIEW       (standardised, cast, null-handled output)
-- DATABASE     : PostgreSQL 18
-- AUTHOR       : [Anshul]
-- LAST UPDATED : 2026
-- ============================================================================================================================


-- ============================================================================================================================
-- SECTION 0 : RAW DATA PREVIEW
-- Purpose    : Quick row-count and sample check before touching any data.
--              Always run this first to understand what you are working with.
-- ============================================================================================================================

SELECT 'customers'   AS table_name, COUNT(*) AS row_count FROM customers   UNION ALL
SELECT 'sellers',                   COUNT(*)               FROM sellers     UNION ALL
SELECT 'categories',                COUNT(*)               FROM categories  UNION ALL
SELECT 'products',                  COUNT(*)               FROM products    UNION ALL
SELECT 'orders',                    COUNT(*)               FROM orders      UNION ALL
SELECT 'order_items',               COUNT(*)               FROM order_items UNION ALL
SELECT 'payments',                  COUNT(*)               FROM payments    UNION ALL
SELECT 'returns',                   COUNT(*)               FROM returns     UNION ALL
SELECT 'reviews',                   COUNT(*)               FROM reviews


-- ============================================================================================================================
-- SECTION 1 : CATEGORIES
-- Issues     : Mixed casing in category_name and description; NULL parent_cat_id for root categories.
-- ============================================================================================================================

-- 1A. Duplicate audit
WITH cte_categories_dupes AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY LOWER(TRIM(category_name))
            ORDER BY category_id
        ) AS row_num
    FROM categories
)
SELECT *
FROM   cte_categories_dupes
WHERE  row_num > 1;

-- 1B. Staging table (isolated raw copy)
CREATE TABLE IF NOT EXISTS stg_categories AS
SELECT * FROM categories;

-- 1C. Clean view
CREATE OR REPLACE VIEW categories_clean AS
SELECT
    category_id,
    INITCAP(TRIM(category_name))                    AS category_name,
    INITCAP(TRIM(description))                      AS description,
    COALESCE(parent_cat_id, 0)                      AS parent_cat_id   -- 0 = root category (no parent)
FROM stg_categories;

-- Verify
SELECT * FROM categories_clean ORDER BY category_id;


-- ============================================================================================================================
-- SECTION 2 : CUSTOMERS
-- Issues     : Duplicate records (same email + phone); inconsistent name/gender casing; mixed date formats
--              in signup_date; non-numeric age values ('N/A', 'unknown'); inconsistent country strings;
--              blank/invalid phone numbers; inconsistent prime_member flag values.
-- ============================================================================================================================

-- 2A. Duplicate audit
--     Partitioning on the natural composite key that defines a unique customer.
WITH cte_customer_dupes AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY email, phone
            ORDER BY customer_id
        ) AS row_num
    FROM customers
)
SELECT *
FROM   cte_customer_dupes
WHERE  row_num > 1;

-- 2B. Staging table
CREATE TABLE IF NOT EXISTS stg_customers AS
SELECT * FROM customers;

-- 2C. Clean view
CREATE OR REPLACE VIEW customers_clean AS
SELECT
    customer_id,
    INITCAP(TRIM(first_name))                                               AS first_name,
    INITCAP(TRIM(last_name))                                                AS last_name,

    -- Email: validate format; flag invalids rather than silently dropping
    CASE
        WHEN TRIM(email) ~ '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'
             THEN LOWER(TRIM(email))
        ELSE 'invalid_email'
    END                                                                     AS email,

    -- Phone: strip all non-digit characters; NULL if nothing remains
    NULLIF(REGEXP_REPLACE(COALESCE(phone, ''), '[^0-9]', '', 'g'), '')     AS phone,

    INITCAP(TRIM(city))                                                     AS city,
    UPPER(TRIM(state))                                                      AS state,

    -- Country: normalise common variants to a single canonical value
    CASE
        WHEN UPPER(TRIM(country)) IN ('US', 'USA', 'U.S.A', 'UNITED STATES') THEN 'United States'
        WHEN UPPER(TRIM(country)) IN ('UK', 'U.K', 'UNITED KINGDOM')          THEN 'United Kingdom'
        WHEN UPPER(TRIM(country)) = 'CANADA'                                   THEN 'Canada'
        ELSE INITCAP(TRIM(country))
    END                                                                     AS country,

    -- Age: keep numeric values only; treat everything else as NULL
    CASE
        WHEN age ~ '^\d+$' AND age::INT BETWEEN 16 AND 100 THEN age::INT
        ELSE NULL
    END                                                                     AS age,

    -- Gender: standardise abbreviations and casing
    CASE
        WHEN UPPER(TRIM(gender)) IN ('M', 'MALE')          THEN 'Male'
        WHEN UPPER(TRIM(gender)) IN ('F', 'FEMALE')        THEN 'Female'
        WHEN UPPER(TRIM(gender)) = 'NON-BINARY'            THEN 'Non-Binary'
        ELSE NULL
    END                                                                     AS gender,

    -- Signup date: handle four observed raw formats; NULL if unrecognised
    CASE
        WHEN signup_date ~ '^\d{4}-\d{2}-\d{2}$'               THEN TO_DATE(signup_date, 'YYYY-MM-DD')
        WHEN signup_date ~ '^\d{2}/\d{2}/\d{4}$'               THEN TO_DATE(signup_date, 'MM/DD/YYYY')
        WHEN signup_date ~ '^\d{2}-[A-Za-z]+-\d{4}$'           THEN TO_DATE(signup_date, 'DD-Mon-YYYY')
        WHEN signup_date ~ '^[A-Za-z]+ \d+, \d{4}$'            THEN TO_DATE(signup_date, 'Month DD, YYYY')
        ELSE NULL
    END                                                                     AS signup_date,

    INITCAP(TRIM(segment))                                                  AS segment,

    -- Prime member: normalise all truthy/falsy variants
    CASE
        WHEN UPPER(TRIM(prime_member)) IN ('YES', 'Y', '1', 'TRUE')  THEN 'Yes'
        WHEN UPPER(TRIM(prime_member)) IN ('NO',  'N', '0', 'FALSE') THEN 'No'
        ELSE NULL
    END                                                                     AS prime_member,

    total_spent,
    total_orders
FROM stg_customers;

-- Verify
SELECT * FROM customers_clean LIMIT 10;


-- ============================================================================================================================
-- SECTION 3 : ORDERS
-- Issues     : Duplicate orders (same order_id / customer_id / date / coupon); order_date and delivery_date
--              stored as VARCHAR — must be cast to DATE; total_amount stored as VARCHAR — must be cast to
--              NUMERIC; NULL coupon_code; inconsistent status / payment_method / ship_method casing;
--              orders with future dates flagged as 'Invalid'.
-- ============================================================================================================================

-- 3A. Duplicate audit
WITH cte_order_dupes AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY order_id, customer_id, order_date, delivery_date, status, coupon_code
            ORDER BY order_id
        ) AS row_num
    FROM orders
)
SELECT *
FROM   cte_order_dupes
WHERE  row_num > 1;

-- 3B. Staging table
CREATE TABLE IF NOT EXISTS stg_orders AS
SELECT * FROM orders;

-- 3C. Clean view
CREATE OR REPLACE VIEW orders_clean AS
SELECT
    order_id,
    customer_id,

    -- Cast VARCHAR dates; only accept YYYY-MM-DD format from this dataset
    CASE
        WHEN order_date    ~ '^\d{4}-\d{2}-\d{2}$' THEN order_date::DATE
        ELSE NULL
    END                                                                     AS order_date,

    CASE
        WHEN delivery_date ~ '^\d{4}-\d{2}-\d{2}$' THEN delivery_date::DATE
        ELSE NULL
    END                                                                     AS delivery_date,

    -- Flag future-dated orders rather than silently dropping them
    CASE
        WHEN order_date ~ '^\d{4}-\d{2}-\d{2}$'
             AND order_date::DATE > CURRENT_DATE THEN 'Invalid'
        ELSE INITCAP(TRIM(status))
    END                                                                     AS status,

    shipping_cost,

    -- Cast total_amount from VARCHAR to NUMERIC; NULL if non-numeric
    CASE
        WHEN total_amount ~ '^\d+(\.\d+)?$' THEN total_amount::NUMERIC
        ELSE NULL
    END                                                                     AS total_amount,

    INITCAP(TRIM(payment_method))                                           AS payment_method,
    INITCAP(TRIM(ship_method))                                              AS ship_method,
    COALESCE(NULLIF(TRIM(coupon_code), ''), 'No Coupon')                   AS coupon_code,
    INITCAP(TRIM(ship_city))                                                AS ship_city,

    CASE
        WHEN UPPER(TRIM(ship_country)) IN ('US', 'USA', 'UNITED STATES')  THEN 'United States'
        WHEN UPPER(TRIM(ship_country)) IN ('UK', 'UNITED KINGDOM')        THEN 'United Kingdom'
        ELSE INITCAP(TRIM(ship_country))
    END                                                                     AS ship_country
FROM stg_orders;

-- Verify
SELECT * FROM orders_clean LIMIT 10;


-- ============================================================================================================================
-- SECTION 4 : ORDER ITEMS
-- Issues     : Duplicate line items (same item_id / order_id / product_id / discount); zero or negative
--              quantities; NULL product_id.
-- ============================================================================================================================

-- 4A. Duplicate audit
WITH cte_order_item_dupes AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY item_id, order_id, product_id, discount_amt
            ORDER BY item_id
        ) AS row_num
    FROM order_items
)
SELECT *
FROM   cte_order_item_dupes
WHERE  row_num > 1;

-- 4B. Staging table
CREATE TABLE IF NOT EXISTS stg_order_items AS
SELECT * FROM order_items;

-- 4C. Clean view — invalid quantity rows and NULL product_ids are excluded
CREATE OR REPLACE VIEW order_items_clean AS
SELECT
    item_id,
    order_id,
    product_id,
    quantity,
    unit_price,
    COALESCE(discount_amt, 0)   AS discount_amt
FROM stg_order_items
WHERE product_id IS NOT NULL
  AND quantity   >  0;

-- Verify
SELECT * FROM order_items_clean LIMIT 10;


-- ============================================================================================================================
-- SECTION 5 : PAYMENTS
-- Issues     : Duplicate payments for the same order (duplicate transaction_id); payment_date stored as
--              VARCHAR; NULL amounts; inconsistent status casing.
-- ============================================================================================================================

-- 5A. Duplicate audit — a genuine duplicate is same order paid with same transaction_id
WITH cte_payment_dupes AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY order_id, transaction_id
            ORDER BY payment_id
        ) AS row_num
    FROM payments
)
SELECT *
FROM   cte_payment_dupes
WHERE  row_num > 1;

-- 5B. Staging table
CREATE TABLE IF NOT EXISTS stg_payments AS
SELECT * FROM payments;

-- 5C. Clean view
CREATE OR REPLACE VIEW payments_clean AS
SELECT
    payment_id,
    order_id,

    CASE
        WHEN payment_date ~ '^\d{4}-\d{2}-\d{2}$' THEN payment_date::DATE
        ELSE NULL
    END                                             AS payment_date,

    amount,
    INITCAP(TRIM(method))                           AS method,
    INITCAP(TRIM(status))                           AS status,
    UPPER(TRIM(transaction_id))                     AS transaction_id
FROM stg_payments;

-- Verify
SELECT * FROM payments_clean LIMIT 10;


-- ============================================================================================================================
-- SECTION 6 : RETURNS
-- Issues     : Duplicate return records; return_date stored as VARCHAR with a double-bracket regex bug
--              in the original (^[[0-9] — extra bracket); NULL reason; inconsistent status casing;
--              return_date before order_date (business logic violation).
-- ============================================================================================================================

-- 6A. Duplicate audit
WITH cte_return_dupes AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY return_id, order_id, return_date
            ORDER BY return_id
        ) AS row_num
    FROM returns
)
SELECT *
FROM   cte_return_dupes
WHERE  row_num > 1;

-- 6B. Business logic audit — return before order (impossible)
SELECT
    r.return_id,
    r.order_id,
    r.return_date,
    o.order_date,
    r.return_date::DATE - o.order_date::DATE AS days_diff
FROM   returns r
JOIN   orders  o ON r.order_id = o.order_id
WHERE  r.return_date ~ '^\d{4}-\d{2}-\d{2}$'
  AND  o.order_date  ~ '^\d{4}-\d{2}-\d{2}$'
  AND  r.return_date::DATE < o.order_date::DATE;

-- 6C. Staging table
CREATE TABLE IF NOT EXISTS stg_returns AS
SELECT * FROM returns;

-- 6D. Clean view — excludes rows where return_date pre-dates order_date
CREATE OR REPLACE VIEW returns_clean AS
SELECT
    r.return_id,
    r.order_id,

    CASE
        WHEN r.return_date ~ '^\d{4}-\d{2}-\d{2}$' THEN r.return_date::DATE
        ELSE NULL
    END                                                     AS return_date,

    COALESCE(NULLIF(TRIM(r.reason), ''), 'Not Specified')  AS reason,
    r.refund_amount,
    INITCAP(TRIM(r.status))                                 AS status
FROM stg_returns r
JOIN stg_orders  o ON r.order_id = o.order_id
WHERE NOT (
        r.return_date ~ '^\d{4}-\d{2}-\d{2}$'
    AND o.order_date  ~ '^\d{4}-\d{2}-\d{2}$'
    AND r.return_date::DATE < o.order_date::DATE
);

-- Verify
SELECT * FROM returns_clean LIMIT 10;


-- ============================================================================================================================
-- SECTION 7 : PRODUCTS
-- Issues     : Duplicate products (same product_id / category_id / ASIN); negative price and discount > 100
--              on test/discontinued rows; mixed status casing; NULL weight and rating on inactive items.
-- ============================================================================================================================

-- 7A. Duplicate audit
WITH cte_product_dupes AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY product_id, category_id, asin
            ORDER BY product_id
        ) AS row_num
    FROM products
)
SELECT *
FROM   cte_product_dupes
WHERE  row_num > 1;

-- 7B. Business logic audit — invalid pricing
SELECT product_id, product_name, price, discount_pct, status
FROM   products
WHERE  price        <= 0
   OR  discount_pct >  100
   OR  discount_pct <  0;

-- 7C. Staging table
CREATE TABLE IF NOT EXISTS stg_products AS
SELECT * FROM products;

-- 7D. Clean view — invalid-priced rows are kept but flagged as 'Inactive'
CREATE OR REPLACE VIEW products_clean AS
SELECT
    product_id,
    INITCAP(TRIM(product_name))                     AS product_name,
    category_id,
    seller_id,
    price,
    cost_price,
    stock_qty,
    discount_pct,
    UPPER(TRIM(asin))                               AS asin,

    -- Override status to 'Inactive' for records with invalid business values
    CASE
        WHEN price <= 0 OR discount_pct > 100 THEN 'Inactive'
        ELSE INITCAP(TRIM(status))
    END                                             AS status,

    weight_kg,
    rating,
    TRIM(description)                               AS description
FROM stg_products;

-- Verify
SELECT * FROM products_clean LIMIT 10;


-- ============================================================================================================================
-- SECTION 8 : REVIEWS
-- Issues     : Duplicate reviews (same reviewer + product + date + rating); review_date stored as VARCHAR;
--              ratings outside the valid 1–5 range; NULL review_text (kept — rating alone is valid);
--              future review dates.
-- ============================================================================================================================

-- 8A. Duplicate audit
WITH cte_review_dupes AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY review_id, product_id, customer_id, review_date, rating, purchase_type
            ORDER BY review_id
        ) AS row_num
    FROM reviews
)
SELECT *
FROM   cte_review_dupes
WHERE  row_num > 1;

-- 8B. Invalid rating audit
SELECT review_id, product_id, customer_id, rating, review_date
FROM   reviews
WHERE  rating < 1 OR rating > 5;

-- 8C. Staging table
CREATE TABLE IF NOT EXISTS stg_reviews AS
SELECT * FROM reviews;

-- 8D. Clean view — excludes invalid ratings and future-dated reviews
CREATE OR REPLACE VIEW reviews_clean AS
SELECT
    review_id,
    product_id,
    customer_id,

    CASE
        WHEN review_date ~ '^\d{4}-\d{2}-\d{2}$' THEN review_date::DATE
        ELSE NULL
    END                                             AS review_date,

    rating,
    TRIM(review_text)                               AS review_text,
    helpful_votes,
    INITCAP(TRIM(purchase_type))                    AS purchase_type
FROM stg_reviews
WHERE rating BETWEEN 1 AND 5
  AND (
        review_date !~ '^\d{4}-\d{2}-\d{2}$'
     OR review_date::DATE <= CURRENT_DATE
  );

-- Verify
SELECT * FROM reviews_clean LIMIT 10;


-- ============================================================================================================================
-- SECTION 9 : SELLERS
-- Issues     : Duplicate seller entries (same name + email + city + year joined); blank/NULL phone;
--              inconsistent country casing; avg_rating and year_joined cast to TEXT in original —
--              kept as their native numeric types here.
-- ============================================================================================================================

-- 9A. Duplicate audit
WITH cte_seller_dupes AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY seller_name, email, city, year_joined
            ORDER BY seller_id
        ) AS row_num
    FROM sellers
)
SELECT *
FROM   cte_seller_dupes
WHERE  row_num > 1;

-- 9B. Staging table
CREATE TABLE IF NOT EXISTS stg_sellers AS
SELECT * FROM sellers;

-- 9C. Clean view
CREATE OR REPLACE VIEW sellers_clean AS
SELECT
    seller_id,
    INITCAP(TRIM(seller_name))                                          AS seller_name,
    INITCAP(TRIM(contact_name))                                         AS contact_name,

    CASE
        WHEN TRIM(email) ~ '^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$'
             THEN LOWER(TRIM(email))
        ELSE 'invalid_email'
    END                                                                 AS email,

    NULLIF(REGEXP_REPLACE(COALESCE(phone, ''), '[^0-9]', '', 'g'), '') AS phone,

    COALESCE(NULLIF(INITCAP(TRIM(city)),  ''), 'Unknown')              AS city,
    COALESCE(NULLIF(UPPER(TRIM(state)),   ''), 'N/A')                  AS state,

    CASE
        WHEN UPPER(TRIM(country)) IN ('US', 'USA', 'UNITED STATES') THEN 'United States'
        WHEN UPPER(TRIM(country)) IN ('UK', 'UNITED KINGDOM')        THEN 'United Kingdom'
        WHEN UPPER(TRIM(country)) = 'CANADA'                          THEN 'Canada'
        ELSE INITCAP(TRIM(country))
    END                                                                 AS country,

    avg_rating,     -- retained as NUMERIC 
    year_joined     -- retained as INT
FROM stg_sellers;

-- Verify
SELECT * FROM sellers_clean LIMIT 10;

-- ============================================================================================================================

-- ============================================================================================================================
-- Q-01 : TOP 10 BEST-SELLING PRODUCTS BY UNITS SOLD
-- Business use : Identify hero SKUs for inventory planning and marketing spend.
-- ============================================================================================================================

SELECT
    p.product_name,
    SUM(oi.quantity)    AS units_sold
FROM   products_clean    p
JOIN   order_items_clean oi ON oi.product_id = p.product_id
GROUP  BY p.product_name
ORDER  BY units_sold DESC
LIMIT  10;


-- ============================================================================================================================
-- Q-02 : MONTHLY ORDER VOLUME — 2023
-- Business use : Spot seasonal demand peaks to align fulfilment and staffing capacity.
-- ============================================================================================================================

SELECT
    EXTRACT(MONTH FROM order_date)              AS month_number,
    TO_CHAR(order_date, 'Month')                AS month_name,
    COUNT(DISTINCT order_id)                    AS order_count
FROM   orders_clean
WHERE  EXTRACT(YEAR FROM order_date) = 2023
  AND  status NOT IN ('Invalid', 'Cancelled')
GROUP  BY month_number, month_name
ORDER  BY month_number;


-- ============================================================================================================================
-- Q-03 : TOTAL REVENUE BY PRODUCT CATEGORY (DELIVERED ORDERS ONLY)
-- Business use : Understand which categories drive the business; inform assortment strategy.
-- Note        : Revenue = (unit_price × quantity) − discount_amt to reflect actual realised revenue.
-- ============================================================================================================================

SELECT
    cat.category_name,
    ROUND(SUM(oi.quantity * oi.unit_price - oi.discount_amt), 2) AS revenue
FROM   categories_clean  cat
JOIN   products_clean    p   ON p.category_id  = cat.category_id
JOIN   order_items_clean oi  ON oi.product_id  = p.product_id
JOIN   orders_clean      o   ON o.order_id     = oi.order_id
WHERE  o.status = 'Delivered'
GROUP  BY cat.category_name
ORDER  BY revenue DESC;


-- ============================================================================================================================
-- Q-04 : PRIME MEMBERS WHO HAVE NEVER PLACED AN ORDER
-- Business use : High-value subscribers not converting — target for re-engagement campaigns.
-- ============================================================================================================================

SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    c.email,
    c.signup_date
FROM   customers_clean c
LEFT   JOIN orders_clean o ON o.customer_id = c.customer_id
WHERE  o.order_id    IS NULL
  AND  c.prime_member = 'Yes'
ORDER  BY c.customer_id;


-- ============================================================================================================================
-- Q-05 : AVERAGE ORDER VALUE (AOV) BY PAYMENT METHOD
-- Business use : Understand spend behaviour per channel; negotiate better rates with high-AOV providers.
-- ============================================================================================================================

SELECT
    p.method,
    COUNT(DISTINCT p.payment_id)            AS transaction_count,
    ROUND(AVG(o.total_amount), 2)           AS avg_order_value
FROM   payments_clean p
JOIN   orders_clean   o ON o.order_id = p.order_id
WHERE  o.status = 'Delivered'
  AND  p.status = 'Completed'
GROUP  BY p.method
ORDER  BY avg_order_value DESC;


-- ============================================================================================================================
-- Q-06 : MONTHLY CANCELLATION RATE — 2022 AND 2023
-- Business use : Monitor fulfilment health; a rising cancel rate signals stock or logistics problems.
-- ============================================================================================================================

WITH monthly_orders AS (
    SELECT
        DATE_TRUNC('month', order_date)                     AS order_month,
        COUNT(order_id)                                     AS total_orders,
        SUM(CASE WHEN status = 'Cancelled' THEN 1 ELSE 0 END) AS cancelled_orders
    FROM   orders_clean
    WHERE  EXTRACT(YEAR FROM order_date) IN (2022, 2023)
    GROUP  BY order_month
)
SELECT
    TO_CHAR(order_month, 'YYYY-MM')                         AS month,
    total_orders,
    cancelled_orders,
    ROUND(cancelled_orders * 100.0 / NULLIF(total_orders, 0), 2) AS cancellation_rate_pct
FROM   monthly_orders
ORDER  BY order_month;


-- ============================================================================================================================
-- Q-07 : TOP 10 US STATES BY CUSTOMER COUNT
-- Business use : Geographic concentration analysis; supports regional warehouse and logistics planning.
-- ============================================================================================================================

SELECT
    state,
    COUNT(*) AS customer_count
FROM   customers_clean
WHERE  country = 'United States'
  AND  state   IS NOT NULL
GROUP  BY state
ORDER  BY customer_count DESC
LIMIT  10;


-- ============================================================================================================================
-- Q-08 : AVERAGE SELLER RATING AND REVIEW VOLUME
-- Business use : Identify underperforming sellers for quality review or de-listing.
-- ============================================================================================================================

SELECT
    s.seller_name,
    ROUND(AVG(r.rating), 2)         AS avg_rating,
    COUNT(DISTINCT r.review_id)     AS total_reviews
FROM   sellers_clean  s
JOIN   products_clean p ON p.seller_id  = s.seller_id
JOIN   reviews_clean  r ON r.product_id = p.product_id
GROUP  BY s.seller_name
ORDER  BY avg_rating DESC;


-- ============================================================================================================================
-- Q-09 : COUPON USAGE RATE (DELIVERED ORDERS)
-- Business use : Measure promotional effectiveness; evaluate whether discounts are driving incremental volume.
-- ============================================================================================================================

SELECT
    COUNT(order_id)                                                                     AS total_orders,
    SUM(CASE WHEN coupon_code <> 'No Coupon' THEN 1 ELSE 0 END)                        AS coupon_orders,
    ROUND(
        SUM(CASE WHEN coupon_code <> 'No Coupon' THEN 1.0 ELSE 0 END)
        * 100.0 / NULLIF(COUNT(order_id), 0),
        2
    )                                                                                   AS coupon_usage_pct
FROM   orders_clean
WHERE  status = 'Delivered';


-- ============================================================================================================================
-- Q-10 : TOP 5 PRODUCTS BY RETURN RATE
-- Business use : High return rates signal quality, listing accuracy, or fit issues — prioritise for review.
-- ============================================================================================================================

SELECT
    p.product_name,
    COUNT(r.return_id)                                                      AS total_returns,
    SUM(oi.quantity)                                                        AS units_sold,
    ROUND(COUNT(r.return_id) * 100.0 / NULLIF(SUM(oi.quantity), 0), 2)    AS return_rate_pct
FROM   products_clean    p
LEFT   JOIN order_items_clean oi ON oi.product_id = p.product_id
LEFT   JOIN returns_clean     r  ON r.order_id    = oi.order_id
GROUP  BY p.product_name
HAVING SUM(oi.quantity) > 0
ORDER  BY return_rate_pct DESC
LIMIT  5;


-- ============================================================================================================================
-- Q-11 : REFUND RATE BY PAYMENT METHOD
-- Business use : High refund rates on specific channels may indicate fraud patterns or poor UX.
-- ============================================================================================================================

SELECT
    method,
    COUNT(payment_id)                                                        AS total_payments,
    SUM(CASE WHEN status = 'Refunded' THEN 1 ELSE 0 END)                    AS refunded_payments,
    ROUND(
        SUM(CASE WHEN status = 'Refunded' THEN 1.0 ELSE 0 END)
        * 100.0 / NULLIF(COUNT(payment_id), 0),
        2
    )                                                                        AS refund_rate_pct
FROM   payments_clean
GROUP  BY method
ORDER  BY refund_rate_pct DESC;


-- ============================================================================================================================
-- Q-12 : AVERAGE DELIVERY TIME BY SHIPPING METHOD
-- Business use : SLA monitoring — flag methods that breach the 5-day benchmark.
-- ============================================================================================================================

WITH delivery_times AS (
    SELECT
        ship_method,
        (delivery_date - order_date)    AS days_to_deliver
    FROM   orders_clean
    WHERE  status       = 'Delivered'
      AND  order_date   IS NOT NULL
      AND  delivery_date IS NOT NULL
)
SELECT
    ship_method,
    ROUND(AVG(days_to_deliver), 1)                                  AS avg_delivery_days,
    CASE
        WHEN AVG(days_to_deliver) > 5 THEN 'Breach — Review Required'
        ELSE 'Within SLA'
    END                                                             AS sla_status
FROM   delivery_times
GROUP  BY ship_method
ORDER  BY avg_delivery_days;


-- ============================================================================================================================
-- Q-13 : EXECUTIVE SUMMARY DASHBOARD — SINGLE-QUERY KPI SNAPSHOT (2023)
-- Business use : One-row executive summary for leadership reporting; maps directly to a Power BI card row.
-- Fixes       : Original query had a syntax error (ROUND(c.avg_order_value,2) AS ,) and wrong
--               CROSS JOIN target (CTE instead of ranks CTE). Corrected below.
-- ============================================================================================================================

WITH kpis AS (
    SELECT
        ROUND(SUM(o.total_amount), 2)                                               AS total_revenue,
        COUNT(DISTINCT o.order_id)                                                  AS total_orders,
        ROUND(SUM(o.total_amount) / NULLIF(COUNT(DISTINCT o.order_id), 0), 2)      AS avg_order_value,
        COUNT(DISTINCT o.customer_id)                                               AS active_customers,
        ROUND(
            100.0 * COUNT(DISTINCT CASE WHEN c.prime_member = 'Yes' THEN c.customer_id END)
            / NULLIF(COUNT(DISTINCT o.customer_id), 0),
            2
        )                                                                           AS prime_member_pct
    FROM   orders_clean    o
    JOIN   customers_clean c ON c.customer_id = o.customer_id
    WHERE  EXTRACT(YEAR FROM o.order_date) = 2023
      AND  o.status = 'Delivered'
),
category_revenue AS (
    SELECT
        cat.category_name,
        SUM(o.total_amount)                                                         AS category_revenue,
        ROW_NUMBER() OVER (ORDER BY SUM(o.total_amount) DESC)                      AS revenue_rank
    FROM   categories_clean  cat
    JOIN   products_clean    p   ON p.category_id = cat.category_id
    JOIN   order_items_clean oi  ON oi.product_id = p.product_id
    JOIN   orders_clean      o   ON o.order_id    = oi.order_id
    WHERE  EXTRACT(YEAR FROM o.order_date) = 2023
      AND  o.status = 'Delivered'
    GROUP  BY cat.category_name
)
SELECT
    k.total_revenue,
    k.total_orders,
    k.avg_order_value,
    k.active_customers,
    k.prime_member_pct,
    cr.category_name   AS top_category
FROM   kpis             k
CROSS  JOIN category_revenue cr
WHERE  cr.revenue_rank = 1;


-- ============================================================================================================================
-- Q-01 : TOP 10 CUSTOMERS BY LIFETIME VALUE (LTV)
-- Business use : Identify highest-value customers for VIP treatment, retention offers, and upsell targeting.
-- Fix         : Original used COALESCE(SUM(o.total_amount::NUMERIC),0) — total_amount is already NUMERIC
--               in the clean view; the redundant cast is removed.
-- ============================================================================================================================

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name)  AS customer_name,
    c.segment,
    c.prime_member,
    COUNT(DISTINCT o.order_id)              AS total_orders,
    ROUND(SUM(o.total_amount), 2)           AS lifetime_value
FROM   customers_clean c
JOIN   orders_clean    o ON o.customer_id = c.customer_id
WHERE  o.status = 'Delivered'
GROUP  BY
    c.customer_id,
    c.first_name,
    c.last_name,
    c.segment,
    c.prime_member
ORDER  BY lifetime_value DESC
LIMIT  10;


-- ============================================================================================================================
-- Q-02 : CUSTOMERS WITH ABOVE-AVERAGE LIFETIME VALUE
-- Business use : Distinguish high-value customers from the base; input for tiered loyalty programmes.
-- ============================================================================================================================

WITH customer_ltv AS (
    SELECT
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name)  AS customer_name,
        ROUND(SUM(o.total_amount), 2)            AS lifetime_value
    FROM   customers_clean c
    JOIN   orders_clean    o ON o.customer_id = c.customer_id
    WHERE  o.status = 'Delivered'
    GROUP  BY c.customer_id, c.first_name, c.last_name
)
SELECT
    customer_id,
    customer_name,
    lifetime_value,
    ROUND((SELECT AVG(lifetime_value) FROM customer_ltv), 2) AS platform_avg_ltv
FROM   customer_ltv
WHERE  lifetime_value > (SELECT AVG(lifetime_value) FROM customer_ltv)
ORDER  BY lifetime_value DESC;


-- ============================================================================================================================
-- Q-03 : TOP 3 CUSTOMERS PER SEGMENT BY REVENUE
-- Business use : Recognise the best performers in each segment; personalise rewards by tier.
-- ============================================================================================================================

WITH ranked_customers AS (
    SELECT
        c.segment,
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name)  AS customer_name,
        ROUND(SUM(o.total_amount), 2)            AS total_revenue,
        ROW_NUMBER() OVER (
            PARTITION BY c.segment
            ORDER BY SUM(o.total_amount) DESC
        )                                        AS segment_rank
    FROM   customers_clean c
    JOIN   orders_clean    o ON o.customer_id = c.customer_id
    WHERE  o.status = 'Delivered'
    GROUP  BY c.segment, c.customer_id, c.first_name, c.last_name
)
SELECT
    segment,
    segment_rank,
    customer_id,
    customer_name,
    total_revenue
FROM   ranked_customers
WHERE  segment_rank <= 3
ORDER  BY segment, segment_rank;


-- ============================================================================================================================
-- Q-04 : PRIME VS NON-PRIME REVENUE BY QUARTER
-- Business use : Quantify the revenue impact of Prime membership; inform membership pricing decisions.
-- ============================================================================================================================

SELECT
    CASE
        WHEN c.prime_member = 'Yes' THEN 'Prime'
        ELSE 'Non-Prime'
    END                                         AS customer_type,
    TO_CHAR(DATE_TRUNC('quarter', o.order_date), 'YYYY-"Q"Q') AS quarter,
    COUNT(DISTINCT o.order_id)                  AS total_orders,
    ROUND(SUM(o.total_amount), 2)               AS revenue
FROM   customers_clean c
JOIN   orders_clean    o ON o.customer_id = c.customer_id
WHERE  o.status = 'Delivered'
GROUP  BY customer_type, DATE_TRUNC('quarter', o.order_date)
ORDER  BY DATE_TRUNC('quarter', o.order_date), customer_type;


-- ============================================================================================================================
-- Q-05 : REPEAT CUSTOMERS — ORDERED IN 3 OR MORE DISTINCT MONTHS
-- Business use : Measured purchase loyalty beyond simple order counts; identify habitual buyers.
-- ============================================================================================================================

SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name)                      AS customer_name,
    COUNT(DISTINCT DATE_TRUNC('month', o.order_date))           AS active_months,
    COUNT(DISTINCT o.order_id)                                  AS total_orders
FROM   customers_clean c
JOIN   orders_clean    o ON o.customer_id = c.customer_id
WHERE  o.status NOT IN ('Invalid', 'Cancelled')
GROUP  BY c.customer_id, c.first_name, c.last_name
HAVING COUNT(DISTINCT DATE_TRUNC('month', o.order_date)) >= 3
ORDER  BY active_months DESC, total_orders DESC;


-- ============================================================================================================================
-- Q-06 : AVERAGE GAP BETWEEN CONSECUTIVE ORDERS PER CUSTOMER
-- Business use : Understand purchase cadence; feed into churn prediction (customers exceeding their
--               average gap are at risk of churning).
-- ============================================================================================================================

WITH order_sequence AS (
    SELECT
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name)      AS customer_name,
        o.order_id,
        o.order_date,
        LAG(o.order_date) OVER (
            PARTITION BY c.customer_id
            ORDER BY o.order_date
        )                                            AS prev_order_date
    FROM   customers_clean c
    JOIN   orders_clean    o ON o.customer_id = c.customer_id
    WHERE  o.status NOT IN ('Invalid', 'Cancelled')
      AND  o.order_date IS NOT NULL
)
SELECT
    customer_id,
    customer_name,
    COUNT(order_id)                                  AS total_orders,
    ROUND(AVG(order_date - prev_order_date), 1)      AS avg_days_between_orders
FROM   order_sequence
WHERE  prev_order_date IS NOT NULL
GROUP  BY customer_id, customer_name
HAVING COUNT(order_id) >= 3
ORDER  BY avg_days_between_orders;


-- ============================================================================================================================
-- Q-07 : Q1 2022 COHORT RETENTION ANALYSIS
-- Business use : Measure how well the platform retains first-time buyers over subsequent quarters.
--               A core metric for subscription and marketplace businesses.
-- ============================================================================================================================

WITH first_order_per_customer AS (
    SELECT
        customer_id,
        MIN(order_date) AS first_order_date
    FROM   orders_clean
    WHERE  status NOT IN ('Invalid', 'Cancelled')
    GROUP  BY customer_id
),
q1_2022_cohort AS (
    SELECT customer_id
    FROM   first_order_per_customer
    WHERE  first_order_date >= '2022-01-01'
      AND  first_order_date <  '2022-04-01'
)
SELECT
    COUNT(DISTINCT coh.customer_id)                                     AS cohort_size,

    COUNT(DISTINCT CASE
        WHEN o.order_date BETWEEN '2022-04-01' AND '2022-06-30'
        THEN o.customer_id
    END)                                                                AS q2_2022_retained,

    COUNT(DISTINCT CASE
        WHEN o.order_date BETWEEN '2022-07-01' AND '2022-09-30'
        THEN o.customer_id
    END)                                                                AS q3_2022_retained,

    COUNT(DISTINCT CASE
        WHEN o.order_date BETWEEN '2022-10-01' AND '2022-12-31'
        THEN o.customer_id
    END)                                                                AS q4_2022_retained
FROM   q1_2022_cohort coh
LEFT   JOIN orders_clean o
       ON  coh.customer_id = o.customer_id
       AND o.status NOT IN ('Invalid', 'Cancelled');


-- ============================================================================================================================
-- Q-08 : RFM CUSTOMER SEGMENTATION
-- Business use : Score every customer on Recency, Frequency, and Monetary value to assign a behaviour
--               segment — used directly for targeted marketing and churn-prevention campaigns.
-- ============================================================================================================================

WITH rfm_base AS (
    SELECT
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name)      AS customer_name,
        (CURRENT_DATE - MAX(o.order_date))           AS recency_days,
        COUNT(DISTINCT o.order_id)                   AS frequency,
        ROUND(SUM(o.total_amount), 2)                AS monetary
    FROM   customers_clean c
    JOIN   orders_clean    o ON o.customer_id = c.customer_id
    WHERE  o.status = 'Delivered'
    GROUP  BY c.customer_id, c.first_name, c.last_name
),
rfm_scored AS (
    SELECT
        *,
        -- Lower recency_days = more recent customer = should score HIGHER
        NTILE(4) OVER (ORDER BY recency_days ASC)   AS r_score,
        NTILE(4) OVER (ORDER BY frequency    DESC)  AS f_score,
        NTILE(4) OVER (ORDER BY monetary     DESC)  AS m_score
    FROM rfm_base
)
SELECT
    customer_id,
    customer_name,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    (r_score + f_score + m_score)   AS rfm_score,
    CASE
        WHEN (r_score + f_score + m_score) >= 10 THEN 'Champions'
        WHEN (r_score + f_score + m_score) BETWEEN 7 AND 9  THEN 'Loyal Customers'
        WHEN (r_score + f_score + m_score) BETWEEN 5 AND 6  THEN 'Potential Loyalists'
        WHEN (r_score + f_score + m_score) BETWEEN 3 AND 4  THEN 'At Risk / Lost'
    END                             AS rfm_segment
FROM rfm_scored
ORDER BY rfm_score DESC;


-- ============================================================================================================================
-- Q-09 : TOP 10% CUSTOMERS BY REVENUE AND THEIR SHARE OF TOTAL REVENUE
-- Business use : Pareto analysis — quantify how much revenue concentration exists in the top decile.
-- ============================================================================================================================

WITH customer_revenue AS (
    SELECT
        c.customer_id,
        CONCAT(c.first_name, ' ', c.last_name)  AS customer_name,
        ROUND(SUM(o.total_amount), 2)            AS revenue
    FROM   customers_clean c
    JOIN   orders_clean    o ON o.customer_id = c.customer_id
    WHERE  o.status = 'Delivered'
    GROUP  BY c.customer_id, c.first_name, c.last_name
),
threshold AS (
    SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY revenue) AS p90_revenue
    FROM   customer_revenue
)
SELECT
    cr.customer_id,
    cr.customer_name,
    cr.revenue,
    SUM(cr.revenue)  OVER ()                        AS total_platform_revenue,
    ROUND(cr.revenue * 100.0 / SUM(cr.revenue) OVER (), 2) AS pct_of_total_revenue
FROM   customer_revenue cr
CROSS  JOIN threshold    t
WHERE  cr.revenue >= t.p90_revenue
ORDER  BY cr.revenue DESC;


-- ============================================================================================================================
-- Q-01 : PROFIT MARGIN BY CATEGORY
-- Business use : Identify which categories generate the most margin, not just the most revenue.
--               Guides negotiation with suppliers and pricing strategy.
-- ============================================================================================================================

SELECT
    cat.category_name,
    ROUND(AVG((p.price - p.cost_price) / NULLIF(p.price, 0) * 100), 2)  AS avg_margin_pct,
    ROUND(MIN((p.price - p.cost_price) / NULLIF(p.price, 0) * 100), 2)  AS min_margin_pct,
    ROUND(MAX((p.price - p.cost_price) / NULLIF(p.price, 0) * 100), 2)  AS max_margin_pct
FROM   categories_clean cat
JOIN   products_clean   p   ON p.category_id = cat.category_id
WHERE  p.status = 'Active'
GROUP  BY cat.category_name
ORDER  BY avg_margin_pct DESC;


-- ============================================================================================================================
-- Q-02 : CATEGORY REVENUE CONTRIBUTION (% OF TOTAL)
-- Business use : Portfolio mix analysis — understand revenue concentration risk across categories.
-- ============================================================================================================================

WITH category_revenue AS (
    SELECT
        cat.category_name,
        ROUND(SUM(oi.quantity * oi.unit_price - oi.discount_amt), 2) AS revenue
    FROM   categories_clean  cat
    JOIN   products_clean    p   ON p.category_id  = cat.category_id
    JOIN   order_items_clean oi  ON oi.product_id  = p.product_id
    JOIN   orders_clean      o   ON o.order_id     = oi.order_id
    WHERE  o.status = 'Delivered'
    GROUP  BY cat.category_name
)
SELECT
    category_name,
    revenue,
    SUM(revenue) OVER ()                                    AS total_revenue,
    ROUND(revenue * 100.0 / SUM(revenue) OVER (), 2)       AS pct_of_total
FROM   category_revenue
ORDER  BY revenue DESC;


-- ============================================================================================================================
-- Q-03 : CATEGORY REVENUE MONTH-OVER-MONTH GROWTH
-- Business use : Trend analysis per category — spot which are growing vs declining to adjust investment.
-- ============================================================================================================================

WITH monthly_category_revenue AS (
    SELECT
        cat.category_name,
        DATE_TRUNC('month', o.order_date)               AS order_month,
        ROUND(SUM(o.total_amount), 2)                   AS revenue
    FROM   categories_clean  cat
    JOIN   products_clean    p   ON p.category_id  = cat.category_id
    JOIN   order_items_clean oi  ON oi.product_id  = p.product_id
    JOIN   orders_clean      o   ON o.order_id     = oi.order_id
    WHERE  o.status = 'Delivered'
    GROUP  BY cat.category_name, DATE_TRUNC('month', o.order_date)
),
with_lag AS (
    SELECT
        *,
        LAG(revenue) OVER (
            PARTITION BY category_name
            ORDER BY order_month
        )                                               AS prev_month_revenue
    FROM   monthly_category_revenue
)
SELECT
    category_name,
    TO_CHAR(order_month, 'YYYY-MM')                     AS month,
    revenue,
    prev_month_revenue,
    ROUND(
        (revenue - prev_month_revenue) * 100.0
        / NULLIF(prev_month_revenue, 0),
        2
    )                                                   AS mom_growth_pct
FROM   with_lag
ORDER  BY category_name, order_month;


-- ============================================================================================================================
-- Q-04 : MONTH-OVER-MONTH REVENUE GROWTH — PLATFORM LEVEL (2023)
-- Business use : Top-line revenue momentum tracking for leadership reporting.
-- ============================================================================================================================

WITH monthly_revenue AS (
    SELECT
        DATE_TRUNC('month', o.order_date)       AS order_month,
        ROUND(SUM(o.total_amount), 2)           AS revenue
    FROM   orders_clean o
    WHERE  EXTRACT(YEAR FROM o.order_date) = 2023
      AND  o.status = 'Delivered'
    GROUP  BY DATE_TRUNC('month', o.order_date)
),
with_lag AS (
    SELECT
        *,
        LAG(revenue) OVER (ORDER BY order_month) AS prev_month_revenue
    FROM   monthly_revenue
)
SELECT
    TO_CHAR(order_month, 'YYYY-MM')                     AS month,
    revenue,
    prev_month_revenue,
    ROUND(
        (revenue - prev_month_revenue) * 100.0
        / NULLIF(prev_month_revenue, 0),
        2
    )                                                   AS mom_growth_pct
FROM   with_lag
ORDER  BY order_month;


-- ============================================================================================================================
-- Q-05 : RANKED PRODUCTS WITHIN EACH CATEGORY BY REVENUE
-- Business use : Identify the star product in every category for promotional and cross-sell strategy.
-- ============================================================================================================================

WITH product_revenue AS (
    SELECT
        cat.category_name,
        p.product_id,
        p.product_name,
        ROUND(SUM(oi.quantity * oi.unit_price - oi.discount_amt), 2) AS revenue,
        RANK() OVER (
            PARTITION BY cat.category_name
            ORDER BY SUM(oi.quantity * oi.unit_price - oi.discount_amt) DESC
        )                                                              AS revenue_rank
    FROM   categories_clean  cat
    JOIN   products_clean    p   ON p.category_id  = cat.category_id
    JOIN   order_items_clean oi  ON oi.product_id  = p.product_id
    JOIN   orders_clean      o   ON o.order_id     = oi.order_id
    WHERE  o.status = 'Delivered'
    GROUP  BY cat.category_name, p.product_id, p.product_name
)
SELECT
    category_name,
    revenue_rank,
    product_name,
    revenue
FROM   product_revenue
ORDER  BY category_name, revenue_rank;


-- ============================================================================================================================
-- Q-06 : TOP 5 CATEGORIES BY TOTAL REFUND AMOUNT
-- Business use : Return cost analysis — high refund categories warrant quality or listing audits.
-- ============================================================================================================================

WITH category_refunds AS (
    SELECT
        cat.category_name,
        COUNT(DISTINCT r.return_id)             AS total_returns,
        ROUND(SUM(r.refund_amount), 2)          AS total_refunded,
        RANK() OVER (
            ORDER BY SUM(r.refund_amount) DESC
        )                                       AS refund_rank
    FROM   categories_clean  cat
    JOIN   products_clean    p   ON p.category_id  = cat.category_id
    JOIN   order_items_clean oi  ON oi.product_id  = p.product_id
    JOIN   orders_clean      o   ON o.order_id     = oi.order_id
    JOIN   returns_clean     r   ON r.order_id     = o.order_id
    WHERE  r.status = 'Approved'
    GROUP  BY cat.category_name
)
SELECT
    refund_rank,
    category_name,
    total_returns,
    total_refunded
FROM   category_refunds
WHERE  refund_rank <= 5
ORDER  BY refund_rank;


-- ============================================================================================================================
-- Q-07 : PRODUCT REVIEW TREND — IMPROVING, DECLINING, OR STABLE
-- Business use : Early warning system for quality degradation; monitor product health post-launch.
-- ============================================================================================================================

WITH monthly_ratings AS (
    SELECT
        p.product_id,
        p.product_name,
        DATE_TRUNC('month', r.review_date)      AS review_month,
        ROUND(AVG(r.rating), 2)                 AS avg_rating
    FROM   products_clean p
    JOIN   reviews_clean  r ON r.product_id = p.product_id
    GROUP  BY p.product_id, p.product_name, DATE_TRUNC('month', r.review_date)
),
with_lag AS (
    SELECT
        *,
        LAG(avg_rating) OVER (
            PARTITION BY product_id
            ORDER BY review_month
        )                                       AS prev_avg_rating
    FROM   monthly_ratings
),
latest_month AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY product_id
            ORDER BY review_month DESC
        )                                       AS rn
    FROM   with_lag
)
SELECT
    product_id,
    product_name,
    review_month                                AS latest_review_month,
    prev_avg_rating,
    avg_rating                                  AS current_avg_rating,
    CASE
        WHEN prev_avg_rating IS NULL          THEN 'Insufficient Data'
        WHEN avg_rating > prev_avg_rating     THEN 'Improving'
        WHEN avg_rating < prev_avg_rating     THEN 'Declining'
        ELSE                                       'Stable'
    END                                         AS rating_trend
FROM   latest_month
WHERE  rn = 1
ORDER  BY rating_trend, product_name;



-- ============================================================================================================================
-- Q-08 : 7-DAY ROLLING AVERAGE REVENUE
-- Business use : Smooth out daily revenue noise to identify underlying demand trends.
--               Essential for operations forecasting and anomaly detection.
-- ============================================================================================================================

WITH daily_revenue AS (
    SELECT
        order_date                              AS day,
        ROUND(SUM(total_amount), 2)             AS daily_revenue
    FROM   orders_clean
    WHERE  status = 'Delivered'
      AND  order_date IS NOT NULL
    GROUP  BY order_date
)
SELECT
    day,
    daily_revenue,
    ROUND(
        AVG(daily_revenue) OVER (
            ORDER BY day
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ),
        2
    )                                           AS rolling_7d_avg_revenue
FROM   daily_revenue
ORDER  BY day;


-- ============================================================================================================================
-- Q-09 : SELLERS BELOW PLATFORM AVERAGE RATING
-- Business use : Quality assurance — sellers consistently below average are candidates for
--               performance improvement plans or removal from the marketplace.
-- ============================================================================================================================

WITH seller_ratings AS (
    SELECT
        s.seller_id,
        s.seller_name,
        ROUND(AVG(r.rating), 2)             AS seller_avg_rating,
        COUNT(DISTINCT r.review_id)         AS total_reviews
    FROM   sellers_clean  s
    JOIN   products_clean p ON p.seller_id  = s.seller_id
    JOIN   reviews_clean  r ON r.product_id = p.product_id
    GROUP  BY s.seller_id, s.seller_name
),
platform_avg AS (
    SELECT ROUND(AVG(rating), 2) AS platform_avg_rating
    FROM   reviews_clean
)
SELECT
    sr.seller_id,
    sr.seller_name,
    sr.seller_avg_rating,
    sr.total_reviews,
    pa.platform_avg_rating,
    ROUND(sr.seller_avg_rating - pa.platform_avg_rating, 2) AS vs_platform_avg
FROM   seller_ratings  sr
CROSS  JOIN platform_avg pa
WHERE  sr.seller_avg_rating < pa.platform_avg_rating
ORDER  BY sr.seller_avg_rating;







