# Organization baseline: service control policies and cost-tag activation. Applied
# once, from the organization's management account. See README.md.
#
# SCPs never apply to the management account, and never to AWS service principals.
# They apply to every IAM principal in the attached accounts, root included.
#
# Applying this module with attach_to empty creates the policies and changes nothing.
# Attach to an OU only after checking that no running workload depends on what the
# policies deny.

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition

  # Each policy is a name, a description and its statements. One list drives both the
  # policies and their attachments, so no policy can exist unattached by mistake.
  policies = merge(
    {
      deny_root = {
        name        = "${var.name}-DenyRootUser"
        description = "Nobody uses the root user in a member account."
        statements = [{
          Sid      = "DenyRootUser"
          Effect   = "Deny"
          Action   = "*"
          Resource = "*"
          Condition = {
            StringLike = { "aws:PrincipalArn" = "arn:${local.partition}:iam::*:root" }
          }
        }]
      }

      limit_regions = {
        name        = "${var.name}-LimitRegions"
        description = "US regions only. Global and cross-region services are exempt."
        statements = [{
          Sid       = "LimitRegions"
          Effect    = "Deny"
          NotAction = var.region_exempt_actions
          Resource  = "*"
          Condition = {
            StringNotEquals = { "aws:RequestedRegion" = var.allowed_regions }
          }
        }]
      }

      # A rule that requires the encryption header denies every CLI upload that does
      # not send one, because S3 encrypts by default and clients rarely ask. This one
      # denies only a request that names something other than SSE-S3 or SSE-KMS, and
      # any request over plain HTTP.
      s3_protection = {
        name        = "${var.name}-S3Protection"
        description = "No plain-HTTP S3 access, and no upload that asks for an unsupported encryption."
        statements = [
          {
            Sid      = "DenyInsecureTransport"
            Effect   = "Deny"
            Action   = "s3:*"
            Resource = "*"
            Condition = {
              Bool = { "aws:SecureTransport" = "false" }
            }
          },
          {
            Sid      = "DenyUnsupportedEncryption"
            Effect   = "Deny"
            Action   = "s3:PutObject"
            Resource = "*"
            Condition = {
              StringNotEqualsIfExists = { "s3:x-amz-server-side-encryption" = ["AES256", "aws:kms"] }
            }
          },
        ]
      }

      billing_and_account = {
        name        = "${var.name}-DenyBillingAndAccountChanges"
        description = "Billing preferences, payment methods and account settings change only from the management account."
        statements = [{
          Sid    = "DenyBillingAndAccountChanges"
          Effect = "Deny"
          Action = [
            "aws-portal:ModifyAccount",
            "aws-portal:ModifyBilling",
            "aws-portal:ModifyPaymentMethods",
            "account:PutAccountName",
            "account:PutContactInformation",
          ]
          Resource = "*"
        }]
      }
    },

    var.deny_leaving_organization ? {
      deny_leaving = {
        name        = "${var.name}-DenyLeavingOrganization"
        description = "Accounts stay in the organization."
        statements = [{
          Sid      = "DenyLeavingOrganization"
          Effect   = "Deny"
          Action   = "organizations:LeaveOrganization"
          Resource = "*"
        }]
      }
    } : {},

    var.deny_static_access_keys ? {
      deny_access_keys = {
        name        = "${var.name}-DenyStaticAccessKeys"
        description = "No long-lived IAM access keys. Use roles and short-lived credentials."
        statements = [{
          Sid      = "DenyStaticAccessKeys"
          Effect   = "Deny"
          Action   = "iam:CreateAccessKey"
          Resource = "*"
          Condition = {
            ArnNotLike = { "aws:PrincipalArn" = var.exempt_principals }
          }
        }]
      }
    } : {},

    var.deny_audit_tampering ? {
      deny_audit_tampering = {
        name        = "${var.name}-DenyAuditTampering"
        description = "The audit and detection services stay on."
        statements = [{
          Sid    = "DenyAuditTampering"
          Effect = "Deny"
          Action = [
            "cloudtrail:DeleteTrail",
            "cloudtrail:PutEventSelectors",
            "cloudtrail:StopLogging",
            "cloudtrail:UpdateTrail",
            "config:DeleteConfigurationRecorder",
            "config:DeleteDeliveryChannel",
            "config:StopConfigurationRecorder",
            "guardduty:DeleteDetector",
            "securityhub:DisableSecurityHub",
            "access-analyzer:DeleteAnalyzer",
          ]
          Resource = "*"
          Condition = {
            ArnNotLike = { "aws:PrincipalArn" = var.exempt_principals }
          }
        }]
      }
    } : {},
  )

  policy_content = {
    for k, p in local.policies : k => jsonencode({
      Version   = "2012-10-17"
      Statement = p.statements
    })
  }

  too_long = [for k, c in local.policy_content : local.policies[k].name if length(c) > 5120]

  attachments = {
    for pair in setproduct(keys(local.policies), var.attach_to) :
    "${pair[0]}/${pair[1]}" => { policy = pair[0], target = pair[1] }
  }
}

# An SCP over 5,120 characters is refused at apply with an error about the whole call.
# This fails at plan and names the policy.
resource "terraform_data" "size_limit" {
  lifecycle {
    precondition {
      condition     = length(local.too_long) == 0
      error_message = "Over the 5,120 character SCP limit: ${join(", ", local.too_long)}."
    }
  }
}

resource "aws_organizations_policy" "scp" {
  for_each = local.policies

  name        = each.value.name
  description = each.value.description
  type        = "SERVICE_CONTROL_POLICY"
  content     = local.policy_content[each.key]

  depends_on = [terraform_data.size_limit]
}

resource "aws_organizations_policy_attachment" "scp" {
  for_each = local.attachments

  policy_id = aws_organizations_policy.scp[each.value.policy].id
  target_id = each.value.target
}

# Cost tags. A tag shows in Cost Explorer only after it is activated here, in the
# management account, and AWS does not backfill cost from before the activation.
resource "aws_ce_cost_allocation_tag" "active" {
  for_each = toset(var.cost_allocation_tag_keys)

  tag_key = each.value
  status  = "Active"
}
