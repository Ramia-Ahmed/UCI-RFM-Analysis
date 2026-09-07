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