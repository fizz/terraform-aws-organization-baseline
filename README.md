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

## Cost data exports

The module creates a bucket and three daily Parquet exports. Set `enable_data_exports = false` only when the organization already has its own exports. AWS Billing writes them from the management account, so they cover every member account.

| Key | Export | Prefix |
|---|---|---|
| `focus` | FOCUS 1.2, hourly | `focus/v1.2` |
| `recommendations` | Cost Optimization Hub recommendations | `recommendations` |
| `cur2` | CUR 2.0, daily, with `line_item_iam_principal` | `cur2/iam-principal` |

The CUR 2.0 export splits spend by the IAM principal that made each call. Bedrock attributes inference cost this way. A federated user appears as `assumed-role/<role>/<session name>`, so a role for each person splits Bedrock cost by person with no tags. FOCUS has no such column.

The exports are also a submodule. An organization that already has its own service control policies can use the exports alone:

```hcl
module "data_exports" {
  source  = "fizz/organization-baseline/aws//modules/data-exports"
  version = "~> 0.2"

  name = "acme"
}
```

To adopt exports that exist already, pass their names and descriptions in `exports`, and add a `moved` block for each resource. A change to the name, the description, the prefix or the granularity replaces an export, and the exports and the bucket have `prevent_destroy`.

### Reading the exports

`modules/data-exports/queries/cur2.sql` defines DuckDB views over the CUR 2.0 export:

- `cur2` keeps only the latest snapshot of each billing period. Each refresh of a `CREATE_NEW_REPORT` export writes a complete copy, so a query over every file counts each cost once per snapshot.
- `cur2` adds `service` (the product name, not the code), `model`, `seller`, `partition`, `role`, `session` and `cost`. A Marketplace model such as Claude has an opaque product code, and `service` and `model` give its name. An SDK default session name such as `botocore-session-<time>` becomes null.
- `model_cost_by_caller` is model spend by day, account, Region, role and session.

```sql
SET VARIABLE cur2_path = 's3://<bucket>/cur2/iam-principal/*/data/*/*/*.parquet';
.read modules/data-exports/queries/cur2.sql
SELECT model, caller, session, round(sum(cost), 2) AS usd
FROM model_cost_by_caller GROUP BY ALL ORDER BY usd DESC;
```

GovCloud usage is billed in the paired commercial account, and its rows carry the GovCloud principal (`arn:aws-us-gov:...`), so `partition` is `aws-us-gov`.

## What is hard to get right

**A region deny breaks Bedrock.** Bedrock inference profiles route a request to another region, and a plain `aws:RequestedRegion` deny blocks the hop. `bedrock:*` is in the exempt list. Add any other service that routes to a second region.

**An encryption rule that requires the header breaks `aws s3 cp`.** S3 encrypts new objects by default, so callers rarely send the encryption header. A rule that denies a request without one denies nearly every upload. This module denies only a request that names something other than SSE-S3 or SSE-KMS, and any request over plain HTTP.

**Your own pipeline is a principal too.** An SCP that denies `cloudtrail:UpdateTrail` also stops the Terraform role that manages the trail. `exempt_principals` applies to the access-key and audit-tampering policies. It cannot be empty, because an empty condition is an invalid policy. The default is the role AWS Organizations creates in each member account.

**An SCP over 5,120 characters is refused with an error about the whole call.** The module checks each policy at plan time. It names the one that is too long.

**SCPs never apply to the management account or to AWS service principals.** They apply to every IAM principal in the attached accounts, root included. Test with one account before you attach to an OU.

**`DenyLeavingOrganization` is a toggle for a reason.** While accounts are being built and moved between organizations it blocks the move. Turn it on once an account has reached its owner.

**Cost tags need the management account.** A tag shows in Cost Explorer only after it is activated there. AWS does not backfill cost from before the activation, so activate early.

**A tag key activates only after it appears on the bill.** AWS refuses to activate a key that no resource in the organization has carried, and the apply fails. If no resource in the organization has carried a key in the default list, such as `Module`, pass a shorter `cost_allocation_tag_keys`. To see which keys AWS knows, run `aws ce list-cost-allocation-tags` in the management account.

**An export created before an option existed never gains it.** The IAM principal column needs a new CUR 2.0 export. An old export with the same table does not get the column.

**The provider reports an inconsistent result without `BILLING_VIEW_ARN`.** AWS adds it to a CUR 2.0 export on create. The module puts it in the configuration.

**Data Exports refuses `SELECT *`.** Each query names every column of its table. A column that AWS adds later appears only after it is added to `modules/data-exports/columns.tf`.

**Cost Optimization Hub must be on, and two service-linked roles must exist.** They are `AWSServiceRoleForCostOptimizationHub` and `AWSServiceRoleForBCMDataExports`. The module does not create them, because creating them in the same apply as an export fails on a race (terraform-provider-aws#39855). The first export created in the console creates the second role.

## Notes

- Needs AWS provider 6.0 or later. Tested on 6.0 and 6.68, with `terraform test` and a mocked provider, so the tests need no credentials. It has been planned against a live organization.
- Pairs with [terraform-aws-account-baseline](https://github.com/fizz/terraform-aws-account-baseline), which creates the per-account audit, detection and cost controls.
