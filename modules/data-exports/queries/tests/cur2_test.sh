#!/usr/bin/env bash
# Checks the cur2.sql views with synthetic CUR 2.0 rows: the latest snapshot
# only, Marketplace model names, the partition, and the session name.
set -euo pipefail

here="$(dirname "${BASH_SOURCE[0]}")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

period="$work/data/BILLING_PERIOD=2026-10"
mkdir -p "$period/2026-10-12T05:00:00.000Z-a" "$period/2026-10-13T05:00:00.000Z-b"

duckdb <<SQL
CREATE TABLE rows AS SELECT * FROM (VALUES
  ('111122223333', '9svps415mdwhhoxlp2tx3hald', MAP {'product_name': 'Claude Sonnet 4.5 (Amazon Bedrock Edition)'}, 'Anthropic, PBC', 'us-east-1',
   'arn:aws:sts::111122223333:assumed-role/BedrockDeveloper/alice', TIMESTAMP '2026-10-12 00:00:00', 2.50),
  ('444455556666', '9svps415mdwhhoxlp2tx3hald', MAP {'product_name': 'Claude Sonnet 4.5 (Amazon Bedrock Edition)'}, 'Anthropic, PBC', 'us-gov-east-1',
   'arn:aws-us-gov:sts::777788889999:assumed-role/app-server/botocore-session-1791583562', TIMESTAMP '2026-10-12 00:00:00', 0.25),
  ('111122223333', 'AmazonEC2', MAP {'product_name': 'Amazon Elastic Compute Cloud'}, 'Amazon Web Services, Inc.', 'us-east-1',
   '', TIMESTAMP '2026-10-12 00:00:00', 10.00)
) AS t(line_item_usage_account_id, line_item_product_code, product, line_item_legal_entity, product_region_code,
       line_item_iam_principal, line_item_usage_start_date, line_item_unblended_cost);
COPY rows TO '$period/2026-10-12T05:00:00.000Z-a/part-00001.parquet' (FORMAT parquet);
COPY rows TO '$period/2026-10-13T05:00:00.000Z-b/part-00001.parquet' (FORMAT parquet);
SQL

duckdb <<SQL
SET VARIABLE cur2_path = '$work/data/*/*/*.parquet';
.read $here/../cur2.sql
SELECT CASE WHEN (SELECT count(*) FROM cur2_raw) = 6 THEN 'ok' ELSE error('the fixture has two snapshots of three rows') END;
SELECT CASE WHEN (SELECT count(*) FROM cur2) = 3 THEN 'ok' ELSE error('cur2 keeps only the latest snapshot') END;
SELECT CASE WHEN (SELECT round(sum(cost), 2) FROM cur2) = 12.75 THEN 'ok' ELSE error('the latest snapshot is counted once') END;
SELECT CASE WHEN (SELECT count(*) FROM cur2 WHERE model = 'Claude Sonnet 4.5') = 2 THEN 'ok' ELSE error('a Marketplace code resolves to its model name') END;
SELECT CASE WHEN (SELECT partition FROM cur2 WHERE product_region_code = 'us-gov-east-1') = 'aws-us-gov' THEN 'ok' ELSE error('a GovCloud row is in aws-us-gov') END;
SELECT CASE WHEN (SELECT session FROM cur2 WHERE role = 'BedrockDeveloper') = 'alice' THEN 'ok' ELSE error('a federated session name is kept') END;
SELECT CASE WHEN (SELECT session FROM cur2 WHERE role = 'app-server') IS NULL THEN 'ok' ELSE error('an SDK default session name is dropped') END;
SELECT CASE WHEN (SELECT count(*) FROM model_cost_by_caller) = 2 THEN 'ok' ELSE error('model_cost_by_caller has model rows only') END;
SQL

echo "cur2.sql: all checks pass"
