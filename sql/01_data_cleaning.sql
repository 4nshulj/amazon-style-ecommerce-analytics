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
ORDER BY table_name;


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

  
    CASE
        WHEN order_date    ~ '^\d{4}-\d{2}-\d{2}$' THEN order_date::DATE
        ELSE NULL
    END                                                                     AS order_date,

    CASE
        WHEN delivery_date ~ '^\d{4}-\d{2}-\d{2}$' THEN delivery_date::DATE
        ELSE NULL
    END                                                                     AS delivery_date,

    
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

-- 6B. Business logic audit
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


