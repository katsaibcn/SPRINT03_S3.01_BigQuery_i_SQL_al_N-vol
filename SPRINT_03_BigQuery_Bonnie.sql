CREATE SCHEMA IF NOT EXISTS
`sprint3-analytics-bonnie`.sprint3_silver
OPTIONS(location="EU");

-- EXERCISE 2

CREATE OR REPLACE EXTERNAL TABLE sprint3_bronze.transactions_raw
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/ERP/transactions.csv'],
  field_delimiter = ';'
);

CREATE OR REPLACE EXTERNAL TABLE sprint3_bronze.companies_raw
(
  company_id STRING,
  company_name STRING,
  phone STRING,
  email STRING,
  country STRING,
  website STRING
)
OPTIONS ( 
  format = 'CSV',
  skip_leading_rows = 1,
  uris = ['gs://bootcamp-data-analytics-public/ERP/companies.csv'],
  field_delimiter = ','
);


CREATE OR REPLACE EXTERNAL TABLE sprint3_bronze.american_users_raw
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/CRM/american_users.csv']
);

CREATE OR REPLACE EXTERNAL TABLE sprint3_bronze.european_users_raw
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/CRM/european_users.csv']
);

CREATE OR REPLACE EXTERNAL TABLE sprint3_bronze.credit_cards_raw
OPTIONS (
  format = 'CSV',
  uris = ['gs://bootcamp-data-analytics-public/CRM/credit_cards.csv']
);

# EXERCISE 3: uploading local products csv and creating products_raw table:
# used bq shell (uploaded file, then run bq load, specifying new table name and schema, to create it)

# this is the order I executed in bq shelL:

# bq load \
# --replace \
# --skip_leading_rows=1 \
# sprint3_bronze.products_raw products.csv id:string,product_name:string,price:string,colour:string,weight:string,warehouse_id:string,category:string,brand:string,cost:string,launch_date:string

# EXERCISE 4 (AI assisted prompt):
-- 1. Write a SQL query to create a new table called transactions_raw_native in the sprint3_bronze dataset. It should have the same schema as, and contain all data from, the transactions_raw external table but be created as a native table in the same dataset (sprint3_bronze). Please use CREATE OR REPLACE TABLE so I don't get errors if I run it more than once.
-- 2. replace the list of columns in the SELECT statement with * (... AS SELECT* FROM...)
CREATE OR REPLACE TABLE
  `sprint3-analytics-bonnie`.`sprint3_bronze`.`transactions_raw_native` AS
SELECT
  *
FROM
  `sprint3-analytics-bonnie`.`sprint3_bronze`.`transactions_raw`;

SELECT COUNT(id)
FROM sprint3_bronze.transactions_raw
WHERE id LIKE "%1%";

SELECT*
FROM sprint3_bronze.transactions_raw;

# Estimate how much data a query will process
# queryDryRun demonstrates issuing a dry run query to validate query structure and
# provide an estimate of the bytes scanned.

SELECT*
FROM sprint3_bronze.transactions_raw_native;

# EXERCISE 5:
# show the 5 days in 2021 with most income.

SELECT ROUND(SUM(amount),2) AS total_billed, DATE(timestamp)
FROM `sprint3_bronze.transactions_raw_native`
WHERE DATE(timestamp) BETWEEN '2021-01-01' AND '2021-12-31'
GROUP BY DATE(timestamp)
ORDER BY SUM(amount) DESC
LIMIT 5;

#EXERCISE 6:
# company names etc of those who did transaction on given dates and between given amounts:


SELECT co.company_name, co.country, DATE(tr.timestamp) AS transaction_date, tr.amount
FROM sprint3_bronze.companies_raw co
JOIN sprint3_bronze.transactions_raw_native tr
	ON tr.business_id = co.company_id
WHERE DATE(tr.timestamp) IN ("2015-04-29", "2018-07-20", "2024-03-13")
	AND tr.amount BETWEEN 100 and 200
    AND declined = 0
ORDER BY tr.amount DESC;

# __________NIVEL 2________________________
# EXERCISE 1:
# clean data from products_raw and create silver level products_clean table:

CREATE OR REPLACE TABLE sprint3_silver.products_clean AS 
  SELECT 
    id AS product_id,
    product_name AS name,
	  SAFE_CAST((REPLACE(price,'$','')) AS FLOAT64) AS price,
    colour,
    weight,
    SAFE_CAST((REPLACE(warehouse_id,'WH-','')) AS INT64) AS warehouse_id,
    category,
    brand,
    SAFE_CAST((REPLACE(cost,"$","")) AS FLOAT64) AS cost,
    SAFE_CAST(launch_date AS DATE) AS launch_date
  FROM sprint3_bronze.products_raw
  ;

# to see if any constraints in place:
SELECT *
FROM `sprint3-analytics-bonnie`.sprint3_silver.INFORMATION_SCHEMA.TABLE_CONSTRAINTS;

ALTER TABLE sprint3_silver.products_clean 
ADD PRIMARY KEY (product_id) NOT ENFORCED;




# EXERCISE 2:
#create clean transactions table and populate with fixes listed in the instructions:

#testing ARRAY() to fix product_ids field:
SELECT ARRAY(
        SELECT CAST(products AS INT64) 
        FROM UNNEST(SPLIT(product_ids, ',')) AS products
        ) AS array_product_ids
FROM `sprint3_bronze.transactions_raw`;

#checking amount field has no issues:
SELECT amount 
FROM sprint3_bronze.transactions_raw
WHERE amount IS NULL;

CREATE OR REPLACE TABLE sprint3_silver.transactions_clean AS 
  SELECT
    id AS transaction_id,
    card_id,
    business_id,
    SAFE_CAST(timestamp AS TIMESTAMP) AS timestamp,
    SAFE_CAST(amount AS FLOAT64) AS amount,
    declined,
    ARRAY(SELECT CAST(products AS INT64) 
          FROM UNNEST(SPLIT(product_ids, ',')) AS products
          ) AS product_ids,
    user_id,
    SAFE_CAST(lat AS FLOAT64) as lat,
    SAFE_CAST(longitude AS FLOAT64) as longitude
FROM sprint3_bronze.transactions_raw;

    
# EXERCISE 3: combine user tables for silver level:

# to see date format (no preview option as is an external table):
SELECT*
FROM `sprint3_bronze.american_users_raw`
LIMIT 5;
# >>> returns "Nov 17, 1985"

# testing birth_date fix:
SELECT birth_date, PARSE_DATE('%b %e, %Y', birth_date) AS fixed_date
FROM `sprint3_bronze.american_users_raw`;

CREATE OR REPLACE TABLE sprint3_silver.users_combined AS
SELECT
  "American" as origin,
  id AS user_id,
  name,
  surname,
  phone,
  email,
  PARSE_DATE('%b %e, %Y', birth_date) AS birth_date,
  country,
  city,
  postal_code,
  address
FROM sprint3_bronze.american_users_raw
UNION ALL
SELECT
  "European" as origin,
  id AS user_id,
  name,
  surname,
  phone,
  email,
  PARSE_DATE('%b %e, %Y', birth_date) AS birth_date,
  country,
  city,
  postal_code,
  address
FROM sprint3_bronze.european_users_raw;

CREATE OR REPLACE TABLE sprint3_silver.companies_clean AS
  SELECT
    company_id,
    company_name,
    phone,
    email,
    country,
    website,
FROM sprint3_bronze.companies_raw;

CREATE OR REPLACE TABLE sprint3_silver.credit_cards_clean AS
  SELECT
    id AS credit_card_id,
    user_id,
    iban,
    pan,
    pin,
    cvv,
    track1,
    track2,
    expiring_date
FROM sprint3_bronze.credit_cards_raw;

# tables have no PK or FK....

--
-- to see if any constraints in place:
SELECT *
FROM `sprint3-analytics-bonnie`.sprint3_silver.INFORMATION_SCHEMA.TABLE_CONSTRAINTS;

# adding constraints:
ALTER TABLE sprint3_silver.companies_clean 
ADD PRIMARY KEY (company_id) NOT ENFORCED;

ALTER TABLE sprint3_silver.credit_cards_clean 
ADD PRIMARY KEY (credit_card_id) NOT ENFORCED;

ALTER TABLE sprint3_silver.users_combined 
ADD PRIMARY KEY (user_id) NOT ENFORCED;

ALTER TABLE sprint3_silver.transactions_clean 
ADD PRIMARY KEY (transaction_id) NOT ENFORCED,
ADD CONSTRAINT fk_trans_credit_cards FOREIGN KEY (card_id) REFERENCES `sprint3_silver.credit_cards_clean`(credit_card_id) NOT ENFORCED,
ADD CONSTRAINT fk_trans_companies FOREIGN KEY (business_id) REFERENCES `sprint3_silver.companies_clean`(company_id) NOT ENFORCED,
ADD CONSTRAINT fk_trans_users FOREIGN KEY (user_id) REFERENCES `sprint3_silver.users_combined`(user_id) NOT ENFORCED
;



#__________NIVELL 3___________________

# EXERCISE 1: vista marketing:

CREATE OR REPLACE VIEW sprint3_gold.v_marketing_kpis AS 
  SELECT co.company_name, 
        co.phone, 
        co.country, 
        av.average_spend,
        IF(av.average_spend > 260,'Premium','Standard') AS client_tier
  FROM `sprint3_silver.companies_clean` co
  LEFT JOIN (SELECT business_id, ROUND(AVG(amount),2) AS average_spend
          FROM `sprint3_silver.transactions_clean`
          WHERE declined = 0
          GROUP BY business_id) AS av
    ON av.business_id = co.company_id; 

SELECT*
FROM `sprint3-analytics-bonnie.sprint3_gold.v_marketing_kpis`
ORDER BY client_tier, average_spend DESC;

# EXERCISE 2:
# create new sales table: product_id, name, price i color, total_sold

# testing flattening product_ids in transactions_clean table:
SELECT transaction_id, individual_products
FROM sprint3_silver.transactions_clean
INNER JOIN UNNEST(transactions_clean.product_ids) AS individual_products;

# testing counting flattened products
SELECT individual_products, COUNT(individual_products) AS sold_count
FROM sprint3_silver.transactions_clean
INNER JOIN UNNEST(transactions_clean.product_ids) AS individual_products
GROUP BY individual_products;

#testing full select query for future table
SELECT product_id, name, price, colour, unpacked_products.sold_count AS total_sold 
FROM `sprint3_silver.products_clean` prod 
LEFT JOIN (SELECT CAST(individual_product AS STRING) AS product, COUNT(individual_product) AS sold_count
          FROM sprint3_silver.transactions_clean
          INNER JOIN UNNEST(transactions_clean.product_ids) AS individual_product
          GROUP BY individual_product) AS unpacked_products
  ON unpacked_products.product = prod.product_id
ORDER BY product_id;

# creating final table:
CREATE OR REPLACE TABLE sprint3_gold.product_sales_ranking AS
  SELECT product_id, name, price, colour, unpacked_products.sold_count AS total_sold 
  FROM `sprint3_silver.products_clean` prod 
  LEFT JOIN (SELECT CAST(individual_product AS STRING) AS product, COUNT(individual_product) AS sold_count
          FROM sprint3_silver.transactions_clean
          INNER JOIN UNNEST(transactions_clean.product_ids) AS individual_product
          GROUP BY individual_product) AS unpacked_products
  ON unpacked_products.product = prod.product_id
  ORDER BY unpacked_products.sold_count DESC;

SELECT*
FROM `sprint3_gold.product_sales_ranking`
ORDER BY total_sold DESC;
