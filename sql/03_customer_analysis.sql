-- ============================================================================================================================
-- PROJECT      : Amazon-Style E-Commerce Database — End-to-End SQL Analysis
-- FILE         : 03_customer_analysis.sql
-- DESCRIPTION  : Deep-dive customer analytics — lifetime value, segmentation, cohort retention,
--                RFM scoring, purchase frequency, and Prime vs Non-Prime revenue split.
--                All queries run on the clean views created in 01_data_cleaning.sql.
-- DATABASE     : PostgreSQL 18
-- AUTHOR       : [Anshul]
-- LAST UPDATED : 2026
-- ============================================================================================================================


-- ============================================================================================================================
-- Q-01 : TOP 10 CUSTOMERS BY LIFETIME VALUE (LTV)
-- Business use : Identify highest-value customers for VIP treatment, retention offers, and upsell targeting.
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
-- Business use : Measure purchase loyalty beyond simple order counts; identify habitual buyers.
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


