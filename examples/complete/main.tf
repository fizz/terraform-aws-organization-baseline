terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Run this in the organization's management account.
provider "aws" {
  region = "us-east-1"
}

module "organization_baseline" {
  source = "../.."

  # An empty list creates the policies and attaches none. After you check that
  # nothing running depends on what they deny, put an OU ID here and apply again.
  attach_to = []

  allowed_regions = ["us-east-1", "us-east-2", "us-west-2"]

  # Add the role your pipeline applies Terraform with.
  exempt_principals = [
    "arn:aws:iam::*:role/OrganizationAccountAccessRole",
    "arn:aws:iam::*:role/terraform-apply",
  ]

  # Turn on once an account has moved to its owner's organization.
  deny_leaving_organization = false
}

output "policy_ids" {
  value = module.organization_baseline.policy_ids
}
