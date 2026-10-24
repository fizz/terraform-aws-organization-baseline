output "bucket_name" {
  description = "Bucket the exports write to."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the bucket the exports write to."
  value       = aws_s3_bucket.this.arn
}

output "kms_key_arn" {
  description = "ARN of the key that encrypts the bucket. Readers need kms:Decrypt on it."
  value       = aws_kms_key.this.arn
}

output "reencrypt_runbook" {
  description = "Name of the runbook that re-encrypts delivered files. Null when reencrypt_deliveries is false."
  value       = var.reencrypt_deliveries ? aws_ssm_document.reencrypt[0].name : null
}

output "export_arns" {
  description = "Export ARNs by key."
  value       = { for k, e in aws_bcmdataexports_export.this : k => e.arn }
}

output "s3_uris" {
  description = "S3 URI of each export's files, by key."
  value       = { for k, e in local.exports : k => "s3://${aws_s3_bucket.this.bucket}/${e.s3_prefix}/" }
}
