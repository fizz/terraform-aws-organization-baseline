-- DuckDB views over the CUR 2.0 export with the IAM principal.
--
-- Set the path to the export's data files, then read this file:
--
--   SET VARIABLE cur2_path = 's3://<bucket>/cur2/iam-principal/*/data/*/*/*.parquet';
--   .read cur2.sql
--
-- For S3, load httpfs and give DuckDB credentials first, for example with
-- CREATE SECRET (TYPE s3, PROVIDER credential_chain).
--
-- Each refresh of a CREATE_NEW_REPORT export writes a complete new snapshot of
-- the billing period. Reading every file counts each cost once per snapshot, so
-- cur2 keeps only the latest snapshot of each period. A snapshot directory name
-- starts with the time of the refresh, so the latest is the largest name.

CREATE OR REPLACE VIEW cur2_raw AS
SELECT
  *,
  regexp_extract(filename, '/([^/]+)/[^/]+\.parquet$', 1) AS snapshot
FROM read_parquet(getvariable('cur2_path'), filename = true, hive_partitioning = true, union_by_name = true);

CREATE OR REPLACE VIEW cur2 AS
WITH latest AS (
  SELECT * FROM cur2_raw
  QUALIFY snapshot = max(snapshot) OVER (PARTITION BY BILLING_PERIOD)
)
SELECT
  *,
  -- The product code of a Marketplace product is an opaque ID, for example
  -- 9svps415mdwhhoxlp2tx3hald. The bill also has its name.
  coalesce(product['product_name'], line_item_product_code) AS service,
  -- Claude and other Marketplace models on Bedrock are billed under their own
  -- product codes, not under AmazonBedrock.
  CASE
    WHEN product['product_name'] LIKE '% (Amazon Bedrock Edition)'
      THEN replace(product['product_name'], ' (Amazon Bedrock Edition)', '')
    WHEN line_item_product_code = 'AmazonBedrock'
      THEN product['product_name']
  END AS model,
  line_item_legal_entity AS seller,
  CASE
    WHEN line_item_iam_principal LIKE 'arn:aws-us-gov:%' OR product_region_code LIKE 'us-gov-%' THEN 'aws-us-gov'
    WHEN line_item_iam_principal LIKE 'arn:aws-cn:%' OR product_region_code LIKE 'cn-%' THEN 'aws-cn'
    ELSE 'aws'
  END AS partition,
  nullif(regexp_extract(line_item_iam_principal, ':assumed-role/([^/]+)', 1), '') AS role,
  -- The session name names a person for a federated user. An SDK that sets no
  -- name uses botocore-session-<time>, which names nothing.
  CASE
    WHEN regexp_extract(line_item_iam_principal, ':assumed-role/[^/]+/(.+)$', 1) SIMILAR TO 'botocore-session-[0-9]+' THEN NULL
    ELSE nullif(regexp_extract(line_item_iam_principal, ':assumed-role/[^/]+/(.+)$', 1), '')
  END AS session,
  nullif(regexp_extract(line_item_iam_principal, ':user/(.+)$', 1), '') AS iam_user,
  CAST(line_item_usage_start_date AS DATE) AS usage_date,
  line_item_unblended_cost AS cost
FROM latest;

-- Model spend by day, account, role and session.
CREATE OR REPLACE VIEW model_cost_by_caller AS
SELECT
  usage_date,
  line_item_usage_account_id AS account_id,
  partition,
  product_region_code AS region,
  model,
  coalesce(role, iam_user, '(no principal)') AS caller,
  session,
  sum(cost) AS cost
FROM cur2
WHERE model IS NOT NULL
GROUP BY ALL;
