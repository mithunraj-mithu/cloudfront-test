# ADR-0001: Alamy Labs Infrastructure Guidelines

## Status
Accepted — 2026-02-11 (Updated 2026-04-15)

## Context
This document outlines the standard operational structure for the Alamy Labs (`labs.alamy.com`) infrastructure repository. This environment acts as a reverse proxy router to various external Proof of Concept (POC) applications hosted on PaaS (Platform as a Service) providers like Vercel, Netlify, or Bolt. 

Terraform runs exclusively via GitHub Actions CI/CD pipelines. Manual executions are prohibited to maintain state integrity.

## Decision

### 1. File Layout
- **Flat structure** inside the `terraform/` directory. 
- Files are named by their AWS service or logical purpose (e.g., `cloudfront.tf`, `acm.tf`, `r53.tf`, `iam.tf`). We do not use a monolithic `main.tf` file.

### 2. State & Environment Management
- **Workspaces + Per-Environment Configs:** Isolated state files. Backend configurations (`backends/*.conf`) separate the S3 state storage, and variable files (`workspaces/*.tfvars`) inject environment-specific variables.
- **S3 Backend Configuration:** State is stored in Amazon S3 with AES-256 server-side encryption enabled. State locking is handled via an Amazon DynamoDB table.

### 3. Execution & Dependencies
- **Pessimistic Provider Constraints:** Provider versions are locked using the pessimistic constraint operator (e.g., `~> 5.52.0`). This allows minor patch updates for security but blocks major versions.
- **No Local `.terraform.lock.hcl`:** The CI pipeline runs `terraform init -upgrade` to resolve the provider dependency tree dynamically based on the pessimistic constraints.

### 4. Security & Compliance
- **Strict TLS Standards:** All CloudFront viewer certificates and origin connections enforce `TLSv1.2` as the minimum protocol. `TLSv1.1` and older are explicitly rejected.
- **IAM Best Practices:** The infrastructure relies entirely on Assumed Roles (`sts:AssumeRole`) and Instance Profiles. We do not provision IAM Users or generate static access keys.

### 5. CloudFront Log Storage
CloudFront Standard Logs are written to a dedicated S3 bucket. The following production standards apply.

#### Delivery Model
The `logging_config` block inside `aws_cloudfront_distribution` uses CloudFront's **legacy log delivery path**. AWS's delivery fleet writes objects under the `awslogsdelivery` AWS account and applies the `log-delivery-write` canned ACL on every PUT. This is a hard-wired AWS-side behaviour that imposes two constraints on the bucket:

1. `object_ownership` must be `BucketOwnerPreferred` (not `BucketOwnerEnforced`) — ACLs must remain enabled so the delivery fleet can set them.
2. `block_public_acls` and `ignore_public_acls` must be `false` — the delivery PUT carries an ACL header; blocking it causes `AccessDenied` on every write.

`block_public_policy` and `restrict_public_buckets` remain `true` because the bucket policy (`iam.tf`) is a resource-based policy, not a public policy, and these controls provide an additional safeguard against future operator error.

#### Encryption
Log objects are encrypted at rest using **SSE-S3 (AES-256)**. A KMS CMK cannot be used here: CloudFront's legacy delivery fleet does not have permission to call `kms:GenerateDataKey` on a customer-managed key, which would cause every log delivery PUT to fail. SSE-S3 encrypts every object at rest; the key is managed and rotated automatically by S3. All access to the bucket is gated by the `DenyNonTLS` bucket policy statement, ensuring data in transit is always protected by TLS.

#### Bucket Hardening
| Control | Setting |
|---|---|
| `block_public_acls` | `false` — required for legacy CloudFront delivery |
| `ignore_public_acls` | `false` — required for legacy CloudFront delivery |
| `block_public_policy` | `true` — prevents public bucket policies |
| `restrict_public_buckets` | `true` — prevents public access via policies |
| Object ownership | `BucketOwnerPreferred` — bucket owner takes ownership of all delivered objects |
| Bucket ACL | `log-delivery-write` — grants `awslogsdelivery` write access |
| Encryption | SSE-S3 (AES-256) |
| Versioning | Enabled — supports recovery of overwritten or deleted log objects |
| TLS enforcement | Bucket policy `DenyNonTLS` statement rejects all non-HTTPS requests |
| `force_destroy` | `false` in production — prevents accidental destruction of audit logs |

#### Log Lifecycle (Production)
| Age | Storage class | Rationale |
|---|---|---|
| 0 – 30 days | S3 Standard | Hot tier — active querying, alerting, dashboards |
| 30 – 90 days | S3 Standard-IA | Warm tier — occasional incident lookups |
| 90 – 365 days | S3 Glacier IR | Cold tier — compliance and forensic retention |
| > 365 days | Expired | Hard deletion after one year |

Non-current versions (created by versioning on overwrites) transition to Standard-IA after 30 days and expire after 90 days to prevent unbounded storage growth. Incomplete multipart uploads are aborted after 7 days.

#### Log Prefix Convention
CloudFront writes logs under `{service}/{workspace}/` (e.g., `alamy-labs/production/`). This prefix is defined in `cloudfront.tf` and mirrored in the `s3:PutObject` resource ARN inside the bucket policy to enforce least-privilege delivery.

## Adding a New Application
To add a new POC application to the Labs router:
1. Open the target environment's variable file (e.g., `production.tfvars`).
2. Add a new key-value pair to the `labs_applications` map block.
3. Commit and push. The pipeline will dynamically create a new CloudFront Origin and Cache Behavior route.
