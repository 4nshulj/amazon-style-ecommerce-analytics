-- ============================================================================================================================
-- PROJECT      : Amazon-Style E-Commerce Database — End-to-End SQL Analysis
-- FILE         : 02_kpi_analysis.sql
-- DESCRIPTION  : Core business KPIs — revenue, orders, delivery performance, coupon usage,
--                payment behaviour, and an executive summary dashboard query.
--                All queries run on the clean views created in 01_data_cleaning.sql.
-- DATABASE     : PostgreSQL 18
-- AUTHOR       : [Anshul]
-- LAST UPDATED : 2026
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
