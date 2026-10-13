output "bucket_name" {
  description = "Bucket the exports write to."
  value       = aws_s3_bucket.this.bucket
}

output "bucket_arn" {
  description = "ARN of the bucket the exports write to."
  value       = aws_s3_bucket.this.arn
}

output "export_arns" {
  description = "Export ARNs by key."
  value       = { for k, e in aws_bcmdataexports_export.this : k => e.arn }
}

output "s3_uris" {
  description = "S3 URI of each export's files, by key."
  value       = { for k, e in local.exports : k => "s3://${aws_s3_bucket.this.bucket}/${e.s3_prefix}/" }
}
