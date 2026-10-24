output "policy_ids" {
  description = "Service control policy IDs by short name."
  value       = { for k, p in aws_organizations_policy.scp : k => p.id }
}

output "attached_to" {
  description = "Targets the policies are attached to."
  value       = var.attach_to
}

output "data_exports" {
  description = "Bucket, key, re-encryption runbook, export ARNs and S3 URIs of the cost data exports. Null when enable_data_exports is false."
  value = var.enable_data_exports ? {
    bucket_name       = module.data_exports[0].bucket_name
    kms_key_arn       = module.data_exports[0].kms_key_arn
    reencrypt_runbook = module.data_exports[0].reencrypt_runbook
    export_arns       = module.data_exports[0].export_arns
    s3_uris           = module.data_exports[0].s3_uris
  } : null
}
