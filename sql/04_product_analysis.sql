-- ============================================================================================================================
-- PROJECT      : Amazon-Style E-Commerce Database — End-to-End SQL Analysis
-- FILE         : 04_product_analysis.sql
-- DESCRIPTION  : Product and category analytics — profitability, revenue contribution, ranking,
--                return analysis, review trends, price anomalies, and rolling revenue.
--                All queries run on the clean views created in 01_data_cleaning.sql.
-- DATABASE     : PostgreSQL 18
-- AUTHOR       : [Anshul]
-- LAST UPDATED : 2024
-- ============================================================================================================================


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


