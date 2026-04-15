# locals.tf — computed values shared across the stack.

locals {
  labs_fqdn = "${var.labs_subdomain}.${var.alamy_domain}" # e.g. labs.alamy.com
  app_names = sort(keys(var.labs_applications))            # deterministic plan diffs
}
