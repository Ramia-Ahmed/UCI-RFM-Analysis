CREATE VIEW uci_flat_table AS
SELECT * FROM 'UCI/Online Retail.csv';


SELECT * FROM uci_flat_table;

SELECT strptime(InvoiceDate, '%m/%d/%Y %H:%M')::DATE AS Invoice_Date
FROM uci_flat_table;

SELECT MAX(InvoiceDate) AS last_date
FROM uci_flat_table;

SELECT MAX(strptime(InvoiceDate, '%m/%d/%Y %H:%M')) 
FROM uci_flat_table;

CREATE OR REPLACE VIEW line_totals AS
SELECT 
    CustomerID,
    InvoiceDate,
    InvoiceNo,
    SUM(Quantity * UnitPrice) AS line_total
FROM uci_flat_table
WHERE Quantity > 0 AND UnitPrice > 0
GROUP BY 
    CustomerID,
    InvoiceDate,
    InvoiceNo
ORDER BY line_total DESC;

CREATE OR REPLACE VIEW customer_rfm AS
SELECT 
    CustomerID,
    DATE '2011-12-09' - MAX(strptime(InvoiceDate, '%m/%d/%Y %H:%M'))::DATE AS recency_days,
    COUNT(InvoiceNo) AS frequency,
    SUM(line_total) AS monetary
FROM line_totals
GROUP BY CustomerID;

SELECT * FROM customer_rfm;

SELECT
    MIN(recency_days) AS min_rec,
    MAX(recency_days) AS max_rec,
    AVG(recency_days) AS avg_rec,
    MIN(frequency) AS min_freq,
    MAX(frequency) AS max_freq,
    AVG(frequency) AS avg_freq,
    MIN(monetary) AS min_mon,
    MAX(monetary) AS max_mon,
    AVG(monetary) AS avg_mon
FROM customer_rfm;

SELECT frequency, COUNT(CustomerID) FROM customer_rfm
GROUP BY frequency
ORDER BY frequency;

CREATE OR REPLACE VIEW rfm_scores AS
SELECT
    CustomerID,
    recency_days,
    frequency,
    monetary,

    -- R score: lower recency_days = more recent = better, so reverse the quartile
    NTILE(5) OVER (ORDER BY recency_days DESC) AS r_score,

    -- M score: higher monetary = better
    NTILE(5) OVER (ORDER BY monetary) AS m_score,

    -- F score: CASE, since frequency is skewed and quartiles would bunch too many customers together
    CASE
        WHEN frequency = 1 THEN 1
        WHEN frequency BETWEEN 2 AND 6 THEN 2
        WHEN frequency BETWEEN 7 AND 11 THEN 3
        WHEN frequency BETWEEN 12 AND 16 THEN 4
        ELSE 5
    END AS f_score

FROM customer_rfm;

SELECT * FROM rfm_scores;

CREATE OR REPLACE VIEW rfm_segments AS
SELECT
    CustomerID,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 3 AND f_score <= 2 THEN 'New Customers'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score = 2 THEN 'About to Sleep'
        WHEN r_score <= 2 AND f_score <= 1 THEN 'Lost'
        ELSE 'Needs Attention'
    END AS segment,
    CASE
    WHEN segment = 'Champions' THEN 1
    WHEN segment = 'Loyal Customers' THEN 2
    WHEN segment = 'New Customers' THEN 3
    WHEN segment = 'At Risk' THEN 4
    WHEN segment = 'About to Sleep' THEN 5
    WHEN segment = 'Lost' THEN 6
    END AS segment_group_order
FROM rfm_scores;

SELECT segment, COUNT(*) 
FROM rfm_segments 
GROUP BY segment 
ORDER BY COUNT(*) DESC;

SELECT * FROM rfm_scores 
WHERE r_score <= 2 AND f_score >= 3 LIMIT 20;

SELECT COUNT(*) FROM rfm_segments;

SELECT * FROM rfm_segments;

COPY rfm_segments TO 'UCI/rfm_segments.csv' (HEADER, DELIMITER ',');

                -- Cohort Analysis --
-- Clean Base Data (Filtered out negetive quantities)
CREATE OR REPLACE VIEW clean_invoices AS
SELECT
    CustomerID,
    InvoiceNo,
    InvoiceDate,
    DATE_TRUNC('month', STRPTIME(InvoiceDate, '%-m/%-d/%Y %-H:%M')) AS order_month
FROM uci_flat_table
WHERE CustomerID IS NOT NULL
AND Quantity > 0
AND UnitPrice > 0;

-- First Purchase Month per Customer = Their Cohort
CREATE OR REPLACE VIEW customer_cohorts AS
SELECT
    CustomerID,
    MIN(order_month) AS cohort_month
FROM clean_invoices
GROUP BY CustomerID;

-- Every Customer Month They were Active, tagged with cohort + month offset
CREATE OR REPLACE VIEW cohort_activity AS
SELECT
    c.CustomerID,
    c.cohort_month,
    DATE_DIFF('month', c.cohort_month, i.order_month) AS month_number
FROM customer_cohorts c
JOIN clean_invoices i USING(CustomerID)
GROUP BY
    c.CustomerID,
    c.cohort_month,
    month_number;

-- Cohort Sizes (Month 0 count per cohort)
CREATE OR REPLACE VIEW cohort_sizes AS
SELECT
    cohort_month,
    COUNT(DISTINCT CustomerID) AS cohort_size
FROM customer_cohorts
GROUP BY cohort_month;

-- Retention Metrix - active customers per cohort per month_number

SELECT
    a.cohort_month,
    a.month_number,
    COUNT(DISTINCT a.CustomerID) AS active_customers,
    s.cohort_size,
    ROUND(active_customers::DECIMAL / s.cohort_size * 100, 2) AS retention_pct
FROM cohort_activity a
JOIN cohort_sizes s USING(cohort_month)
GROUP BY
    a.cohort_month,
    a.month_number,
    s.cohort_size
ORDER BY
    a.cohort_month,
    a.month_number;