use company;

-- ============================================================
-- SECTION: DATA QUALITY CHECK
-- ============================================================

SELECT * FROM company_spending_analysis;

-- Modify PurchaseDate data type to date
ALTER TABLE company_spending_analysis MODIFY COLUMN PurchaseDate DATE ;

-- Check duplicate data
WITH duplicates_cte AS (
	SELECT *, 
			ROW_NUMBER() OVER (PARTITION BY TransactionID) AS row_num
	FROM company_spending_analysis
)
SELECT * 
FROM duplicates_cte
WHERE row_num > 1;

-- Check mismatch between Quantity * UnitPrice vs TotalCost
SELECT *
FROM company_spending_analysis
WHERE  ROUND(Quantity * UnitPrice, 2) != TotalCost;

-- Dataset overview summary
SELECT 
  COUNT(*) AS total_records,
  COUNT(DISTINCT TransactionID) AS unique_transactions,
  COUNT(*) - COUNT(Supplier) AS missing_supplier,
  COUNT(*) - COUNT(Buyer) AS missing_buyer,
  MIN(Quantity) AS min_quantity,
  MAX(Quantity) AS max_quantity,
  MIN(UnitPrice) AS min_unit_price,
  MAX(UnitPrice) AS max_unit_price,
  MIN(PurchaseDate) AS min_purchase_date,
  MAX(PurchaseDate) AS max_purchase_date
FROM company_spending_analysis;


-- ============================================================
-- SECTION: EXPLORATION DATA
-- ============================================================

-- Top spending by item
SELECT ItemName, 
		ROUND(SUM(TotalCost), 2) AS TotalCost
FROM company_spending_analysis
GROUP BY ItemName
ORDER BY TotalCost DESC;

-- Total quantity by item
SELECT ItemName, 
		SUM(Quantity) AS TotalQuantity 
FROM company_spending_analysis
GROUP BY ItemName
ORDER BY TotalQuantity DESC;

-- Top spending by category
SELECT Category, 
		ROUND(SUM(TotalCost), 2) AS TotalCost
FROM company_spending_analysis
GROUP BY Category
ORDER BY TotalCost DESC;


-- ============================================================
-- SECTION: TEMPORAL ANALYSIS
-- ============================================================

-- Monthly spending by category
SELECT SUBSTRING(PurchaseDate, 1, 7) AS `Month`,
		Category, 
        ROUND(SUM(TotalCost), 2) AS TotalSpending
FROM company_spending_analysis
GROUP BY `Month`, Category
ORDER BY `Month`, Category;
        
-- MoM Growth
WITH total_purchase_per_month AS (
	SELECT SUBSTRING(PurchaseDate, 1, 7) AS `Month`, 
			ROUND(SUM(TotalCost), 2) AS Total
	FROM company_spending_analysis
	GROUP BY `Month`
)
SELECT *, 
		ROUND((Total / ( LAG(total, 1, 0) OVER (ORDER BY `Month`)) - 1) * 100, 2) AS `% Growth`
FROM total_purchase_per_month;

-- 7-days rolling average
CREATE OR REPLACE VIEW company_spend_with_rolling AS 
( 
	WITH RECURSIVE calendar AS (
		SELECT MIN(PurchaseDate) AS cal_date
		FROM company_spending_analysis
		UNION ALL
		SELECT DATE_ADD(cal_date, INTERVAL 1 DAY)
		FROM calendar
		WHERE cal_date < (SELECT MAX(PurchaseDate) FROM company_spending_analysis)
	),
	daily_total AS (
		SELECT PurchaseDate, 
			   ROUND(SUM(TotalCost), 2) AS daily_spend
		FROM company_spending_analysis
		GROUP BY PurchaseDate
	),
	calendar_spend AS (
		SELECT c.cal_date AS PurchaseDate,
			   COALESCE(d.daily_spend, 0) AS daily_spend
		FROM calendar c
		LEFT JOIN daily_total d
		ON c.cal_date = d.PurchaseDate
	)
	-- Final result with 7-days rolling average
	SELECT PurchaseDate,
		   daily_spend,
		   ROUND(AVG(daily_spend) OVER (ORDER BY PurchaseDate ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS rolling_7_days_avg
	FROM calendar_spend
	ORDER BY PurchaseDate
);

SELECT * FROM company_spend_with_rolling;

-- ============================================================
-- SECTION: SUPPLIER ANALYSIS
-- ============================================================

-- Supplier Dependence Analysis
SELECT Supplier, 
		ROUND(SUM(TotalCost), 2) AS TotalSpend,
        ROUND(SUM(TotalCost) * 100 / SUM(SUM(TotalCost)) OVER ()) AS Percentage
FROM company_spending_analysis
GROUP BY Supplier
ORDER BY TotalSpend DESC;

-- Total Quantity Purchased per Supplier
SELECT Supplier, 
		ROUND(SUM(Quantity), 2) AS TotalQuantity
FROM company_spending_analysis
GROUP BY Supplier
ORDER BY TotalQuantity DESC;

-- Spending Efficiency Analysis
SELECT Category, Supplier,
       ROUND(SUM(TotalCost) / NULLIF(SUM(Quantity), 0), 2) AS avg_cost_per_unit
FROM company_spending_analysis
GROUP BY Category, Supplier
ORDER BY Category, avg_cost_per_unit;


-- ============================================================
-- SECTION: BUYER ANALYSIS
-- ============================================================

-- Buyer spending analysis
SELECT Buyer,
		ROUND(SUM(TotalCost), 2) AS TotalSpend
FROM company_spending_analysis
GROUP BY Buyer
ORDER BY TotalSpend DESC;


-- ============================================================
-- SECTION: ANOMALY DETECTION
-- ============================================================

-- Detect Outliers based on TotalCost (2 SD above mean)
WITH stats AS (
  SELECT 
    AVG(TotalCost) AS avg_cost,
    STDDEV_POP(TotalCost) AS stddev_cost
  FROM company_spending_analysis
)
SELECT *
FROM company_spending_analysis, stats
WHERE TotalCost > avg_cost + 2 * stddev_cost
ORDER BY TotalCost DESC;
