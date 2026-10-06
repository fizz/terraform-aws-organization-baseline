# terraform-aws-organization-baseline

Service control policies that do not break the people they protect. It also activates the cost tags that only the management account can activate.

Most SCP examples are copied between blog posts, and several of them fail in ways that look like a fault in your code. A region deny breaks Bedrock. An S3 encryption rule breaks every plain `aws s3 cp`. An audit-protection rule locks out your own Terraform. This module avoids all three, and the reasons are below.

## Usage

```hcl
module "organization_baseline" {
  source  = "fizz/organization-baseline/aws"
  version = "~> 0.1"

  # Empty creates the policies and attaches none. Attach in a second apply.
  attach_to = []

  exempt_principals = [
    "arn:aws:iam::*:role/OrganizationAccountAccessRole",
    "arn:aws:iam::*:role/my-terraform-apply",
  ]
}
```

Apply it in the organization's management account. The first apply creates the policies and changes nothing. Put an OU ID in `attach_to` for the second apply, after you check that nothing running depends on what the policies deny.

## The policies

| Policy | Effect |
|---|---|
| `DenyRootUser` | Nobody uses the root user in a member account |
| `LimitRegions` | US regions only, with global and cross-region services exempt |
| `S3Protection` | No plain-HTTP S3 access, and no upload that asks for an unsupported encryption |
| `DenyBillingAndAccountChanges` | Billing, payment and account settings change only from the management account |
| `DenyStaticAccessKeys` | No long-lived IAM access keys (`deny_static_access_keys`, on by default) |
| `DenyAuditTampering` | CloudTrail, Config, GuardDuty, Security Hub and Access Analyzer cannot be stopped or deleted (`deny_audit_tampering`, on by default) |
| `DenyLeavingOrganization` | Accounts cannot leave. **Off by default** (`deny_leaving_organization`) |

The four cost allocation tags `Project`, `Environment`, `ManagedBy` and `Module` are activated too. Change the list with `cost_allocation_tag_keys`.

## What is hard to get right

**A region deny breaks Bedrock.** Bedrock inference profiles route a request to another region, and a plain `aws:RequestedRegion` deny blocks the hop. `bedrock:*` is in the exempt list. Add any other service that routes to a second region.

**An encryption rule that requires the header breaks `aws s3 cp`.** S3 encrypts new objects by default, so callers rarely send the encryption header. A rule that denies a request without one denies nearly every upload. This module denies only a request that names something other than SSE-S3 or SSE-KMS, and any request over plain HTTP.

**Your own pipeline is a principal too.** An SCP that denies `cloudtrail:UpdateTrail` also stops the Terraform role that manages the trail. `exempt_principals` applies to the access-key and audit-tampering policies. It cannot be empty, because an empty condition is an invalid policy. The default is the role AWS Organizations creates in each member account.

**An SCP over 5,120 characters is refused with an error about the whole call.** The module checks each policy at plan time. It names the one that is too long.

**SCPs never apply to the management account or to AWS service principals.** They apply to every IAM principal in the attached accounts, root included. Test with one account before you attach to an OU.

**`DenyLeavingOrganization` is a toggle for a reason.** While accounts are being built and moved between organizations it blocks the move. Turn it on once an account has reached its owner.

**Cost tags need the management account.** A tag shows in Cost Explorer only after it is activated there. AWS does not backfill cost from before the activation, so activate early.

## Notes

- Tested on AWS provider 5.100 and 6.0, with `terraform test` and a mocked provider, so the tests need no credentials. It has been planned against a live organization.
- Pairs with [terraform-aws-account-baseline](https://github.com/fizz/terraform-aws-account-baseline), which creates the per-account audit, detection and cost controls.
