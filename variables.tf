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
  description = "Tag keys to activate for cost allocation. A tag appears in Cost Explorer only after it is activated, and AWS does not backfill earlier cost. AWS can activate only a key that has already appeared on the bill, so in an organization that has never used a key, leave it out of this list."
  type        = list(string)
  default     = ["Project", "Environment", "ManagedBy", "Module"]
}

variable "enable_data_exports" {
  description = "Create the cost data exports (FOCUS 1.2, Cost Optimization Hub recommendations, CUR 2.0 with the IAM principal) and their bucket. On by default. Set false only when the organization already has its own exports. See modules/data-exports."
  type        = bool
  default     = true
}

variable "data_exports_bucket_name" {
  description = "Bucket for the cost data exports. Null creates <name>-finops-<account ID>."
  type        = string
  default     = null
}

variable "data_exports_reencrypt_deliveries" {
  description = "Re-encrypt each delivered export file with the module key, through EventBridge and a Systems Manager Automation runbook. Data Exports writes its files with SSE-S3 whatever the bucket default is. See modules/data-exports."
  type        = bool
  default     = false
}
