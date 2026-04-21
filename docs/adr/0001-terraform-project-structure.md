# ADR-0001: Terraform Project Structure & Infrastructure Conventions

## Status

Accepted — 2026-04-20  
Updated — 2026-04-22 (S3 OAC default origin; `s3_force_destroy`, `log_retention_days` variables; lifecycle rule; static asset path; versions.tf consolidation)

---

## Context

The Alamy Labs infrastructure provisions a CloudFront reverse proxy and its supporting resources (ACM, Route 53, S3, CloudWatch Logs, KMS) using Terraform. This ADR covers project structure, versioning, state, and execution conventions. CloudFront architecture is in [ADR-0002](0002-cloudfront-architecture-overview.md).

---

## Decisions

### 1. File layout

Flat structure under `terraform/`. Each file owns one AWS service or logical concern. There is no `main.tf`.

| File | Responsibility |
|---|---|
| `cloudfront.tf` | Distribution, OAC, origin request policy, cache policy |
| `acm.tf` | TLS certificate lifecycle (us-east-1 provider alias) |
| `r53.tf` | Route 53 A + AAAA ALIAS records |
| `s3.tf` | Default-origin bucket, public-access block, versioning, encryption, lifecycle, bucket policy, `index.html` object |
| `cloudwatch.tf` | Log Group, delivery destination, delivery source, delivery link |
| `kms.tf` | CMK and alias for Log Group encryption |
| `data.tf` | Read-only data sources and IAM policy documents |
| `locals.tf` | Computed local `labs_fqdn` |
| `variables.tf` | All input variable declarations with validation |
| `outputs.tf` | Stack outputs |
| `providers.tf` | Provider configuration, default tags, S3 backend, provider version constraints |
| `versions.tf` | Terraform core version constraint |
| `static/index.html` | Holding page served for unmatched paths |

### 2. Version constraints

`versions.tf` pins the Terraform core version:

```hcl
terraform {
  required_version = ">= 1.9.0, < 2.0.0"
}
```

`providers.tf` pins the AWS provider with the pessimistic constraint operator, permitting patch releases only:

```hcl
aws = {
  source  = "hashicorp/aws"
  version = "~> 5.94.0"
}
```

The two `terraform {}` blocks (one in `versions.tf`, one in `providers.tf`) are merged at init time by Terraform and are intentionally split by concern. No `.terraform.lock.hcl` is committed. CI runs `terraform init -upgrade` on each execution, resolving the dependency tree within declared constraints.

### 3. Provider configuration

Two provider instances are declared in `providers.tf`:

- `aws` — primary region (`var.region`, defaults to `eu-west-1`). Used for all resources except ACM, CloudWatch Logs, KMS, and S3 (S3 bucket itself uses the primary region, but the log delivery resources require `us-east-1`).
- `aws.us_east_1` — alias locked to `us-east-1`. Used by `acm.tf`, `cloudwatch.tf`, and `kms.tf`. CloudFront is a global service and its Standard Logging v2 delivery chain (`ACCESS_LOGS` log type) is only supported in `us-east-1`; the Log Group and CMK must reside in the same region.

Both share the same `default_tags`:

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

Resource-level `tags` blocks contain only `{ Name = "..." }`. No `merge()` or `var.tags` is needed.

### 4. State management

Remote state in S3 with DynamoDB locking:

```hcl
backend "s3" {
  encrypt = true
}
```

`encrypt = true` enables AES-256 SSE on the state file. Bucket, key path, and DynamoDB table are injected at init time from `backends/`. Single production workspace.

### 5. Variable validation

| Variable | Constraint |
|---|---|
| `labs_subdomain` | `^[a-z0-9-]+$` |
| `cloudfront_price_class` | Enum: `PriceClass_100`, `PriceClass_200`, `PriceClass_All` |
| `labs_applications` keys | `^[a-z0-9-]+$` |
| `labs_applications[*].origin_domain` | Valid hostname, no protocol prefix |
| `log_retention_days` | Valid CloudWatch Logs retention integer |

Validation runs at plan time, before any API call.

### 6. Locals

`locals.tf` defines the single source of truth for the public domain:

```hcl
locals {
  labs_fqdn = "${var.labs_subdomain}.${var.hosted_zone_name}"
}
```

`labs_fqdn` is consumed by ACM, CloudFront aliases, Route 53 records, and the `X-Forwarded-Host` custom header.

### 7. Data sources

`data.tf` contains all read-only data sources and IAM policy documents:

- `aws_route53_zone.main` — looks up the hosted zone by name; a data source ensures this stack cannot destroy it.
- `aws_caller_identity.current` — resolves the account ID for KMS key policy ARNs, IAM condition values, and the S3 bucket policy.
- `aws_iam_policy_document.cloudwatch_kms` — KMS key policy granting the account root and the CloudWatch Logs service (`logs.us-east-1.amazonaws.com`) permission to use the CMK, scoped to the specific log group ARN via `kms:EncryptionContext:aws:logs:arn`.
- `aws_iam_policy_document.default_origin_bucket` — S3 bucket policy granting CloudFront OAC `s3:GetObject` access, scoped to this distribution ARN via `AWS:SourceArn`.

### 8. ACM certificate lifecycle

`acm.tf` provisions the TLS certificate with `create_before_destroy = true`. DNS validation records are written to Route 53 via `for_each` over `domain_validation_options`. `aws_acm_certificate_validation` blocks apply completion until the certificate reaches `ISSUED` status.

### 9. Default origin — S3 with OAC

The CloudFront default (catch-all) behaviour is backed by an S3 bucket rather than an external origin. This ensures a reliable, controlled holding page is returned for all unmatched paths.

`s3.tf` provisions:

- **`aws_s3_bucket`** — `${service}-default-origin-${workspace}`. `force_destroy` controlled by `var.s3_force_destroy` (default `false`; set `true` only in non-production workspaces).
- **`aws_s3_bucket_public_access_block`** — all four block settings enabled; no public access.
- **`aws_s3_bucket_versioning`** — enabled; required for lifecycle non-current version expiry.
- **`aws_s3_bucket_server_side_encryption_configuration`** — AES-256 SSE.
- **`aws_s3_bucket_lifecycle_configuration`** — expires non-current versions after 30 days; aborts incomplete multipart uploads after 7 days.
- **`aws_s3_bucket_policy`** — grants CloudFront OAC `s3:GetObject` scoped to this distribution (see `data.tf`).
- **`aws_s3_object`** — uploads `static/index.html` as the holding page (key: `index.html`, `content_type: text/html`, tracked via `etag`).

`cloudfront.tf` provisions `aws_cloudfront_origin_access_control` (`sigv4`, `always` signing) and references the bucket's regional domain name as the default origin. CloudFront custom error responses map S3 `403` and `404` responses to `index.html` with HTTP `404`, with `error_caching_min_ttl = 0`.

The static holding page source is `terraform/static/index.html`. This file must exist before `terraform apply`.

### 10. Outputs

| Output | Description |
|---|---|
| `labs_url` | Public base URL |
| `cloudfront_distribution_id` | Used for cache invalidations |
| `cloudfront_domain_name` | `*.cloudfront.net` domain |
| `acm_certificate_arn` | Certificate ARN |
| `route53_zone_id` | Hosted zone ID |
| `cloudfront_log_group` | CloudWatch Log Group name (always in us-east-1) |
| `default_origin_bucket` | S3 bucket name for the catch-all origin |
| `application_urls` | `map(string)` of app name → full public URL |

### 11. CI/CD

Terraform runs exclusively in GitHub Actions via short-lived credentials (`sts:AssumeRole`, `production` GitHub Environment). Manual runs are prohibited.

| Workflow | Trigger | Action |
|---|---|---|
| `test.yml` | PR → main | `init -backend=false`, `validate`, `fmt -check`, TFLint, TruffleHog, Trivy |
| `plan.yml` | PR → main (`terraform/**`) | `plan` against production; result posted as sticky PR comment |
| `release.yml` | Push to main | Creates semver tag + GitHub Release; triggers `production.yml` |
| `production.yml` | Triggered by `release.yml` or `workflow_dispatch` | `apply` against production |

Trivy scans for `HIGH` and `CRITICAL` severity misconfigurations. One suppression is active — see `.trivyignore`.

### 12. Access logging

CloudFront Standard Logging v2 delivers access logs to CloudWatch Logs via three resources in `cloudwatch.tf`, all using `provider = aws.us_east_1`:

- `aws_cloudwatch_log_delivery_source` — registers the CloudFront distribution as a log source (`ACCESS_LOGS`).
- `aws_cloudwatch_log_delivery_destination` — registers the Log Group as the delivery target.
- `aws_cloudwatch_log_delivery` — wires source to destination.

The `ACCESS_LOGS` log type is only supported in `us-east-1`. The Log Group and CMK (`kms.tf`) are therefore also provisioned in `us-east-1` via the same provider alias. Retention is configurable via `var.log_retention_days` (default 30 days). The Log Group is encrypted with the CMK (`enable_key_rotation = true`, 7-day deletion window).

When troubleshooting, query logs in the `us-east-1` region — the Log Group `/aws/cloudfront/labs-{workspace}` will not appear in the console or CLI if the selected region is anything other than `us-east-1`.

---

## Consequences

- The flat layout scales to ~10–15 files before module extraction is warranted. Extract when a second independently deployable stack needs to reuse any of these resources.
- No committed lock file means provider resolution runs on every CI execution. Commit `.terraform.lock.hcl` and remove `-upgrade` if reproducible builds become a hard requirement.
- `create_before_destroy` on the ACM certificate means two certificates briefly coexist in ACM during rotation. This is expected and does not affect availability.
- Destroy the Log Group before the KMS key. Deleting the key first causes delivery failures during the 7-day deletion window.
- `var.s3_force_destroy` defaults to `false`. Attempting to destroy the stack in production while the bucket is non-empty will fail safely. Set `true` only in ephemeral (dev/staging) workspaces.
- The `static/index.html` file must exist at plan and apply time. The `filemd5()` call in `s3.tf` will fail if the file is absent.
