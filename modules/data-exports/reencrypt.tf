# Re-encryption of delivered export files. Data Exports writes every file with SSE-S3,
# whatever the bucket default is, and AWS says to apply SSE-KMS after delivery. S3 sends
# an Object Created event to EventBridge for each file. A rule matches the export
# prefixes and starts an Automation runbook, which calls UpdateObjectEncryption on that
# object version. The update re-encrypts the data key in place: the version ID, the
# ETag and the last-modified time stay, and no new version is written.

locals {
  reencrypt_name = "${var.name}-finops-reencrypt"
}

resource "aws_s3_bucket_notification" "this" {
  count = var.reencrypt_deliveries ? 1 : 0

  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

# The runbook's role can change the encryption of objects in this bucket, with this key,
# and nothing else.
data "aws_iam_policy_document" "reencrypt_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

data "aws_iam_policy_document" "reencrypt" {
  statement {
    sid       = "UpdateObjectEncryption"
    actions   = ["s3:UpdateObjectEncryption"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    sid = "UseTheKey"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:ReEncrypt*",
    ]
    resources = [aws_kms_key.this.arn]
  }
}

resource "aws_iam_role" "reencrypt" {
  count = var.reencrypt_deliveries ? 1 : 0

  name               = local.reencrypt_name
  description        = "Runs the ${local.reencrypt_name} runbook on files in ${local.bucket_name}"
  assume_role_policy = data.aws_iam_policy_document.reencrypt_assume.json
}

resource "aws_iam_role_policy" "reencrypt" {
  count = var.reencrypt_deliveries ? 1 : 0

  name   = "reencrypt"
  role   = aws_iam_role.reencrypt[0].id
  policy = data.aws_iam_policy_document.reencrypt.json
}

resource "aws_ssm_document" "reencrypt" {
  count = var.reencrypt_deliveries ? 1 : 0

  name            = local.reencrypt_name
  document_type   = "Automation"
  document_format = "YAML"

  content = yamlencode({
    schemaVersion = "0.3"
    description   = "Re-encrypts one object version in ${local.bucket_name} with SSE-KMS and the ${var.name} FinOps key."
    assumeRole    = aws_iam_role.reencrypt[0].arn
    parameters = {
      Bucket    = { type = "String" }
      Key       = { type = "String" }
      VersionId = { type = "String" }
    }
    mainSteps = [{
      name        = "UpdateObjectEncryption"
      action      = "aws:executeAwsApi"
      maxAttempts = 3
      inputs = {
        Service   = "s3"
        Api       = "UpdateObjectEncryption"
        Bucket    = "{{ Bucket }}"
        Key       = "{{ Key }}"
        VersionId = "{{ VersionId }}"
        ObjectEncryption = {
          SSEKMS = {
            KMSKeyArn        = aws_kms_key.this.arn
            BucketKeyEnabled = true
          }
        }
      }
    }]
  })
}

# EventBridge starts the runbook as this role. It can start this one runbook and hand
# it the runbook's role.
data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

data "aws_iam_policy_document" "events" {
  count = var.reencrypt_deliveries ? 1 : 0

  # The target is the automation definition, but SSM authorizes the start against the
  # document and against the new execution as well. With any of the three missing,
  # EventBridge counts each invocation as a success while SSM refuses it. The provider
  # gives an Automation document the automation-definition ARN, so the document ARN is
  # built here.
  statement {
    sid     = "StartTheRunbook"
    actions = ["ssm:StartAutomationExecution"]
    resources = [
      "${local.automation_definition_arn}:*",
      "${local.ssm_arn_prefix}:document/${local.reencrypt_name}",
      "${local.ssm_arn_prefix}:automation-execution/*",
    ]
  }

  statement {
    sid       = "PassTheRunbookRole"
    actions   = ["iam:PassRole"]
    resources = [aws_iam_role.reencrypt[0].arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ssm.amazonaws.com"]
    }
  }
}

locals {
  ssm_arn_prefix            = "arn:${local.partition}:ssm:${aws_s3_bucket.this.region}:${local.account_id}"
  automation_definition_arn = "${local.ssm_arn_prefix}:automation-definition/${local.reencrypt_name}"
}

resource "aws_iam_role" "events" {
  count = var.reencrypt_deliveries ? 1 : 0

  name               = "${local.reencrypt_name}-events"
  description        = "Lets EventBridge start the ${local.reencrypt_name} runbook"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json
}

resource "aws_iam_role_policy" "events" {
  count = var.reencrypt_deliveries ? 1 : 0

  name   = "start-reencrypt"
  role   = aws_iam_role.events[0].id
  policy = data.aws_iam_policy_document.events[0].json
}

# Only files under the export prefixes. Other writers keep the bucket default.
resource "aws_cloudwatch_event_rule" "reencrypt" {
  count = var.reencrypt_deliveries ? 1 : 0

  name        = local.reencrypt_name
  description = "New export files in ${local.bucket_name}"

  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.this.bucket] }
      object = { key = [for e in values(local.exports) : { prefix = "${e.s3_prefix}/" }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "reencrypt" {
  count = var.reencrypt_deliveries ? 1 : 0

  rule     = aws_cloudwatch_event_rule.reencrypt[0].name
  arn      = "${local.automation_definition_arn}:$DEFAULT"
  role_arn = aws_iam_role.events[0].arn

  # Automation takes each parameter as a list of strings.
  input_transformer {
    input_paths = {
      bucket  = "$.detail.bucket.name"
      key     = "$.detail.object.key"
      version = "$.detail.object.version-id"
    }
    input_template = <<-EOT
      {"Bucket": ["<bucket>"], "Key": ["<key>"], "VersionId": ["<version>"]}
    EOT
  }

  depends_on = [aws_ssm_document.reencrypt]
}
