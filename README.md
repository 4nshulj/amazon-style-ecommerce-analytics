# 📦 Amazon-Style E-Commerce — End-to-End Data Analyst Portfolio Project

> **SQL data cleaning · Business analysis · Power BI dashboard · Storytelling insights**
> Built to demonstrate the complete workflow a Data Analyst follows in an industry setting.

---

## 🗂️ Table of Contents

1. [Project Overview](#-project-overview)
2. [Dataset Information](#-dataset-information)
3. [Repository Structure](#-repository-structure)
4. [Data Cleaning — SQL](#-data-cleaning--sql)
5. [Business Analysis — SQL](#-business-analysis--sql)
6. [Power BI Dashboard](#-power-bi-dashboard)
7. [Business Insights — September vs August 2024](#-business-insights--september-vs-august-2024)
8. [Key Findings](#-key-findings)
9. [Tools & Technologies](#-tools--technologies)
10. [How to Run This Project](#-how-to-run-this-project)

---

## 🎯 Project Overview

This project simulates the operational database of a large **Amazon-style global e-commerce marketplace**. It covers the complete data analyst lifecycle:

```
Raw Messy Data  →  SQL Cleaning  →  SQL Analysis  →  Power BI Dashboard  →  Business Insights
```

The dataset contains **9 related tables**, **9,500+ rows**, and **13 intentional data quality issues** — replicating what analysts encounter in real production systems. After cleaning and analysis in PostgreSQL, all results are visualised in a **4-page Power BI dashboard** connected via Import mode.

---

## 📊 Dataset Information

The dataset is modelled on Amazon's marketplace data structure and covers order activity from **2021 to 2024**.

| Table | Rows | Description |
|---|---|---|
| `customers` | 500 | Buyer profiles, demographics, Prime membership status |
| `sellers` | 14 | Marketplace vendor information and ratings |
| `categories` | 20 | Two-level product category hierarchy |
| `products` | 55 | Real-brand catalogue with pricing, stock, and ASIN |
| `orders` | 2,359 | Order headers — dates, status, shipping, totals |
| `order_items` | 2,836 | Line items — quantity, unit price, discount |
| `payments` | 1,020 | Payment transactions per order |
| `returns` | 180 | Return requests with reasons and refund status |
| `reviews` | 1,674 | Customer ratings and review text |

### Entity Relationships

```
customers ──< orders ──< order_items >── products >── categories
                  │                          │
                  ├──< payments         sellers ──< products
                  └──< returns
reviews >── products
reviews >── customers
```

### Intentional Data Quality Issues (13 Types)

| # | Issue | Tables Affected |
|---|---|---|
| 1 | Duplicate rows | customers, payments, sellers, reviews |
| 2 | Inconsistent text casing | All tables |
| 3 | Dates stored as VARCHAR (4 mixed formats) | customers, orders, payments, returns, reviews |
| 4 | Numeric amounts stored as VARCHAR | orders.total_amount, customers.age |
| 5 | Invalid numeric values (negative price, rating > 5, discount > 100%) | products, reviews |
| 6 | NULL in critical FK columns | order_items.product_id, payments.amount |
| 7 | Blank / placeholder values | customers.phone, sellers.phone |
| 8 | Future-dated records | orders, reviews |
| 9 | Orphan records (FK violations) | orders, returns |
| 10 | Business logic violations (return date before order date) | returns |
| 11 | Inconsistent categorical values | customers.gender, customers.prime_member |
| 12 | Inactive / test product records | products |
| 13 | Mixed country name formats | customers, sellers |

---

## 📁 Repository Structure

```amazon-ecommerce-analysis/
│
├── data/
│   ├── customers.csv
│   ├── sellers.csv
│   ├── categories.csv
│   ├── products.csv
│   ├── orders.csv
│   ├── order_items.csv
│   ├── payments.csv
│   ├── returns.csv
│   └── reviews.csv
│
├── sql/
│   └── Amazon_Project.sql
│
├── powerbi/
│   └── amazon.pbix
│
├── images/
│   ├── model.png
│   ├── dashboard_page1.png
│   ├── dashboard_page2.png
│   ├── dashboard_page3.png
│
├── Data Model.png
|
└── README.md
---

## 🧹 Data Cleaning — SQL

All cleaning is implemented in `Amazon_Project.sql` using a consistent **3-step pattern** for every table.

### Cleaning Architecture

```
Raw Table
    │
    ▼
STEP 1: Duplicate Audit
    ROW_NUMBER() OVER (PARTITION BY natural_key ORDER BY primary_key)
    │
    ▼
STEP 2: Staging Table
    CREATE TABLE IF NOT EXISTS stg_{table} AS SELECT * FROM {table}
    │
    ▼
STEP 3: Clean View
    CREATE OR REPLACE VIEW {table}_clean AS
    SELECT (standardised, cast, null-handled columns) FROM stg_{table}
```

### What Was Cleaned Per Table

**customers_clean**
- Duplicate detection partitioned on `email + phone` (natural composite key)
- Email validated with regex — invalids flagged as `'invalid_email'` rather than silently dropped
- Phone stripped of all non-digit characters using `REGEXP_REPLACE`, empty result → `NULL`
- Country normalised: `'US'`, `'USA'`, `'U.S.A'`, `'UNITED STATES'` → `'United States'`
- Age: non-numeric values and out-of-range integers → `NULL`
- Gender: `'M'`/`'MALE'`/`'male'` → `'Male'`, `'F'`/`'FEMALE'` → `'Female'`
- `signup_date` parsed from 4 observed formats to `DATE` using regex-guarded `CASE WHEN`
- `prime_member`: `'YES'`/`'Y'`/`'1'`/`'TRUE'` → `'Yes'`, falsy variants → `'No'`

**orders_clean**
- Duplicate detection partitioned on `order_id + customer_id + order_date + coupon_code`
- `order_date` and `delivery_date` cast from `VARCHAR` to `DATE` with regex guard
- `total_amount` cast from `VARCHAR` to `NUMERIC` — non-numeric values → `NULL`
- Future-dated orders flagged as `'Invalid'` rather than deleted (preserves audit trail)
- `coupon_code`: empty strings → `'No Coupon'`
- All text status/method columns standardised with `INITCAP(TRIM(...))`

**order_items_clean**
- Duplicate detection partitioned on `item_id + order_id + product_id + discount_amt`
- Rows with `quantity <= 0` or `product_id IS NULL` excluded from clean view
- `discount_amt` NULL → `0` via `COALESCE`

**payments_clean**
- Duplicate detection partitioned on `order_id + transaction_id` (true payment duplicate)
- `payment_date` cast from `VARCHAR` to `DATE` with regex guard
- Status standardised with `INITCAP(TRIM(...))`

**returns_clean**
- Business logic violation detected: return date before corresponding order date
- Violating rows excluded from clean view via `JOIN + WHERE NOT` pattern
- `reason` empty string → `'Not Specified'` via `COALESCE(NULLIF(...))`

**products_clean**
- Products with `price <= 0` or `discount_pct > 100` overridden to `status = 'Inactive'`
- `asin` standardised with `UPPER(TRIM(...))`

**reviews_clean**
- Ratings outside valid range `1–5` excluded
- Future-dated reviews excluded
- Duplicate reviews detected on `review_id + product_id + customer_id + review_date + rating`

**sellers_clean**
- Duplicate detection on `seller_name + email + city + year_joined`
- Phone cleaned identically to customers
- `avg_rating` and `year_joined` retained as native `NUMERIC` and `INT` types (not cast to TEXT)

### Post-Cleaning Validation

After all views are created, a 10-assertion validation checklist confirms:

```sql
-- Every query below should return 0 rows

-- V-01: No duplicate customer emails
SELECT email, COUNT(*) FROM customers_clean GROUP BY email HAVING COUNT(*) > 1;

-- V-02: No invalid gender values
SELECT DISTINCT gender FROM customers_clean
WHERE gender NOT IN ('Male','Female','Non-Binary') AND gender IS NOT NULL;

-- V-03: No future order dates still marked as valid
SELECT order_id, order_date FROM orders_clean
WHERE order_date > CURRENT_DATE AND status <> 'Invalid';

-- V-04: No zero or negative quantities
SELECT COUNT(*) FROM order_items_clean WHERE quantity <= 0;

-- V-05: No ratings outside 1–5
SELECT COUNT(*) FROM reviews_clean WHERE rating NOT BETWEEN 1 AND 5;

-- (+ 5 more assertions covering payments, returns, products, and referential integrity)
```

---

## 📈 Business Analysis — SQL

All analysis runs on the `_clean` views and is structured across three sections: **KPI Analysis**, **Customer Analysis**, and **Product Analysis**.

### KPI Analysis (13 queries)

| Query | Business Question | SQL Concept |
|---|---|---|
| Q-01 | Top 10 products by units sold | `GROUP BY`, `SUM`, `ORDER BY`, `LIMIT` |
| Q-02 | Monthly order volume — 2023 | `EXTRACT`, `DATE_TRUNC`, `TO_CHAR` |
| Q-03 | Revenue by product category (Delivered orders) | 4-table `JOIN`, `SUM` |
| Q-04 | Prime members who never placed an order | `LEFT JOIN`, `IS NULL` |
| Q-05 | Average order value by payment method | `JOIN`, `AVG`, `GROUP BY` |
| Q-06 | Monthly cancellation rate — 2022 and 2023 | `CTE`, `CASE WHEN`, percentage |
| Q-07 | Top 10 US states by customer count | `WHERE`, `GROUP BY`, `COUNT` |
| Q-08 | Average seller rating and review volume | 3-table `JOIN`, `AVG`, `COUNT DISTINCT` |
| Q-09 | Coupon usage rate for delivered orders | `SUM CASE WHEN`, `NULLIF`, percentage |
| Q-10 | Top 5 products by return rate | `LEFT JOIN`, safe division with `NULLIF` |
| Q-11 | Refund rate by payment method | `CASE WHEN`, percentage, `GROUP BY` |
| Q-12 | Average delivery time with SLA flag | `CTE`, date arithmetic, `CASE WHEN` |
| Q-13 | Executive summary — all KPIs in one row | `CTE`, `CROSS JOIN`, `ROW_NUMBER` |

### Customer Analysis (9 queries)

| Query | Business Question | SQL Concept |
|---|---|---|
| Q-01 | Top 10 customers by lifetime value | `GROUP BY`, `SUM`, `ORDER BY` |
| Q-02 | Customers with above-average LTV | `CTE`, scalar subquery |
| Q-03 | Top 3 customers per segment | `ROW_NUMBER() OVER (PARTITION BY segment)` |
| Q-04 | Prime vs Non-Prime revenue by quarter | `DATE_TRUNC('quarter')`, `CASE WHEN` |
| Q-05 | Repeat customers (3+ distinct months) | `COUNT(DISTINCT DATE_TRUNC(...))`, `HAVING` |
| Q-06 | Average gap between consecutive orders | `LAG() OVER (PARTITION BY customer_id)` |
| Q-07 | Q1 2022 cohort retention analysis | `CTE`, `MIN` date, conditional `COUNT DISTINCT` |
| Q-08 | RFM customer segmentation | `NTILE(4)`, `CTE`, `SWITCH` |
| Q-09 | Top 10% customers by revenue (Pareto) | `PERCENTILE_CONT(0.90)`, `CROSS JOIN` |

### Product Analysis (9 queries)

| Query | Business Question | SQL Concept |
|---|---|---|
| Q-01 | Profit margin % by category | `AVG`, computed column, `NULLIF` |
| Q-02 | Category revenue as % of total | `SUM() OVER ()` window function |
| Q-03 | Category MoM revenue growth | `LAG() OVER (PARTITION BY category)` |
| Q-04 | Platform-level MoM revenue growth (2023) | `LAG() OVER (ORDER BY month)` |
| Q-05 | Ranked products within each category | `RANK() OVER (PARTITION BY category)` |
| Q-06 | Top 5 categories by approved refund amount | `CTE`, `RANK() OVER`, join path fix |
| Q-07 | Product review trend (Improving/Declining/Stable) | `LAG`, `ROW_NUMBER`, `CASE WHEN` |
| Q-08 | 7-day rolling average revenue | `AVG() OVER (ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)` |
| Q-09 | Sellers below platform average rating | `CROSS JOIN`, scalar subquery |

### SQL Concepts Demonstrated

```
Window Functions    → ROW_NUMBER, RANK, NTILE, LAG, AVG OVER, SUM OVER
CTEs                → Chained CTEs, self-referencing patterns
Multi-table JOINs   → Up to 5 tables in a single query
Date Functions      → DATE_TRUNC, EXTRACT, TO_CHAR, TO_DATE
Type Casting        → VARCHAR → DATE, VARCHAR → NUMERIC with regex guards
Safe Division       → NULLIF() in all denominators — no divide-by-zero errors
Regex Validation    → ~ operator for format checks before casting
Cohort Analysis     → First-order date + conditional COUNT DISTINCT per quarter
RFM Segmentation   → NTILE(4) with correct recency scoring direction
```

---

## 📊 Power BI Dashboard

The dashboard is connected to PostgreSQL via **Import Mode** and contains **4 pages**.

### Page 1 — Executive Overview

| Visual | Description |
|---|---|
| 5 KPI Cards | Total Revenue · Total Orders · AOV · Return Rate · MoM Growth |
| Revenue by Month | Clustered column + line combo showing MoM growth annotation |
| Revenue by Category | Donut chart — Electronics leads at 43% |
| Payment Method Contribution | Horizontal bar showing % split by method |
| Top 10 Products by Revenue | Horizontal bar sorted descending |
| Order Status Breakdown | 100% stacked bar showing Delivered/Shipped/Cancelled/Returned/Processing |
| Orders from Countries | Filled map by ship_country |

**DAX Measures (Page 1)**
```dax
Total Revenue =
CALCULATE(SUM(orders_clean[total_amount]), orders_clean[status] = "Delivered")

Total Orders = CALCULATE(COUNT('public order_items_clean'[order_id]),'public orders_clean'[status]="Delivered")

AOV = DIVIDE([Total Revenue], [Total Orders], 0)

Return Rate% = DIVIDE(DISTINCTCOUNT('public returns_clean'[return_id]),[Total Orders])*100.0

MoM Growth = VAR PREVIOS_MONTH= CALCULATE([Total Revenue],DATEADD('Calendar'[Date],-1,MONTH))
RETURN
DIVIDE([Total Revenue]-PREVIOS_MONTH,PREVIOS_MONTH,0)

```

---

### Page 2 — Customer Analytics

| Visual | Description |
|---|---|
| 4  KPI Cards  | Total Customers · Prime Customers · Repeat Customers · Never Orderd Prime Customers |
| Revenue by Customer Segment | Horizontal bar — uses `Customer Segment` calculated column |
| Gender Breakdown By Orders | Donut chart by customer gender|
| Prime vs Non-Prime by Quarter | Stacked column — 8 quarters across 2022–2023 |
| State Geography | Top 10 states bar chart |



**DAX Measures (Page 2)**
```dax
Repeat Customers% = 
VAR Retaibed= COUNTROWS(FILTER(VALUES('public orders_clean'[customer_id]),CALCULATE(COUNTROWS('public orders_clean'),'public orders_clean'[status]="Delivered")>=2))
VAR total= DISTINCTCOUNT('public orders_clean'[customer_id])
RETURN
DIVIDE(Retained,total,0)

```

---

### Page 3 — Order Analytics

| Visual | Description |
|---|---|
| 4 KPI Cards | Avg Platform Rating · Total Reviews · Total Approved Refunds · Refunds Amount |
| Revenue vs SPLY Line | Current year vs same period last year using `SAMEPERIODLASTYEAR` |
| Category Revenue Treemap | Proportional blocks by revenue — Electronics largest |
| Product Review Trend Table | Improving / Stable / Declining with rating sparklines |
| Return Reason Breakdown | Progress bars for top 4 reasons |


**DAX Measures (Page 3)**
```dax


Total Refund Amount =
CALCULATE(SUM(returns_clean[refund_amount]), returns_clean[status] = "Approved")

Revenue SPLY =
CALCULATE([Total Revenue], SAMEPERIODLASTYEAR('Date Table'[Date]))

YoY Growth % = DIVIDE([Total Revenue] - [Revenue SPLY], [Revenue SPLY], 0) * 100
```

---

### Page 4 — Monthly Insights (September vs August 2024)

The storytelling page comparing the two most recent full months.

## 💡 Business Insights — September vs August 2024

### The Story of September

September 2024 delivered the platform's strongest month-over-month revenue growth at **+45.54%**, driven by a surge in female buyers from 41% to **54.41%** — the largest single-month gender shift in the dataset. This new buyer cohort drove a product preference switch from the **Canon EOS R6 Mark II** (August's top product) to the **Sony A7 IV Mirrorless Camera** (September's top), both priced at $2,499. **PayPal** overtook Credit Card as the #1 payment method, consistent with the mobile-first checkout behaviour of the growing female buyer base. However, the return rate climbed to **11.76%** — crossing the 10% alert threshold — and Non-Prime revenue quietly contracted **3%** through Q3, two signals requiring attention before Q4 peak season.

### Month Comparison

| Metric | September 2024 | August 2024 | Change |
|---|---|---|---|
| Revenue | $148.2K | $101.8K | **+45.54%** |
| Orders | 99 | 68 | **+45.6%** |
| Average Order Value | $1,490 | $1,497 | −$7 (flat) |
| Return Rate | 11.76% | 8.82% | **+2.94pp ⚠** |
| Top Product | Sony A7 IV | Canon EOS R6 II | Switched |
| Top Payment | PayPal (32%) | Credit Card (38%) | Switched |

### Gender Distribution

| Gender | August 2024 | September 2024 | Change |
|---|---|---|---|
| Female | 41.28% | 54.41% | **+13.13 pp ↑** |
| Male | 34.64% | 24.02% | −10.62 pp ↓ |
| Non-Binary | 24.08% | 21.57% | −2.51 pp ↓ |

---

## 🔍 Key Findings

### Revenue & Growth

**Finding 1 — Electronics leads revenue but with the lowest margin**
Electronics generates 43% of total platform revenue but carries only a 28% profit margin — the lowest of any category. Books generate 67% margin on 7% of revenue. The platform is volume-led in Electronics but profitability-led in smaller categories.
> **Recommendation:** Cross-promote high-margin categories (Books, Beauty) to Electronics buyers using post-purchase email sequences.

**Finding 2 — Q4 is the strongest revenue quarter consistently**
Month-over-month analysis shows revenue acceleration starting in October and peaking in December across all years in the dataset. The sharpest single-month jump occurs in November.
> **Recommendation:** Front-load inventory for the top 10 SKUs from mid-October. Increase ad spend in October to capture early Q4 demand.

**Finding 3 — September 2024 MoM growth of +45.54% is driven by volume, not ticket size**
The AOV in September ($1,490) was virtually identical to August ($1,497). Growth came entirely from order volume — 99 vs 68 orders. This suggests the female buyer surge increased the customer count, not the spend per customer.
> **Recommendation:** Investigate the channel that brought in the new female buyers in September and replicate it in Q4.

### Customer Behaviour

**Finding 4 — Top 10% of customers contribute ~61% of total revenue**
The P90 revenue threshold is significantly above the platform average LTV, confirming a classic Pareto distribution. Revenue is highly concentrated in a small group of Champions and VIP customers.
> **Recommendation:** Create a dedicated VIP programme for this cohort — personalised service, early product access, and priority support reduce churn risk for the highest-value accounts.

**Finding 5 — Prime members (43% of base) generate 67% of revenue**
Prime members have materially higher AOV and order frequency than Non-Prime customers. The gap widened each quarter in 2023, suggesting compounding engagement effects.
> **Recommendation:** Convert Returning and Potential Loyalist RFM segments to Prime membership — these are the customers most likely to convert if given a time-limited incentive.

**Finding 6 — Q1 2022 cohort retention drops sharply — only 15% active by Q4**
Of the 284 customers who placed their first order in Q1 2022, only 108 (38%) placed another order in Q2, dropping to 68 (24%) in Q3 and 42 (15%) in Q4. This indicates a weak post-purchase engagement loop.
> **Recommendation:** Introduce a 3-touch post-purchase email sequence (Days 3, 7, 30) with personalised product recommendations based on the first purchase category.

**Finding 7 — Average repurchase cycle is 47 days**
Customers who ordered in 3 or more distinct months have an average gap of 47 days between consecutive orders. This is the platform's natural repurchase cycle.
> **Recommendation:** Trigger automated replenishment nudges at Day 40 post-purchase for consumable categories — Grocery, Beauty, and Sports supplements.

### Product & Seller Health

**Finding 8 — September return rate of 11.76% crosses the 10% alert threshold**
The camera category is the likely driver given the Sony A7 IV's high September order volume. Even a small number of returns on a $2,499 item has an outsized impact on the return rate percentage.
> **Recommendation:** Audit the Sony A7 IV product listing for accuracy. Review post-purchase feedback from September buyers. Determine if the primary return reason is "not as described" or "defective" — the fix differs depending on the cause.

**Finding 9 — Non-Prime revenue contracted 3% in Q3 — first quarter-over-quarter decline**
While Prime revenue continued growing, Non-Prime revenue fell 3% from Q2 to Q3 2024. This is the first QoQ decline for this segment in the dataset.
> **Recommendation:** With Q4 being historically the highest-revenue quarter, now is the optimal window for a Prime conversion campaign targeting the At-Risk/Lost RFM segment.

**Finding 10 — GadgetWorld and AutoParts Direct are below the platform average rating**
Both sellers have ratings below the platform average of 4.54. GadgetWorld (3.9) and AutoParts Direct (3.7) both have declining product review trends in the last 2 months of the dataset.
> **Recommendation:** Issue a quality improvement notice to both sellers. Set a 60-day rating improvement target. If no improvement, escalate to de-listing review.

**Finding 11 — PayPal refund rate (8.1%) is 4× that of Amazon Pay (3.2%)**
The September payment method switch to PayPal, combined with the elevated return rate, creates a compounding risk — more refunds processed through a higher-refund-rate channel.
> **Recommendation:** Review the Gift Card and PayPal refund UX flows. Consider exchanging for store credit rather than cash refund to retain revenue on the platform.

**Finding 12 — 84 Prime members have never placed an order**
These are high-intent subscribers who paid for Prime but never converted to their first purchase. They represent a zero-acquisition-cost conversion opportunity.
> **Recommendation:** Trigger a personalised onboarding sequence for Prime zero-order members — highlight exclusive benefits and offer a first-order incentive with a 14-day deadline.

---

## 🛠️ Tools & Technologies

| Tool | Version | Purpose |
|---|---|---|
| PostgreSQL | 18.3 | Database engine, data storage, cleaning and analysis |
| pgAdmin 4 / DBeaver | Latest | Query execution and schema management |
| Power BI Desktop | Latest | Dashboard, visualisation, DAX measures |
| Git / GitHub | — | Version control and portfolio hosting |

---

## ▶️ How to Run This Project

### Prerequisites
- PostgreSQL 15+ installed and running
- pgAdmin 4 or DBeaver (any PostgreSQL client)
- Power BI Desktop (free download from Microsoft)

### Step 1 — Set up the database

```bash
# Connect to PostgreSQL
psql -U postgres

# Create the database
CREATE DATABASE amazon_ecommerce;
\c amazon_ecommerce
```

### Step 2 — Import the CSV data

In pgAdmin, right-click each table → Import/Export → select the corresponding CSV file from the `data/` folder. Load tables in this order (parent tables before child tables):

```
1. customers    2. sellers    3. categories    4. products
5. orders       6. order_items               7. payments
8. returns      9. reviews
```

Or use `\COPY` in psql:
```sql
\COPY customers FROM 'data/customers.csv' WITH (FORMAT csv, HEADER true, NULL '');
-- Repeat for all 9 tables
```

### Step 3 — Run the SQL pipeline

```bash
psql -U postgres -d amazon_ecommerce -f sql/Amazon_Project.sql
```

This runs in order: schema creation → cleaning (staging tables + clean views) → all analysis queries.

### Step 4 — Open the Power BI dashboard

1. Open `powerbi/amazon.pbix` in Power BI Desktop
2. In Home → Transform Data → Data source settings → update the PostgreSQL server to `localhost` and database to `amazon_ecommerce`
3. Click **Refresh** — all 4 pages will populate with your data

### Step 5 — Verify

```sql
-- Confirm all clean views exist
SELECT viewname FROM pg_views
WHERE schemaname = 'public'
  AND viewname LIKE '%_clean'
ORDER BY viewname;

-- Confirm row counts after cleaning
SELECT 'customers_clean', COUNT(*) FROM customers_clean UNION ALL
SELECT 'orders_clean',    COUNT(*) FROM orders_clean    UNION ALL
SELECT 'products_clean',  COUNT(*) FROM products_clean;
```

---

## 📬 Connect

## 👤 Author
**Anshul**

Aspiring Data Analyst | Python · SQL · Power BI
📧 [1311anshul@gmail.com] | 🔗 [LinkedIn](https://www.linkedin.com/in/anshuljangra8/) 


---

*All data is synthetically generated for educational purposes. Real brand names are used for realism only — this project has no affiliation with Amazon or any named brand.*
