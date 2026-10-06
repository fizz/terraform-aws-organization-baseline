variable "name" {
  description = "Prefix for the policy names. Policy names are unique across the organization."
  type        = string
  default     = "baseline"
}

variable "attach_to" {
  description = "Organizational unit or account IDs the policies attach to. Empty creates the policies and attaches none, which is the safe first apply."
  type        = list(string)
  default     = []
}

variable "allowed_regions" {
  description = "Regions the accounts may use."
  type        = list(string)
  default     = ["us-east-1", "us-east-2", "us-west-1", "us-west-2"]
}

variable "region_exempt_actions" {
  description = "Actions exempt from the region limit: global services, and services that route across regions. Bedrock inference profiles route to another region, and a region deny without bedrock:* breaks them."
  type        = list(string)
  default = [
    "account:*",
    "aws-portal:*",
    "bedrock:*",
    "budgets:*",
    "ce:*",
    "cloudfront:*",
    "cur:*",
    "globalaccelerator:*",
    "health:*",
    "iam:*",
    "organizations:*",
    "route53:*",
    "route53domains:*",
    "s3:GetBucketLocation",
    "s3:ListAllMyBuckets",
    "shield:*",
    "sts:*",
    "support:*",
    "trustedadvisor:*",
    "waf:*",
    "wafv2:*",
  ]
}

variable "deny_leaving_organization" {
  description = "Block accounts from leaving the organization. Off while accounts are being built and moved. Turn it on once an account has moved to its owner's organization, so it stays there."
  type        = bool
  default     = false
}

variable "deny_static_access_keys" {
  description = "Block creation of long-lived IAM access keys. People and workflows use roles and short-lived credentials."
  type        = bool
  default     = true
}

variable "deny_audit_tampering" {
  description = "Block stopping or deleting CloudTrail, Config, GuardDuty, Security Hub and Access Analyzer."
  type        = bool
  default     = true
}

variable "exempt_principals" {
  description = "Principal ARNs the access-key and audit-tampering denials do not apply to. Add the role your pipeline uses to apply Terraform. The default is the role AWS Organizations creates in every new member account. The list cannot be empty, because an empty condition is an invalid policy."
  type        = list(string)
  default     = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]

  validation {
    condition     = length(var.exempt_principals) > 0
    error_message = "exempt_principals cannot be empty."
  }
}

variable "cost_allocation_tag_keys" {
  description = "Tag keys to activate for cost allocation. A tag appears in Cost Explorer only after it is activated, and AWS does not backfill earlier cost."
  type        = list(string)
  default     = ["Project", "Environment", "ManagedBy", "Module"]
}
