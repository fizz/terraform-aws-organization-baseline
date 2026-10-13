# Cost data exports: FOCUS 1.2, Cost Optimization Hub recommendations, and CUR 2.0
# with the IAM principal of each line item. AWS Billing writes daily Parquet files to
# one bucket. Apply this in the organization's management account, in us-east-1, which
# is the only region the Data Exports API runs in. The management account sees the cost
# of every member account, so one set of exports covers the organization.
#
# Each export uses CREATE_NEW_REPORT, so each refresh writes a new copy and keeps the
# old ones. Readers take the latest copy for each billing period.

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  # The Data Exports API runs only in us-east-1, so every export ARN names it.
  export_region = "us-east-1"

  bucket_name = coalesce(var.bucket_name, "${var.name}-finops-${local.account_id}")

  # What each export is. The caller can change the name, the description, the prefix
  # and the granularity. All four force a new export, so an adopting caller passes the
  # values its existing exports already have.
  catalog = {
    focus = {
      name        = "${var.name}-focus-v1-2"
      description = "${var.name} FOCUS 1.2, daily Parquet"
      s3_prefix   = "focus/v1.2"
      table       = "FOCUS_1_2_AWS"
      granularity = "HOURLY"
      options     = {}
    }

    recommendations = {
      name        = "${var.name}-cost-optimization-recommendations"
      description = "${var.name} Cost Optimization Hub recommendations, daily Parquet"
      s3_prefix   = "recommendations"
      table       = "COST_OPTIMIZATION_RECOMMENDATIONS"
      granularity = null
      options = {
        INCLUDE_ALL_RECOMMENDATIONS = "TRUE"
        FILTER                      = "{}"
      }
    }

    # Bedrock and other services attribute each charge to the IAM principal that made
    # the call. For a federated user the value is assumed-role/<role>/<session name>,
    # so spend splits by person with no tags. FOCUS has no such column. An export
    # created before the option existed never gains it, so it is a separate export.
    cur2 = {
      name        = "${var.name}-cur2-iam-principal"
      description = "${var.name} CUR 2.0 daily Parquet with the IAM principal of each line item"
      s3_prefix   = "cur2/iam-principal"
      table       = "COST_AND_USAGE_REPORT"
      granularity = "DAILY"
      options = {
        # AWS adds this on create, and the provider reports an inconsistent result
        # when the configuration does not have it.
        BILLING_VIEW_ARN                      = "arn:${local.partition}:billing::${local.account_id}:billingview/primary"
        INCLUDE_IAM_PRINCIPAL_DATA            = "TRUE"
        INCLUDE_RESOURCES                     = "TRUE"
        INCLUDE_SPLIT_COST_ALLOCATION_DATA    = "FALSE"
        INCLUDE_MANUAL_DISCOUNT_COMPATIBILITY = "FALSE"
      }
    }
  }

  exports = {
    for k, o in var.exports : k => {
      name        = coalesce(o.name, local.catalog[k].name)
      description = coalesce(o.description, local.catalog[k].description)
      s3_prefix   = coalesce(o.s3_prefix, local.catalog[k].s3_prefix)
      query       = "SELECT ${join(", ", local.columns[k])} FROM ${local.catalog[k].table}"
      table       = local.catalog[k].table
      table_config = merge(
        local.catalog[k].options,
        local.catalog[k].granularity == null ? {} : {
          TIME_GRANULARITY = coalesce(o.time_granularity, local.catalog[k].granularity)
        },
      )
    }
  }
}

# The bucket holds the cost history. Terraform never destroys it.
resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The export service checks that it can read this policy before it creates an export,
# and it writes manifests at the root of each prefix, so the policy covers the bucket
# and its keys. The source conditions stop another account's export from writing here.
data "aws_iam_policy_document" "bucket" {
  statement {
    sid    = "EnableAWSDataExportsToWriteToS3AndCheckPolicy"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "billingreports.amazonaws.com",
        "bcm-data-exports.amazonaws.com",
      ]
    }

    actions = [
      "s3:PutObject",
      "s3:GetBucketPolicy",
    ]

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    condition {
      test     = "StringLike"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values = [
        "arn:${local.partition}:cur:${local.export_region}:${local.account_id}:definition/*",
        "arn:${local.partition}:bcm-data-exports:${local.export_region}:${local.account_id}:export/*",
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json
}

resource "aws_bcmdataexports_export" "this" {
  for_each = local.exports

  export {
    name        = each.value.name
    description = each.value.description

    data_query {
      query_statement      = each.value.query
      table_configurations = { (each.value.table) = each.value.table_config }
    }

    destination_configurations {
      s3_destination {
        s3_bucket = aws_s3_bucket.this.bucket
        s3_prefix = each.value.s3_prefix
        s3_region = aws_s3_bucket.this.region

        s3_output_configurations {
          overwrite   = "CREATE_NEW_REPORT"
          format      = "PARQUET"
          compression = "PARQUET"
          output_type = "CUSTOM"
        }
      }
    }

    refresh_cadence {
      frequency = "SYNCHRONOUS"
    }
  }

  depends_on = [aws_s3_bucket_policy.this]

  lifecycle {
    prevent_destroy = true
  }
}
