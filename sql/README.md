# SQL Analysis

This folder contains SQL queries used for data validation, cleaning, analysis, KPI calculation, and business insights for the GoldVista project.

## Contents

- Data validation queries
- Sales analysis
- Returns analysis
- Customer analysis
- Payment analysis
- Old-gold purchase analysis
- KPI queries

SQL was developed and tested using PostgreSQL.
-- Validate that orders have valid customer IDs
SELECT
  o.order_id,
  o.customer_id
FROM orders o
WHERE o.customer_id IS NULL;
