# Computed locals shared across the stack.

locals {
  labs_fqdn = "${var.labs_subdomain}.${var.hosted_zone_name}"
  app_names = sort(keys(var.labs_applications))
}
