# ADR-0001: Terraform Project Structure & Infrastructure Conventions

## Status

Proposed — 2026-04-20 (Updated to reflect Trivy-compliant S3 logging)

---

## Context

The Alamy Labs infrastructure provisions a CloudFront reverse proxy and its supporting resources (ACM, Route 53, S3, IAM) using Terraform. This ADR establishes the conventions that govern how this Terraform project is structured, versioned, and executed. It does not cover the CloudFront architecture itself — see [ADR-0002](0002-cloudfront-architecture-overview.md).

---

## Decisions

### 1. File layout

The `terraform/` directory uses a flat structure. Each file owns one AWS service or logical concern:

| File | Responsibility |
|---|---|
| `cloudfront.tf` | Distribution, origin request policy, cache policy |
| `acm.tf` | TLS certificate lifecycle (us-east-1 provider alias) |
| `r53.tf` | Route 53 ALIAS records |
| `s3.tf` | S3 bucket for access logs (fully locked down, `BucketOwnerEnforced`) |
| `iam.tf` | Resource-based policies (S3 bucket policy for CloudFront delivery) |
| `data.tf` | Read-only data sources |
| `locals.tf` | Computed locals (`labs_fqdn`, `app_names`) |
| `variables.tf` | All input variable declarations with validation |
| `outputs.tf` | Stack outputs |
| `providers.tf` | Provider configuration, default tags, S3 backend |
| `versions.tf` | Terraform core and provider version constraints |

There is no `main.tf`. Grouping by service makes it unambiguous where any given resource lives.

### 2. Version constraints

`versions.tf` declares the Terraform core constraint:

```hcl
terraform {
  required_version = ">= 1.0.0, < 2.0.0"
}
```

The AWS provider is pinned in `providers.tf` using the pessimistic constraint operator:

```hcl
aws = {
  source  = "hashicorp/aws"
  version = "~> 5.82.0"
}
```

`~> 5.82.0` permits patch releases (`5.82.x`) but blocks minor and major version bumps, preventing silent API surface changes while still picking up security patches. There is no committed `.terraform.lock.hcl`; the CI pipeline runs `terraform init -upgrade` on each run, resolving the dependency tree dynamically within the stated constraints.

### 3. Provider configuration

Two AWS provider instances are declared in `providers.tf`:

- `aws` — primary region (`eu-west-1` by default, overridable via `var.region`). Used for all resources except ACM.
- `aws.us_east_1` — alias locked to `us-east-1`. Used exclusively by `acm.tf`, because CloudFront only accepts certificates provisioned in that region.

Both providers share identical `default_tags`:

```hcl
default_tags {
  tags = {
    Service        = "Alamy Labs"
    TeamName       = "DevOps"
    RepositoryName = "cloudfront-labs"
    CreatedBy      = "Terraform"
    Environment    = title(terraform.workspace)
    Org            = "Alamy"
  }
}
```

Resource-level `tags` blocks use `merge(var.tags, { Name = "..." })` to layer a `Name` tag and any caller-supplied extras on top of the defaults.

### 4. State management

State is stored remotely in S3 with DynamoDB locking:

```hcl
backend "s3" {
  encrypt = true
}
```

`encrypt = true` enables AES-256 SSE on the state file. The bucket name, key path, and DynamoDB table are injected at init time from the backend config file in `backends/`. This stack targets a single production workspace.

### 5. Variable validation

All variables that accept free-form strings are guarded by `validation` blocks. Key rules:

| Variable | Constraint |
|---|---|
| `labs_subdomain` | `^[a-z0-9-]+$` — lowercase alphanumeric and hyphens only |
| `default_origin_domain` | Valid hostname, no protocol prefix |
| `cloudfront_price_class` | Enum: `PriceClass_100`, `PriceClass_200`, `PriceClass_All` |
| `labs_applications` keys | `^[a-z0-9-]+$` |
| `labs_applications[*].origin_domain` | Valid hostname, no protocol prefix |

Validation runs at plan time, producing a descriptive error before any API call is made.

### 6. Locals

`locals.tf` centralises computed values:

```hcl
locals {
  labs_fqdn = "${var.labs_subdomain}.${var.hosted_zone_name}"  # → labs.alamy.com
  app_names = sort(keys(var.labs_applications))
}
```

`labs_fqdn` is the single source of truth for the domain string used in the certificate, CloudFront alias, Route 53 records, and the `X-Forwarded-Host` custom header. `app_names` provides a sorted list used in outputs.

### 7. Data sources

`data.tf` looks up the `alamy.com` hosted zone by name:

```hcl
data "aws_route53_zone" "main" {
  name         = var.hosted_zone_name
  private_zone = false
}
```

The hosted zone is shared infrastructure managed outside this stack. Using a data source (rather than a resource) ensures this stack can never accidentally destroy it.

### 8. ACM certificate lifecycle

`acm.tf` provisions the TLS certificate with `create_before_destroy = true`, allowing certificate rotation without downtime. DNS validation records are written to Route 53 automatically via a `for_each` over `domain_validation_options`. The `aws_acm_certificate_validation` resource blocks the apply from completing until the certificate reaches `ISSUED` status.

### 9. Outputs

`outputs.tf` exposes the following:

| Output | Description |
|---|---|
| `labs_url` | Public base URL |
| `cloudfront_distribution_id` | Used for cache invalidations |
| `cloudfront_domain_name` | The `*.cloudfront.net` domain |
| `acm_certificate_arn` | Certificate ARN |
| `route53_zone_id` | Hosted zone ID |
| `cloudfront_log_bucket` | S3 bucket name for access logs |
| `application_urls` | `map(string)` of app name → full public URL |

### 10. CI/CD and execution policy

Terraform is executed exclusively via GitHub Actions. Manual plan or apply runs are prohibited to prevent state drift. The pipeline uses short-lived credentials via `sts:AssumeRole` against a GitHub Environment-scoped IAM role (`production`). No IAM users or static access keys are provisioned.

The four workflows and their roles:

| Workflow | Trigger | Terraform action |
|---|---|---|
| `test.yml` | PR → main | `init -backend=false`, `validate`, `fmt -check`, TFLint |
| `plan.yml` | PR → main (`terraform/**` paths) | `plan` against production workspace; result posted as sticky PR comment |
| `release.yml` | Push to main | No Terraform — creates semver tag, GitHub Release, triggers `production.yml` |
| `production.yml` | Triggered by `release.yml` or manual `workflow_dispatch` | `apply` against production workspace |

Security scanning runs in `test.yml` alongside linting: TruffleHog scans for leaked secrets, Trivy scans Terraform config for `HIGH` and `CRITICAL` severity misconfigurations. The S3 logging architecture explicitly uses modern standard delivery (no ACLs, `BucketOwnerEnforced`, SSE-S3) to ensure 100% native Trivy compliance without requiring `.trivyignore` suppressions.

### 11. Access logging: S3 over CloudWatch Logs

CloudFront access logs are delivered to S3 (`s3.tf`) rather than CloudWatch Logs. AWS recently released CloudFront Standard Logging v2, which adds native delivery directly to a CloudWatch Log Group — removing the need for an S3 bucket entirely. This was considered and rejected for the following reasons.

CloudWatch Logs v2 was considered but rejected primarily on cost — ingestion is ~$0.50/GB versus fractions of a penny for S3. Any long-term retention requirement would also force a secondary Kinesis Firehose pipeline back to S3 Glacier anyway, negating the simplicity gain. S3 delivery is cheaper, equally Trivy-compliant, and sufficient for a POC proxy.

---

## Consequences

- The flat file layout scales to ~10–15 files before module extraction becomes necessary. Extract to modules when a second independently deployable stack needs to reuse any of these resources.
- The absence of a committed lock file means provider resolution happens on every CI run. If reproducible builds become a hard requirement, commit `.terraform.lock.hcl` and remove `-upgrade`.
- `create_before_destroy` on the ACM certificate means two certificates will briefly coexist in ACM during rotation. This is expected and does not affect availability.
- Keeping `versions.tf` separate from `providers.tf` makes it straightforward to locate and update the Terraform core constraint without touching provider configuration.
- Standardising on SSE-S3 for logging buckets prevents KMS-related delivery failures while maintaining compliance with Trivy standards.
