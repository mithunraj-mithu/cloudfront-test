# Alamy Labs — CloudFront Reverse Proxy

Serves externally hosted POC applications under a consistent Alamy vanity URL:

```
https://labs.alamy.com/{app}/*  →  https://{origin}/*
```

PMs and designers can share POC links that appear as first-party Alamy properties without migrating onto Alamy infrastructure.

## How it works

1. `labs.alamy.com` resolves to a CloudFront distribution via Route 53 ALIAS.
2. CloudFront matches the request path against a per-application behaviour (`/{app}/*`).
3. A CloudFront Function strips the `/{app}` prefix before forwarding to the origin.
4. The request is proxied to the external platform (Vercel, Bolt, etc.) over HTTPS.

## Adding an application

Add one entry to `labs_applications` in the relevant workspace tfvars and raise a PR:

```hcl
labs_applications = {
  myapp = { origin_domain = "myapp.vercel.app" }
}
```

This automatically creates a CloudFront origin and behaviour. No code changes required.

## Project layout

```
terraform/
├── cloudfront.tf          CloudFront distribution, behaviours, and path rewrite function
├── acm.tf                 TLS certificate for labs.alamy.com (us-east-1)
├── r53.tf                 Route 53 ALIAS records
├── data.tf                Read-only data sources (hosted zone lookup)
├── locals.tf              Computed values (FQDN, app name list)
├── variables.tf           Input variable definitions
├── outputs.tf             Stack outputs
├── providers.tf           AWS provider configuration and remote state backend
├── versions.tf            Terraform version constraint
├── backends/              Remote state configuration per environment
└── workspaces/            Variable values per environment (tfvars)
```

## CI/CD

| Stage       | Trigger                | Environment   |
| ----------- | ---------------------- | ------------- |
| Development | PR opened / updated    | `development` |
| Cleanup     | PR closed              | `development` |
| Staging     | Merge to main          | `staging`     |
| Production  | Manual (select a tag)  | `production`  |

## Local development

```bash
terraform fmt -recursive terraform/
tflint --chdir=terraform/
```

## Setup checklist

After cloning this repo:

- [ ] Set `bucket` and `key` in `terraform/backends/*.conf`
- [ ] Update `default_tags` in `terraform/providers.tf`
- [ ] Set `default_origin_domain` in each `workspaces/*.tfvars`
- [ ] Create `development`, `staging`, and `production` GitHub Environments with `AWS_ROLE_ARN`
