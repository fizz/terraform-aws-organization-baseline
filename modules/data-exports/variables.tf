variable "name" {
  description = "Prefix for the export names and the default bucket name."
  type        = string
  default     = "baseline"
}

variable "bucket_name" {
  description = "Bucket for the exports. Null creates <name>-finops-<account ID>."
  type        = string
  default     = null
}

variable "reencrypt_deliveries" {
  description = "Re-encrypt each delivered export file with the module key. Data Exports writes its files with SSE-S3 whatever the bucket default is, so without this the key protects nothing the exports write. An EventBridge rule starts a Systems Manager Automation runbook for each new object under an export prefix, and the runbook calls S3 UpdateObjectEncryption on that object version. Readers then need kms:Decrypt on the key."
  type        = bool
  default     = false
}

variable "exports" {
  description = "Exports to create: focus (FOCUS 1.2), recommendations (Cost Optimization Hub) and cur2 (CUR 2.0 with the IAM principal). Leave a key out to skip that export. Each field overrides a default, and each change replaces the export, so a caller that adopts existing exports passes the values they already have."
  type = map(object({
    name             = optional(string)
    description      = optional(string)
    s3_prefix        = optional(string)
    time_granularity = optional(string)
  }))
  default = {
    focus           = {}
    recommendations = {}
    cur2            = {}
  }

  validation {
    condition     = alltrue([for k in keys(var.exports) : contains(["focus", "recommendations", "cur2"], k)])
    error_message = "The export keys are focus, recommendations and cur2."
  }

  validation {
    condition     = alltrue([for o in values(var.exports) : o.time_granularity == null ? true : contains(["HOURLY", "DAILY", "MONTHLY"], o.time_granularity)])
    error_message = "time_granularity is HOURLY, DAILY or MONTHLY."
  }
}
