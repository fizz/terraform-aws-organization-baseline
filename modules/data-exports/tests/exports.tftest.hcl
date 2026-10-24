# Plan-level checks with a mocked provider: no credentials, no organization.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

run "cur2_carries_the_iam_principal" {
  command = plan

  assert {
    condition     = strcontains(aws_bcmdataexports_export.this["cur2"].export[0].data_query[0].query_statement, "line_item_iam_principal")
    error_message = "The CUR 2.0 query selects line_item_iam_principal."
  }

  assert {
    condition     = aws_bcmdataexports_export.this["cur2"].export[0].data_query[0].table_configurations["COST_AND_USAGE_REPORT"]["INCLUDE_IAM_PRINCIPAL_DATA"] == "TRUE"
    error_message = "The CUR 2.0 export sets INCLUDE_IAM_PRINCIPAL_DATA."
  }

  assert {
    condition     = aws_bcmdataexports_export.this["cur2"].export[0].data_query[0].table_configurations["COST_AND_USAGE_REPORT"]["BILLING_VIEW_ARN"] == "arn:aws:billing::111122223333:billingview/primary"
    error_message = "BILLING_VIEW_ARN is in the configuration, or the provider reports an inconsistent result."
  }
}

run "bucket_encrypts_with_the_module_key" {
  command = plan

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "aws:kms"
    error_message = "The bucket encrypts with SSE-KMS."
  }

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.this.rule).bucket_key_enabled
    error_message = "The bucket uses an S3 Bucket Key."
  }

  assert {
    condition     = aws_kms_key.this.enable_key_rotation
    error_message = "The key rotates."
  }
}

run "recommendations_have_no_granularity" {
  command = plan

  assert {
    condition     = !contains(keys(aws_bcmdataexports_export.this["recommendations"].export[0].data_query[0].table_configurations["COST_OPTIMIZATION_RECOMMENDATIONS"]), "TIME_GRANULARITY")
    error_message = "The recommendations table takes no TIME_GRANULARITY."
  }
}

run "adopting_caller_keeps_its_names" {
  command = plan

  variables {
    name        = "acme"
    bucket_name = "acme-finops-legacy"
    exports = {
      focus = {
        description = "an older description"
      }
    }
  }

  assert {
    condition     = length(aws_bcmdataexports_export.this) == 1
    error_message = "Only the listed exports are created."
  }

  assert {
    condition     = aws_bcmdataexports_export.this["focus"].export[0].name == "acme-focus-v1-2"
    error_message = "The name comes from var.name when it is not given."
  }

  assert {
    condition     = aws_bcmdataexports_export.this["focus"].export[0].description == "an older description"
    error_message = "A given description replaces the default, so an existing export is not replaced."
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "acme-finops-legacy"
    error_message = "A given bucket name replaces the default."
  }
}

run "unknown_export_key_fails" {
  command = plan

  variables {
    exports = { cur = {} }
  }

  expect_failures = [var.exports]
}

run "bad_granularity_fails" {
  command = plan

  variables {
    exports = { cur2 = { time_granularity = "WEEKLY" } }
  }

  expect_failures = [var.exports]
}
