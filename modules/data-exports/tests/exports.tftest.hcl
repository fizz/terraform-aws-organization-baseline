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

run "reencryption_is_off_by_default" {
  command = plan

  assert {
    condition = (
      length(aws_s3_bucket_notification.this) == 0 &&
      length(aws_cloudwatch_event_rule.reencrypt) == 0 &&
      length(aws_ssm_document.reencrypt) == 0 &&
      length(aws_iam_role.reencrypt) == 0 &&
      length(aws_iam_role.events) == 0
    )
    error_message = "Nothing for re-encryption is created unless reencrypt_deliveries is true."
  }
}

run "reencryption_matches_each_export_prefix" {
  # The target ARN and the runbook content use values AWS computes, which a plan leaves
  # unknown. The provider is mocked, so this apply makes no AWS calls. Its own state keeps
  # the later runs from planning a destroy of the exports.
  command   = apply
  state_key = "reencrypt"

  variables {
    reencrypt_deliveries = true
  }

  override_resource {
    target = aws_s3_bucket.this
    values = {
      region = "us-east-1"
    }
  }

  override_resource {
    target = aws_kms_key.this
    values = {
      arn = "arn:aws:kms:us-east-1:111122223333:key/00000000-0000-0000-0000-000000000000"
    }
  }

  override_resource {
    target = aws_iam_role.reencrypt
    values = {
      arn = "arn:aws:iam::111122223333:role/baseline-finops-reencrypt"
    }
  }

  override_resource {
    target = aws_iam_role.events
    values = {
      arn = "arn:aws:iam::111122223333:role/baseline-finops-reencrypt-events"
    }
  }

  assert {
    condition     = aws_s3_bucket_notification.this[0].eventbridge
    error_message = "The bucket sends its events to EventBridge."
  }

  assert {
    condition = (
      toset([for k in jsondecode(aws_cloudwatch_event_rule.reencrypt[0].event_pattern).detail.object.key : k.prefix]) ==
      toset(["focus/v1.2/", "recommendations/", "cur2/iam-principal/"])
    )
    error_message = "The rule matches the prefix of each export, with a trailing slash."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.reencrypt[0].event_pattern)["detail-type"] == ["Object Created"]
    error_message = "The rule matches new objects only."
  }

  assert {
    condition     = endswith(aws_cloudwatch_event_target.reencrypt[0].arn, "automation-definition/baseline-finops-reencrypt:$DEFAULT")
    error_message = "The target is the runbook's default version."
  }

  assert {
    condition     = yamldecode(aws_ssm_document.reencrypt[0].content).mainSteps[0].inputs.Api == "UpdateObjectEncryption"
    error_message = "The runbook calls UpdateObjectEncryption."
  }

  assert {
    condition     = yamldecode(aws_ssm_document.reencrypt[0].content).mainSteps[0].inputs.ObjectEncryption.SSEKMS.BucketKeyEnabled
    error_message = "The runbook asks for an S3 Bucket Key on each object."
  }
}

run "reencryption_follows_the_caller_prefixes" {
  command = plan

  variables {
    reencrypt_deliveries = true
    exports = {
      focus = {
        s3_prefix = "legacy/focus"
      }
    }
  }

  assert {
    condition     = [for k in jsondecode(aws_cloudwatch_event_rule.reencrypt[0].event_pattern).detail.object.key : k.prefix] == ["legacy/focus/"]
    error_message = "The rule matches only the exports that exist, with their given prefixes."
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
