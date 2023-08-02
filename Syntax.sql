--A. High Level Sales Analysis
--1. What was the total quantity sold for all products?
SELECT SUM(qty) AS total_quantity
FROM sales;
--2. What is the total generated revenue for all products before discounts?
SELECT SUM(qty * price) AS revenue_before_discounts
FROM sales;
--3. What was the total discount amount for all products?
SELECT CAST(SUM(qty * price * discount/100.0) AS FLOAT) AS total_discount
FROM sales;
--B. Transaction Analysis
--1. How many unique transactions were there?
SELECT COUNT(DISTINCT txn_id) AS unique_transactions
FROM sales;
--2. What is the average unique products purchased in each transaction?
SELECT AVG(product_count) AS avg_unique_products
FROM (
  SELECT 
    txn_id,
    COUNT(DISTINCT prod_id) AS product_count
  FROM sales 
  GROUP BY txn_id
) temp;
--3. What are the 25th, 50th and 75th percentile values for the revenue per transaction?
WITH transaction_revenue AS (
  SELECT 
    txn_id,
    SUM(qty*price) AS revenue
  FROM sales
  GROUP BY txn_id)

SELECT 
  DISTINCT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY revenue) OVER () AS pct_25th,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY revenue) OVER () AS pct_50th,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY revenue) OVER () AS pct_75th
FROM transaction_revenue;
--4. What is the average discount value per transaction?
SELECT CAST(AVG(total_discount) AS decimal(5, 1)) AS avg_discount_per_transaction
FROM (
  SELECT 
    txn_id,
    SUM(qty*price*discount/100.0) AS total_discount
  FROM sales
  GROUP BY txn_id
) temp;
--5. What is the percentage split of all transactions for members vs non-members?
SELECT 
  CAST(100.0*COUNT(DISTINCT CASE WHEN member = 1 THEN txn_id END) 
		/ COUNT(DISTINCT txn_id) AS FLOAT) AS members_pct,
  CAST(100.0*COUNT(DISTINCT CASE WHEN member = 0 THEN txn_id END)
		/ COUNT(DISTINCT txn_id) AS FLOAT) AS non_members_pct
FROM sales;
--6. What is the average revenue for member transactions and non-member transactions?
WITH member_revenue AS (
  SELECT 
    member,
    txn_id,
    SUM(qty*price) AS revenue
  FROM sales
  GROUP BY member, txn_id
) 

SELECT 
  member,
  CAST(AVG(1.0*revenue) AS decimal(10,2)) AS avg_revenue
FROM member_revenue
GROUP BY member;
--C. Product Analysis
--1. What are the top 3 products by total revenue before discount?
SELECT 
  TOP 3 pd.product_name,
  SUM(s.qty * s.price) AS revenue_before_discount
FROM sales s
JOIN product_details pd 
  ON s.prod_id = pd.product_id
GROUP BY pd.product_name
ORDER BY SUM(s.qty * s.price) DESC;
--2. What is the total quantity, revenue and discount for each segment?
SELECT 
  pd.segment_name,
  SUM(s.qty) total_quantity,
  SUM(s.qty * s.price) AS total_revenue_before_discount,
  SUM(s.qty * s.price * discount) AS total_discount
FROM sales s
JOIN product_details pd 
  ON s.prod_id = pd.product_id
GROUP BY pd.segment_name;
--3. What is the top selling product for each segment?
WITH segment_product_quantity AS (
SELECT 
  pd.segment_name,
  pd.product_name,
  SUM(s.qty) AS total_quantity,
  DENSE_RANK() OVER (PARTITION BY pd.segment_name ORDER BY SUM(s.qty) DESC) AS rnk
FROM sales s
JOIN product_details pd 
  ON s.prod_id = pd.product_id
GROUP BY pd.segment_name, pd.product_name
)

SELECT 
  segment_name,
  product_name AS top_selling_product,
  total_quantity
FROM segment_product_quantity
WHERE rnk = 1;
--4. What is the total quantity, revenue and discount for each category?
SELECT 
  pd.category_name,
  SUM(s.qty) AS total_quantity,
  SUM(s.qty * s.price) AS total_revenue,
  SUM(s.qty * s.price * s.discount/100) AS total_discount
FROM sales s
JOIN product_details pd 
  ON s.prod_id = pd.product_id
GROUP BY pd.category_name;
--5. What is the top selling product for each category?
WITH category_product_quantity AS (
  SELECT 
    pd.category_name,
    pd.product_name,
    SUM(s.qty) AS total_quantity,
    DENSE_RANK() OVER (PARTITION BY pd.category_name ORDER BY SUM(s.qty) DESC) AS rnk
  FROM sales s
  JOIN product_details pd 
    ON s.prod_id = pd.product_id
  GROUP BY pd.category_name, pd.product_name
)

SELECT 
  category_name,
  product_name AS top_selling_product,
  total_quantity
FROM category_product_quantity
WHERE rnk = 1;
--6. What is the percentage split of revenue by product for each segment?
WITH segment_product_revenue AS (
  SELECT 
    pd.segment_name,
    pd.product_name,
    SUM(s.qty * s.price) AS product_revenue
  FROM sales s
  JOIN product_details pd 
    ON s.prod_id = pd.product_id
  GROUP BY pd.segment_name, pd.product_name
)

SELECT 
  segment_name,
  product_name,
  CAST(100.0 * product_revenue 
	/ SUM(product_revenue) OVER (PARTITION BY segment_name) 
    AS decimal (10, 2)) AS segment_product_pct
FROM segment_product_revenue;
--7. What is the percentage split of revenue by segment for each category?
WITH segment_category_revenue AS (
  SELECT 
    pd.segment_name,
    pd.category_name,
    SUM(s.qty * s.price) AS category_revenue
  FROM sales s
  JOIN product_details pd 
    ON s.prod_id = pd.product_id
  GROUP BY pd.segment_name, pd.category_name
)

SELECT 
  segment_name,
  category_name,
  CAST(100.0 * category_revenue 
	/ SUM(category_revenue) OVER (PARTITION BY category_name) 
    AS decimal (10, 2)) AS segment_category_pct
FROM segment_category_revenue;
--8. What is the percentage split of total revenue by category?
WITH category_revenue AS (
  SELECT 
    pd.category_name,
    SUM(s.qty * s.price) AS revenue
  FROM sales s
  JOIN product_details pd 
    ON s.prod_id = pd.product_id
  GROUP BY pd.category_name
)

SELECT 
  category_name,
  CAST(100.0 * revenue / SUM(revenue) OVER () AS decimal (10, 2)) AS category_pct
FROM category_revenue;
--9. What is the total transaction “penetration” for each product?
--(penetration = number of transactions where at least 1 quantity of a product was purchased divided by total number of transactions)
WITH product_transations AS (
  SELECT 
    DISTINCT s.prod_id, pd.product_name,
    COUNT(DISTINCT s.txn_id) AS product_txn,
    (SELECT COUNT(DISTINCT txn_id) FROM sales) AS total_txn
  FROM sales s
  JOIN product_details pd 
    ON s.prod_id = pd.product_id
  GROUP BY prod_id, pd.product_name
)

SELECT 
  *,
  CAST(100.0 * product_txn / total_txn AS decimal(10,2)) AS penetration_pct
FROM product_transations;
--10. What is the most common combination of at least 1 quantity of any 3 products in a 1 single transaction?
--Count the number of products in each transaction
WITH products_per_transaction AS (
  SELECT 
    s.txn_id,
    pd.product_id,
    pd.product_name,
    s.qty,
    COUNT(pd.product_id) OVER (PARTITION BY txn_id) AS cnt
  FROM sales s
  JOIN product_details pd 
  ON s.prod_id = pd.product_id
),

--Filter transactions that have the 3 products and group them to a cell
combinations AS (
  SELECT 
    STRING_AGG(product_id, ', ') WITHIN GROUP (ORDER BY product_id)  AS product_ids,
    STRING_AGG(product_name, ', ') WITHIN GROUP (ORDER BY product_id) AS product_names
  FROM products_per_transaction
  WHERE cnt = 3
  GROUP BY txn_id
),

--Count the number of times each combination appears
combination_count AS (
  SELECT 
    product_ids,
    product_names,
    COUNT (*) AS common_combinations
  FROM combinations
  GROUP BY product_ids, product_names
)

--Filter the most common combinations
SELECT 
    product_ids,
    product_names
FROM combination_count
WHERE common_combinations = (SELECT MAX(common_combinations) 
			                 FROM combination_count);
--D. Bonus Question
--Use a single SQL query to transform the product_hierarchy and product_prices datasets to the product_details table.
SELECT 
  pp.product_id,
  pp.price,
  CONCAT(ph1.level_text, ' ', ph2.level_text, ' - ', ph3.level_text) AS product_name,
  ph2.parent_id AS category_id,
  ph1.parent_id AS segment_id,
  ph1.id AS style_id,
  ph3.level_text AS category_name,
  ph2.level_text AS segment_name,
  ph1.level_text AS style_name
FROM product_hierarchy ph1
--self join style level (ph1) with segment level (ph2)
JOIN product_hierarchy ph2 ON ph1.parent_id = ph2.id
--self join segment level (ph2) with category level (ph3)
JOIN product_hierarchy ph3 ON ph3.id = ph2.parent_id
--inner join style level (ph1) with table [product_prices] 
JOIN product_prices pp ON ph1.id = pp.id;