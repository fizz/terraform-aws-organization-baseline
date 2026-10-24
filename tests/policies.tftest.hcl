# Plan-level checks with a mocked provider: no credentials, no organization.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "111122223333"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

run "defaults_create_policies_and_attach_nothing" {
  command = plan

  assert {
    condition     = length(aws_organizations_policy.scp) == 6
    error_message = "Default is six policies: root, regions, S3, billing, access keys and audit tampering."
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.scp) == 0
    error_message = "With attach_to empty nothing is attached."
  }
}

run "deny_leaving_is_off_by_default" {
  command = plan

  assert {
    condition     = !contains(keys(aws_organizations_policy.scp), "deny_leaving")
    error_message = "DenyLeavingOrganization stays off until an account has moved to its owner."
  }
}

run "deny_leaving_turns_on_for_the_owner" {
  command = plan

  variables {
    deny_leaving_organization = true
  }

  assert {
    condition     = contains(keys(aws_organizations_policy.scp), "deny_leaving")
    error_message = "The toggle adds the policy."
  }
}

run "attachments_are_policies_times_targets" {
  command = plan

  variables {
    attach_to = ["ou-aaaa-11111111", "ou-aaaa-22222222"]
  }

  assert {
    condition     = length(aws_organizations_policy_attachment.scp) == 12
    error_message = "Six policies on two targets is twelve attachments."
  }
}

run "bedrock_survives_the_region_limit" {
  command = plan

  assert {
    condition     = contains(var.region_exempt_actions, "bedrock:*")
    error_message = "A region deny without bedrock:* breaks cross-region inference profiles."
  }
}

run "toggles_remove_their_policies" {
  command = plan

  variables {
    deny_static_access_keys = false
    deny_audit_tampering    = false
  }

  assert {
    condition     = length(aws_organizations_policy.scp) == 4
    error_message = "Turning both toggles off leaves four policies."
  }
}

run "all_four_cost_tags_activate" {
  command = plan

  assert {
    condition     = length(aws_ce_cost_allocation_tag.active) == 4
    error_message = "Project, Environment, ManagedBy and Module activate by default."
  }
}

run "exempt_principals_cannot_be_empty" {
  command = plan

  variables {
    exempt_principals = []
  }

  expect_failures = [var.exempt_principals]
}

run "oversized_policy_fails_at_plan" {
  command = plan

  variables {
    region_exempt_actions = [for i in range(400) : "service${i}:*"]
  }

  expect_failures = [terraform_data.size_limit]
}

run "data_exports_can_be_turned_off" {
  command = plan

  variables {
    enable_data_exports = false
  }

  assert {
    condition     = length(module.data_exports) == 0
    error_message = "enable_data_exports = false creates no exports."
  }
}

run "data_exports_are_on_by_default" {
  command = plan

  assert {
    condition     = length(module.data_exports[0].s3_uris) == 3
    error_message = "FOCUS, recommendations and CUR 2.0 by default."
  }

  assert {
    condition     = module.data_exports[0].bucket_name == "baseline-finops-111122223333"
    error_message = "The default bucket is <name>-finops-<account ID>."
  }

  assert {
    condition     = module.data_exports[0].s3_uris["cur2"] == "s3://baseline-finops-111122223333/cur2/iam-principal/"
    error_message = "The CUR 2.0 export writes under cur2/iam-principal."
  }
}
