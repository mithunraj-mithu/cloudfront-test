# =============================================================================
# workspaces/production.tfvars — Alamy Labs production environment.
#
# CI/CD usage:
#   terraform init    -backend-config=backends/production.conf
#   terraform workspace select production
#   terraform plan    -var-file=workspaces/production.tfvars
#   terraform apply   -var-file=workspaces/production.tfvars
#
# To add a new POC application:
#   1. Add one entry to labs_applications below.
#   2. Push — the pipeline creates a new CloudFront origin and behaviour.
#      No code changes are required.
# =============================================================================

region           = "ap-south-1"
hosted_zone_name = "mithunpp4u.shop"
labs_subdomain   = "labs"

# Fallback origin for paths that don't match any application.
# Replace with a real static-site or S3 website endpoint.
default_origin_domain = "labs-default.alamy.com"

# Optional extra tags merged on top of provider default_tags.
tags = {
  CostCentre = "engineering"
}

# -----------------------------------------------------------------------------
# POC Applications
#
# key           = URL path prefix under labs.alamy.com  (lowercase, hyphens ok)
# origin_domain = external hosting hostname             (no protocol prefix)
#
# Result: https://labs.alamy.com/{key}/  →  https://{origin_domain}/
# -----------------------------------------------------------------------------
labs_applications = {
   vercel-credit = { origin_domain = "credit-packs-poc.vercel.app" }
}


