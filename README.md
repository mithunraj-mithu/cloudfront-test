# Alamy Labs — CloudFront Reverse Proxy

Routes externally hosted applications under a consistent Alamy vanity URL:

```
https://labs.alamy.com/{app}/*  →  https://{origin_domain}/{app}/*
```

Unmatched paths return a branded 404 holding page served from an S3 bucket via CloudFront Origin Access Control.

Architecture and infrastructure conventions are documented in the ADRs:

- [ADR-0001 — Terraform Project Structure](docs/adr/0001-terraform-project-structure.md)
- [ADR-0002 — CloudFront Architecture](docs/adr/0002-cloudfront-architecture-overview.md)

## Adding an application

Add one entry to `workspaces/production.tfvars` and raise a PR:

```hcl
labs_applications = {
  myapp = { origin_domain = "myapp.vercel.app" }
}
```

This creates a CloudFront origin and ordered cache behaviour (`/myapp*`). No code changes required.

## Project layout

```
terraform/
├── cloudfront.tf          Distribution, OAC, origin request policy, cache policy
├── acm.tf                 ACM certificate for labs.alamy.com (us-east-1)
├── r53.tf                 Route 53 A + AAAA ALIAS records
├── s3.tf                  Default-origin S3 bucket, versioning, encryption, lifecycle, OAC policy
├── cloudwatch.tf          Log Group, delivery destination, source, and link (us-east-1)
├── kms.tf                 CMK for Log Group encryption (us-east-1)
├── data.tf                Read-only data sources and IAM policy documents
├── locals.tf              labs_fqdn local
├── variables.tf           Input variable declarations with validation
├── outputs.tf             Stack outputs
├── providers.tf           Provider configuration, default tags, S3 backend, provider version pins
├── versions.tf            Terraform core version constraint
├── static/
│   └── index.html         Holding page served for unmatched paths (deployed to S3)
├── backends/              Remote state config per environment
└── workspaces/            tfvars per environment
```

## CI/CD

| Stage | Trigger | Action |
|---|---|---|
| Test | PR opened / updated | `validate`, `fmt -check`, TFLint, TruffleHog, Trivy |
| Plan | PR → main (`terraform/**`) | `plan` against production; result posted as PR comment |
| Release | Merge to main | Semver tag + GitHub Release |
| Production | Triggered by Release or `workflow_dispatch` | `apply` against production |

## Local development

```bash
terraform fmt -recursive terraform/
tflint --chdir=terraform/
```

## Setup checklist

- [ ] Set `bucket`, `key`, and `dynamodb_table` in `terraform/backends/*.conf`
- [ ] Update `default_tags` in `terraform/providers.tf`
- [ ] Confirm `terraform/static/index.html` exists (required at plan time by `filemd5()`)
- [ ] Add application entries to `workspaces/production.tfvars` under `labs_applications`
- [ ] Create `production` GitHub Environment with `AWS_ROLE_ARN`
- [ ] Review `var.s3_force_destroy` — default is `false`; set `true` only for non-production workspaces
- [ ] Review `var.log_retention_days` — default is 30; adjust per data-retention policy

## Key operational notes

**CloudWatch Logs region** — the log group `/aws/cloudfront/labs-{workspace}` is always in `us-east-1`. Set your AWS region to `us-east-1` when querying logs via console or CLI.

**Destroy order** — destroy the CloudWatch Log Group before the KMS key. Deleting the key first causes log delivery failures during the 7-day KMS deletion window.

**WAF** — intentionally not attached (Trivy finding `AVD-AWS-0011` suppressed in `.trivyignore`). Must be re-evaluated and attached before any application that accepts user input or handles sensitive data goes live.

**S3 bucket deletion** — `force_destroy = false` in production. Attempting to destroy the stack while the bucket is non-empty will fail safely. Use `var.s3_force_destroy = true` only in ephemeral workspaces.