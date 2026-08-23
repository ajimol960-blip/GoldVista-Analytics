-- ======================================
-- SECTION 3 : BUSINESS CHALLENGES
-- ======================================

-- C-01 Branch Performance Gap
--What is the revenue, total weight sold, and average transaction value by branch?
SELECT
    b.branch_name,
    COUNT(DISTINCT fs.invoice_id) AS total_invoices,
    SUM(fs.total_amount) AS total_revenue,
    SUM(fs.net_weight) AS total_weight_sold,
    ROUND(
        (SUM(fs.total_amount) /
        COUNT(DISTINCT fs.invoice_id))::numeric,2
    ) AS avg_transaction_value
FROM fact_sales fs
JOIN dim_branch b
ON fs.branch_id = b.branch_id
GROUP BY b.branch_name
ORDER BY total_revenue DESC;
--Which branches lead in weight sold versus revenue?
SELECT
    b.branch_name,
    SUM(fs.net_weight) AS total_weight,
    SUM(fs.total_amount) AS total_revenue
FROM fact_sales fs
JOIN dim_branch b
ON fs.branch_id = b.branch_id
GROUP BY b.branch_name
ORDER BY total_weight DESC;
--How does the karat mix differ across branches?
SELECT
    b.branch_name,
    k.karat_name,
    SUM(fs.total_amount) AS revenue,
    SUM(fs.net_weight) AS total_weight
FROM fact_sales fs
JOIN dim_branch b
    ON fs.branch_id = b.branch_id
JOIN dim_item i
    ON fs.item_id = i.item_id
JOIN dim_karat k
    ON i.karat_id = k.karat_id
GROUP BY
    b.branch_name,
    k.karat_name
ORDER BY
    b.branch_name,
    revenue DESC;
--What is the Making Charge Revenue by Branch?
SELECT
    b.branch_name,
    SUM(fs.making_amount) AS total_making_charge,
    ROUND(AVG(fs.making_amount)::numeric,2) AS avg_making_charge
FROM fact_sales fs
JOIN dim_branch b
    ON fs.branch_id = b.branch_id
GROUP BY b.branch_name
ORDER BY total_making_charge DESC;
--Which branches are growing and which are declining over the 13-month period?
SELECT
    b.branch_name,
    fs.sale_year,
    fs.sale_month,
    SUM(fs.total_amount) AS monthly_revenue
FROM fact_sales fs
JOIN dim_branch b
    ON fs.branch_id = b.branch_id
GROUP BY
    b.branch_name,
    fs.sale_year,
    fs.sale_month
ORDER BY
    b.branch_name,
    fs.sale_year,
    fs.sale_month;
--How does the item type mix (Ring, Chain, Coin, Earring, Necklace, etc.) differ by branch?
SELECT
    b.branch_name,
    it.item_type_name,
    SUM(fs.total_amount) AS total_revenue,
    SUM(fs.net_weight) AS total_weight,
    COUNT(DISTINCT fs.invoice_id) AS total_invoices
FROM fact_sales fs
JOIN dim_branch b
    ON fs.branch_id = b.branch_id
JOIN dim_item i
    ON fs.item_id = i.item_id
JOIN dim_item_type it
    ON i.item_type_id = it.item_type_id
GROUP BY
    b.branch_name,
    it.item_type_name
ORDER BY
    b.branch_name,
    total_revenue DESC;
--Challenge C-02: Customer Retention & Repeat Buying.
--What percentage of customers have made only 1 purchase vs. 2 or more purchases?

--Step 1: Count purchases per customer
WITH CustomerPurchases AS (
    SELECT
        customer_id,
        COUNT(DISTINCT invoice_id) AS purchase_count
    FROM fact_sales
    GROUP BY customer_id
)

SELECT
    CASE
        WHEN purchase_count = 1 THEN 'One-Time Customer'
        ELSE 'Repeat Customer'
    END AS customer_type,
    COUNT(*) AS total_customers,
    ROUND(
        (COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER ())::numeric,
        2
    ) AS percentage
FROM CustomerPurchases
GROUP BY customer_type
ORDER BY total_customers DESC;
--What is the average time gap between the first and second purchase?
WITH CustomerOrders AS (
    SELECT
        customer_id,
        invoice_date,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY invoice_date
        ) AS purchase_number
    FROM fact_sales
),
FirstSecondPurchase AS (
    SELECT
        customer_id,
        MAX(CASE WHEN purchase_number = 1 THEN invoice_date END) AS first_purchase,
        MAX(CASE WHEN purchase_number = 2 THEN invoice_date END) AS second_purchase
    FROM CustomerOrders
    GROUP BY customer_id
)
SELECT
    ROUND(AVG(second_purchase - first_purchase), 2) AS avg_days_between_purchases
FROM FirstSecondPurchase
WHERE second_purchase IS NOT NULL;
--Which branches have the highest repeat customer rate?
WITH CustomerBranchPurchases AS (
    SELECT
        branch_id,
        customer_id,
        COUNT(DISTINCT invoice_id) AS purchase_count
    FROM fact_sales
    GROUP BY branch_id, customer_id
)
SELECT
    b.branch_name,
    COUNT(*) AS total_customers,
    COUNT(*) FILTER (WHERE purchase_count > 1) AS repeat_customers,
    ROUND(
        (
            COUNT(*) FILTER (WHERE purchase_count > 1) * 100.0
            / COUNT(*)
        )::numeric,
        2
    ) AS repeat_customer_rate
FROM CustomerBranchPurchases cb
JOIN dim_branch b
    ON cb.branch_id = b.branch_id
GROUP BY b.branch_name
ORDER BY repeat_customer_rate DESC;
--Do customers who sell old gold (buy-back) return more often for new purchases?
WITH SalesCustomers AS (
    SELECT
        customer_id,
        COUNT(DISTINCT invoice_id) AS purchase_count
    FROM fact_sales
    GROUP BY customer_id
),
OldGoldCustomers AS (
    SELECT DISTINCT customer_id
    FROM fact_old_gold_purchase
)

SELECT
    CASE
        WHEN og.customer_id IS NOT NULL THEN 'Old Gold Customer'
        ELSE 'Regular Customer'
    END AS customer_group,
    COUNT(*) AS total_customers,
    COUNT(*) FILTER (WHERE s.purchase_count > 1) AS repeat_customers,
    ROUND(
        (
            COUNT(*) FILTER (WHERE s.purchase_count > 1) * 100.0
            / COUNT(*)
        )::numeric,
        2
    ) AS repeat_rate
FROM SalesCustomers s
LEFT JOIN OldGoldCustomers og
ON s.customer_id = og.customer_id
GROUP BY customer_group;
--Customer Lifetime Value (CLV)
--What is the average lifetime value (total spend) of repeat customers vs one-time buyers?
WITH CustomerSummary AS (
    SELECT
        customer_id,
        COUNT(DISTINCT invoice_id) AS purchase_count,
        SUM(total_amount) AS lifetime_value
    FROM fact_sales
    GROUP BY customer_id
)

SELECT
    CASE
        WHEN purchase_count = 1 THEN 'One-Time Customer'
        ELSE 'Repeat Customer'
    END AS customer_type,
    COUNT(*) AS total_customers,
    ROUND(AVG(lifetime_value)::numeric,2) AS avg_lifetime_value,
    ROUND(SUM(lifetime_value)::numeric,2) AS total_lifetime_value
FROM CustomerSummary
GROUP BY customer_type
ORDER BY avg_lifetime_value DESC;
--Customer Segmentation
--Can you segment customers into meaningful groups (e.g., High-Value Regulars, Occasional Buyers, One-Time Buyers)?
WITH CustomerSummary AS (
    SELECT
        customer_id,
        COUNT(DISTINCT invoice_id) AS purchase_count,
        SUM(total_amount) AS lifetime_value
    FROM fact_sales
    GROUP BY customer_id
)

SELECT
    CASE
        WHEN purchase_count = 1 THEN 'One-Time Buyer'
        WHEN purchase_count BETWEEN 2 AND 3 THEN 'Occasional Buyer'
        WHEN purchase_count >= 4
             AND lifetime_value >= 50000 THEN 'High-Value Regular'
        ELSE 'Regular Buyer'
    END AS customer_segment,

    COUNT(*) AS total_customers,

    ROUND(AVG(lifetime_value)::numeric,2) AS avg_spend,

    ROUND(SUM(lifetime_value)::numeric,2) AS total_revenue

FROM CustomerSummary

GROUP BY customer_segment

ORDER BY total_revenue DESC;
--How does retention vary by registration month (cohort analysis)?
WITH CustomerCohort AS (
    SELECT
        customer_id,
        MIN(invoice_date) AS first_purchase_date
    FROM fact_sales
    GROUP BY customer_id
)

SELECT
    DATE_TRUNC('month', first_purchase_date) AS cohort_month,
    COUNT(*) AS new_customers
FROM CustomerCohort
GROUP BY cohort_month
ORDER BY cohort_month;

--C-03: Return Rate Analysis.
--Overall Return Rate
SELECT
    (SELECT COUNT(DISTINCT invoice_id) FROM fact_sales) AS total_sales,
    (SELECT COUNT(DISTINCT return_id) FROM fact_returns) AS total_returns,
    ROUND(
        (
            (SELECT COUNT(DISTINCT return_id) FROM fact_returns) * 100.0 /
            (SELECT COUNT(DISTINCT invoice_id) FROM fact_sales)
        )::numeric,
        2
    ) AS return_rate_percentage;
--Financial Impact of Returns
SELECT
    COUNT(DISTINCT return_id) AS total_returns,
    ROUND(SUM(total_amount)::numeric,2) AS total_return_value,
    ROUND(AVG(total_amount)::numeric,2) AS average_return_value
FROM fact_returns;
--Which branches have the highest return rates?
SELECT
    b.branch_name,
    COUNT(DISTINCT fr.return_id) AS total_returns,
    ROUND(SUM(fr.total_amount)::numeric,2) AS return_value
FROM fact_returns fr
JOIN dim_branch b
ON fr.branch_id = b.branch_id
GROUP BY b.branch_name
ORDER BY total_returns DESC;
--Are some karats returned more than others?
SELECT
    k.karat_name,
    COUNT(DISTINCT fr.return_id) AS total_returns,
    ROUND(SUM(fr.total_amount)::numeric,2) AS return_value
FROM fact_returns fr
JOIN dim_item i
ON fr.item_id = i.item_id
JOIN dim_karat k
ON i.karat_id = k.karat_id
GROUP BY k.karat_name
ORDER BY total_returns DESC;
--Which item types have the highest returns?
SELECT
    it.item_type_name,
    COUNT(DISTINCT fr.return_id) AS total_returns,
    ROUND(SUM(fr.total_amount)::numeric,2) AS return_value
FROM fact_returns fr
JOIN dim_item i
ON fr.item_id = i.item_id
JOIN dim_item_type it
ON i.item_type_id = it.item_type_id
GROUP BY it.item_type_name
ORDER BY total_returns DESC;
--Average Time Between Purchase and Return
SELECT
    ROUND(
        AVG(fr.return_date - fs.invoice_date)::numeric,
        2
    ) AS avg_days_to_return
FROM fact_returns fr
JOIN fact_sales fs
    ON fr.original_invoice_id = fs.invoice_id;
--Does a higher discount lead to more returns?
SELECT
    CASE
        WHEN discount_percentage = 0 THEN 'No Discount'
        WHEN discount_percentage <= 5 THEN '1–5%'
        WHEN discount_percentage <= 10 THEN '6–10%'
        ELSE 'Above 10%'
    END AS discount_group,

    COUNT(*) AS total_returns,
    ROUND(AVG(total_amount)::numeric,2) AS avg_return_value

FROM fact_returns
GROUP BY discount_group
ORDER BY total_returns DESC;
--Challenge C-04: Payment Mode Trends.
--What is the payment mode split (Cash vs MADA vs Cheque vs others) by value?
SELECT
    pm.payment_mode_name,
    COUNT(*) AS total_transactions,
    ROUND(SUM(sp.amount)::numeric,2) AS total_amount,
    ROUND(AVG(sp.amount)::numeric,2) AS average_amount
FROM fact_sales_payment sp
JOIN dim_payment_mode pm
ON sp.payment_mode_id = pm.payment_mode_id
GROUP BY pm.payment_mode_name
ORDER BY total_amount DESC;
--How has the payment mode mix changed over the 13-month period?
SELECT
    fs.sale_year,
    fs.sale_month,
    pm.payment_mode_name,
    ROUND(SUM(sp.amount)::numeric,2) AS total_amount
FROM fact_sales_payment sp
JOIN fact_sales fs
ON sp.invoice_id = fs.invoice_id
JOIN dim_payment_mode pm
ON sp.payment_mode_id = pm.payment_mode_id
GROUP BY
    fs.sale_year,
    fs.sale_month,
    pm.payment_mode_name
ORDER BY
    fs.sale_year,
    fs.sale_month,
    pm.payment_mode_name;
--Do certain branches have a different payment profile?
SELECT
    b.branch_name,
    pm.payment_mode_name,
    COUNT(*) AS transactions,
    ROUND(SUM(sp.amount)::numeric,2) AS total_amount
FROM fact_sales_payment sp
JOIN fact_sales fs
ON sp.invoice_id = fs.invoice_id
JOIN dim_branch b
ON fs.branch_id = b.branch_id
JOIN dim_payment_mode pm
ON sp.payment_mode_id = pm.payment_mode_id
GROUP BY
    b.branch_name,
    pm.payment_mode_name
ORDER BY
    b.branch_name,
    total_amount DESC;
--Advance Receipts
SELECT
    is_advance,
    COUNT(*) AS total_transactions
FROM fact_sales_payment
GROUP BY is_advance;
--Do larger purchases use different payment methods?
SELECT
    pm.payment_mode_name,
    ROUND(AVG(fs.total_amount)::numeric,2) AS avg_invoice_value,
    ROUND(MAX(fs.total_amount)::numeric,2) AS highest_invoice_value,
    COUNT(DISTINCT fs.invoice_id) AS invoices
FROM fact_sales_payment sp
JOIN fact_sales fs
    ON sp.invoice_id = fs.invoice_id
JOIN dim_payment_mode pm
    ON sp.payment_mode_id = pm.payment_mode_id
GROUP BY pm.payment_mode_name
ORDER BY avg_invoice_value DESC;
--What percentage of invoices use multiple payment methods?
WITH PaymentCount AS (
    SELECT
        invoice_id,
        COUNT(DISTINCT payment_mode_id) AS payment_modes
    FROM fact_sales_payment
    GROUP BY invoice_id
)
SELECT
    payment_modes,
    COUNT(*) AS invoices,
    ROUND(
        (COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER ())::numeric,
        2
    ) AS percentage
FROM PaymentCount
GROUP BY payment_modes
ORDER BY payment_modes;
--C-05 – Old Gold Buy-Back Impact
--Total Old Gold Purchased Per Month (Weight & Value)
SELECT
    EXTRACT(YEAR FROM purchase_date) AS purchase_year,
    EXTRACT(MONTH FROM purchase_date) AS purchase_month,
    ROUND(SUM(net_weight)::numeric,2) AS total_weight,
    ROUND(SUM(total_amount)::numeric,2) AS total_value
FROM fact_old_gold_purchase
GROUP BY
    EXTRACT(YEAR FROM purchase_date),
    EXTRACT(MONTH FROM purchase_date)
ORDER BY
    purchase_year,
    purchase_month;
--What Percentage of Sales Invoices Are Linked to an Old Gold Buy-Back?
SELECT
    ROUND(
        (
            COUNT(DISTINCT og.customer_id) * 100.0 /
            COUNT(DISTINCT fs.customer_id)
        )::numeric,
        2
    ) AS buyback_customer_percentage
FROM fact_sales fs
LEFT JOIN fact_old_gold_purchase og
ON fs.customer_id = og.customer_id;
--Which Branches Have the Highest Buy-Back Activity?
SELECT
    b.branch_name,
    COUNT(DISTINCT og.purchase_id) AS total_buybacks,
    ROUND(SUM(og.net_weight)::numeric,2) AS total_weight,
    ROUND(SUM(og.total_amount)::numeric,2) AS total_value
FROM fact_old_gold_purchase og
JOIN dim_branch b
ON og.branch_id = b.branch_id
GROUP BY b.branch_name
ORDER BY total_value DESC;
--Average Value of Old Gold Purchases by Branch
SELECT
    b.branch_name,
    ROUND(AVG(og.total_amount)::numeric,2) AS average_buyback_value,
    COUNT(DISTINCT og.purchase_id) AS total_transactions
FROM fact_old_gold_purchase og
JOIN dim_branch b
ON og.branch_id = b.branch_id
GROUP BY b.branch_name
ORDER BY average_buyback_value DESC;
--Buy-Back Rate vs Market Rate
SELECT
    ROUND(AVG(metal_rate)::numeric,2) AS avg_buyback_rate,
    ROUND(AVG(market_rate)::numeric,2) AS avg_market_rate,
    ROUND(AVG(market_rate - metal_rate)::numeric,2) AS average_rate_difference
FROM fact_old_gold_purchase;
--Purity Distribution of Old Gold
SELECT
    purity,
    COUNT(*) AS total_items,
    ROUND(SUM(net_weight)::numeric,2) AS total_weight,
    ROUND(SUM(total_amount)::numeric,2) AS total_value
FROM fact_old_gold_purchase
GROUP BY purity
ORDER BY purity DESC;
--Challenge C-06: Salesperson Effectiveness.
--Top 10 & Bottom 10 Salespeople by RevenueTop 10 & Bottom 10 Salespeople by Revenue
SELECT
    sp.salesperson_name,
    b.branch_name,
    COUNT(DISTINCT fs.invoice_id) AS total_invoices,
    ROUND(SUM(fs.total_amount)::numeric,2) AS total_revenue,
    ROUND(SUM(fs.net_weight)::numeric,2) AS total_weight
FROM fact_sales fs
JOIN dim_salesperson sp
    ON fs.salesperson_id = sp.salesperson_id
JOIN dim_branch b
    ON fs.branch_id = b.branch_id
GROUP BY
    sp.salesperson_name,
    b.branch_name
ORDER BY total_revenue DESC
LIMIT 10;
--Bottom 10 by Revenue
SELECT
    sp.salesperson_name,
    b.branch_name,
    COUNT(DISTINCT fs.invoice_id) AS total_invoices,
    ROUND(SUM(fs.total_amount)::numeric,2) AS total_revenue,
    ROUND(SUM(fs.net_weight)::numeric,2) AS total_weight
FROM fact_sales fs
JOIN dim_salesperson sp
    ON fs.salesperson_id = sp.salesperson_id
JOIN dim_branch b
    ON fs.branch_id = b.branch_id
GROUP BY
    sp.salesperson_name,
    b.branch_name
ORDER BY total_revenue ASC
LIMIT 10;
--Average Transaction Value per Salesperson
SELECT
    sp.salesperson_name,
    b.branch_name,
    COUNT(DISTINCT fs.invoice_id) AS invoices,
    ROUND(AVG(fs.total_amount)::numeric,2) AS avg_transaction_value,
    ROUND(SUM(fs.total_amount)::numeric,2) AS total_revenue
FROM fact_sales fs
JOIN dim_salesperson sp
    ON fs.salesperson_id = sp.salesperson_id
JOIN dim_branch b
    ON fs.branch_id = b.branch_id
GROUP BY
    sp.salesperson_name,
    b.branch_name
ORDER BY avg_transaction_value DESC;
--Revenue, Weight & Transaction Count by Salesperson
SELECT
    sp.salesperson_name,
    ROUND(SUM(fs.total_amount)::numeric,2) AS revenue,
    ROUND(SUM(fs.net_weight)::numeric,2) AS weight_sold,
    COUNT(DISTINCT fs.invoice_id) AS transactions
FROM fact_sales fs
JOIN dim_salesperson sp
    ON fs.salesperson_id = sp.salesperson_id
GROUP BY
    sp.salesperson_name
ORDER BY revenue DESC;
--Which Salespeople Give the Highest Discounts?
SELECT
    sp.salesperson_name,
    ROUND(AVG(fs.discount_percentage)::numeric,2) AS avg_discount,
    ROUND(SUM(fs.discount)::numeric,2) AS total_discount_given,
    COUNT(*) AS sales
FROM fact_sales fs
JOIN dim_salesperson sp
    ON fs.salesperson_id = sp.salesperson_id
GROUP BY
    sp.salesperson_name
ORDER BY avg_discount DESC;
--Which salespeople have the highest return rates?
SELECT
    sp.salesperson_name,
    COUNT(DISTINCT fr.return_id) AS total_returns,
    ROUND(SUM(fr.total_amount)::numeric,2) AS return_value
FROM fact_returns fr
JOIN dim_salesperson sp
ON fr.salesperson_id = sp.salesperson_id
GROUP BY sp.salesperson_name
ORDER BY total_returns DESC;
--Which karat does each salesperson sell the most?
SELECT
    sp.salesperson_name,
    k.karat_name,
    COUNT(*) AS items_sold,
    ROUND(SUM(fs.total_amount)::numeric,2) AS revenue
FROM fact_sales fs
JOIN dim_salesperson sp
ON fs.salesperson_id = sp.salesperson_id
JOIN dim_item i
ON fs.item_id = i.item_id
JOIN dim_karat k
ON i.karat_id = k.karat_id
GROUP BY
    sp.salesperson_name,
    k.karat_name
ORDER BY
    sp.salesperson_name,
    revenue DESC;
--Which product types does each salesperson sell?
SELECT
    sp.salesperson_name,
    it.item_type_name,
    COUNT(*) AS items_sold,
    ROUND(SUM(fs.total_amount)::numeric,2) AS revenue
FROM fact_sales fs
JOIN dim_salesperson sp
ON fs.salesperson_id = sp.salesperson_id
JOIN dim_item i
ON fs.item_id = i.item_id
JOIN dim_item_type it
ON i.item_type_id = it.item_type_id
GROUP BY
    sp.salesperson_name,
    it.item_type_name
ORDER BY
    sp.salesperson_name,
    revenue DESC;
--Which salespeople generate the most old gold buy-back activity?
SELECT
    sp.salesperson_name,
    COUNT(DISTINCT og.purchase_id) AS buyback_transactions,
    ROUND(SUM(og.total_amount)::numeric,2) AS total_buyback_value,
    ROUND(SUM(og.net_weight)::numeric,2) AS total_weight
FROM fact_old_gold_purchase og
JOIN dim_salesperson sp
ON og.salesperson_id = sp.salesperson_id
GROUP BY sp.salesperson_name
ORDER BY total_buyback_value DESC;
--Challenge C-07: Daily & Seasonal Sales Patterns.
--Which days of the week are busiest?
SELECT
    TO_CHAR(invoice_date, 'Day') AS day_of_week,
    COUNT(DISTINCT invoice_id) AS transactions,
    ROUND(SUM(total_amount)::numeric,2) AS total_sales,
    ROUND(AVG(total_amount)::numeric,2) AS avg_sale_value
FROM fact_sales
GROUP BY TO_CHAR(invoice_date, 'Day')
ORDER BY transactions DESC;
--Which months generate the highest sales?
SELECT
    sale_year,
    sale_month,
    COUNT(DISTINCT invoice_id) AS transactions,
    ROUND(SUM(total_amount)::numeric,2) AS total_sales,
    ROUND(SUM(net_weight)::numeric,2) AS total_weight
FROM fact_sales
GROUP BY sale_year, sale_month
ORDER BY sale_year, sale_month;
--Are there months with fewer but higher-value transactions?Transaction Count vs Sales Value
SELECT
    sale_year,
    sale_month,
    COUNT(DISTINCT invoice_id) AS total_transactions,
    ROUND(AVG(total_amount)::numeric,2) AS avg_transaction_value,
    ROUND(SUM(total_amount)::numeric,2) AS total_sales
FROM fact_sales
GROUP BY sale_year, sale_month
ORDER BY sale_year, sale_month;
--Do sales increase when the gold rate changes?
SELECT
    sale_year,
    sale_month,
    ROUND(AVG(metal_rate)::numeric,2) AS avg_gold_rate,
    ROUND(SUM(total_amount)::numeric,2) AS total_sales
FROM fact_sales
GROUP BY sale_year, sale_month
ORDER BY sale_year, sale_month;
--Compare your calculated totals with the daily summary table.
SELECT
    invoice_date,
    COUNT(DISTINCT invoice_id) AS calculated_transactions,
    ROUND(SUM(total_amount)::numeric,2) AS calculated_sales
FROM fact_sales
GROUP BY invoice_date
ORDER BY invoice_date;
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'fact_branch_daily_summary'
ORDER BY ordinal_position;
--Data Validation (Daily Summary vs Fact Sales)
SELECT
    f.invoice_date,
    ROUND(SUM(f.total_amount)::numeric,2) AS calculated_sales,
    ROUND(SUM(s.total_amount)::numeric,2) AS summary_sales,
    ROUND(
        (SUM(f.total_amount) - SUM(s.total_amount))::numeric,
        2
    ) AS difference
FROM fact_sales f
JOIN fact_branch_daily_summary s
ON f.branch_id = s.branch_id
AND f.invoice_date = s.summary_date
WHERE s.is_return = false
GROUP BY f.invoice_date
ORDER BY f.invoice_date;
--C-08 – Karat & Product Mix Analysis.
--Which karat generates the most revenue and weight?
SELECT
    k.karat_name,
    COUNT(DISTINCT fs.invoice_id) AS transactions,
    ROUND(SUM(fs.net_weight)::numeric,2) AS total_weight,
    ROUND(SUM(fs.total_amount)::numeric,2) AS total_revenue
FROM fact_sales fs
JOIN dim_item i
    ON fs.item_id = i.item_id
JOIN dim_karat k
    ON i.karat_id = k.karat_id
GROUP BY k.karat_name
ORDER BY total_revenue DESC;
--Which karat is preferred at each branch?
SELECT
    b.branch_name,
    k.karat_name,
    ROUND(SUM(fs.total_amount)::numeric,2) AS revenue,
    ROUND(SUM(fs.net_weight)::numeric,2) AS weight
FROM fact_sales fs
JOIN dim_branch b
    ON fs.branch_id = b.branch_id
JOIN dim_item i
    ON fs.item_id = i.item_id
JOIN dim_karat k
    ON i.karat_id = k.karat_id
GROUP BY
    b.branch_name,
    k.karat_name
ORDER BY
    b.branch_name,
    revenue DESC;
--Which products generate the highest revenue?
SELECT
    it.item_type_name,
    COUNT(DISTINCT fs.invoice_id) AS transactions,
    ROUND(SUM(fs.total_amount)::numeric,2) AS revenue,
    ROUND(SUM(fs.net_weight)::numeric,2) AS weight
FROM fact_sales fs
JOIN dim_item i
    ON fs.item_id = i.item_id
JOIN dim_item_type it
    ON i.item_type_id = it.item_type_id
GROUP BY it.item_type_name
ORDER BY revenue DESC;
--Which item types generate the highest making charge?
SELECT
    it.item_type_name,
    ROUND(SUM(fs.making_amount)::numeric,2) AS total_making_charge,
    ROUND(SUM(fs.net_weight)::numeric,2) AS total_weight,
    ROUND(
        (SUM(fs.making_amount) /
        NULLIF(SUM(fs.net_weight),0))::numeric,
        2
    ) AS making_charge_per_gram
FROM fact_sales fs
JOIN dim_item i
    ON fs.item_id = i.item_id
JOIN dim_item_type it
    ON i.item_type_id = it.item_type_id
GROUP BY it.item_type_name
ORDER BY making_charge_per_gram DESC;
--Best-Selling Item Types by Branch
SELECT
    b.branch_name,
    it.item_type_name,
    ROUND(SUM(fs.total_amount)::numeric,2) AS revenue,
    COUNT(DISTINCT fs.invoice_id) AS transactions
FROM fact_sales fs
JOIN dim_branch b
    ON fs.branch_id = b.branch_id
JOIN dim_item i
    ON fs.item_id = i.item_id
JOIN dim_item_type it
    ON i.item_type_id = it.item_type_id
GROUP BY
    b.branch_name,
    it.item_type_name
ORDER BY
    b.branch_name,
    revenue DESC;
--Product Mix Trend Over Time
SELECT
    fs.sale_year,
    fs.sale_month,
    k.karat_name,
    ROUND(SUM(fs.total_amount)::numeric,2) AS revenue
FROM fact_sales fs
JOIN dim_item i
    ON fs.item_id = i.item_id
JOIN dim_karat k
    ON i.karat_id = k.karat_id
GROUP BY
    fs.sale_year,
    fs.sale_month,
    k.karat_name
ORDER BY
    fs.sale_year,
    fs.sale_month,
    revenue DESC;
--Create a Customer Segmentation Table
CREATE TABLE customer_segments AS
WITH customer_summary AS (
    SELECT
        customer_id,
        COUNT(DISTINCT invoice_id) AS purchase_count,
        SUM(total_amount) AS total_spent
    FROM fact_sales
    GROUP BY customer_id
)
SELECT
    customer_id,
    purchase_count,
    ROUND(total_spent::numeric,2) AS total_spent,
    CASE
        WHEN purchase_count = 1 THEN 'One-Time Buyer'
        WHEN purchase_count BETWEEN 2 AND 5 THEN 'Occasional Buyer'
        WHEN purchase_count > 5 AND total_spent < 100000 THEN 'Regular Buyer'
        WHEN purchase_count > 5 AND total_spent >= 100000 THEN 'High-Value Regular'
        ELSE 'Other'
    END AS customer_segment
FROM customer_summary;

SELECT *
FROM customer_segments
LIMIT 10;


SELECT column_name
FROM information_schema.columns
WHERE table_name = 'customer_segments'
ORDER BY ordinal_position;

CREATE OR REPLACE VIEW vw_customer_type AS
SELECT
    c.customer_id,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM fact_old_gold_purchase og
            WHERE og.customer_id = c.customer_id
        )
        THEN 'Old Gold Customer'
        ELSE 'Regular Customer'
    END AS customer_type
FROM dim_customer c;


  
