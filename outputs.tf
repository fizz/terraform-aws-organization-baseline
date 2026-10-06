output "policy_ids" {
  description = "Service control policy IDs by short name."
  value       = { for k, p in aws_organizations_policy.scp : k => p.id }
}

output "attached_to" {
  description = "Targets the policies are attached to."
  value       = var.attach_to
}
