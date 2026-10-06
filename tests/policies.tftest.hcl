# Plan-level checks with a mocked provider: no credentials, no organization.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
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
