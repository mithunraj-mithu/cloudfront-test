# Computed values used across the stack.

locals {
  # Single source of truth for the public domain — used in ACM, CloudFront,
  # Route 53, and the X-Forwarded-Host custom header.
  labs_fqdn = "${var.labs_subdomain}.${var.hosted_zone_name}"

}
