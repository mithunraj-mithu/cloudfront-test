# =============================================================================
# workspaces/production.tfvars
#
# Deployed manually via the production workflow — select a release tag and
# approve the plan before apply.
# =============================================================================

region                = "ap-south-1"
hosted_zone_name      = "mithunpp4u.shop"
default_origin_domain = "your-fallback-origin.example.com"

# -----------------------------------------------------------------------------
# POC Applications
#
# Add an entry per application. The map key becomes the URL path prefix.
#
#   https://labs.mithunpp4u.shop/{key}/*  →  https://{origin_domain}/*
#
# Example:
#   myapp = { origin_domain = "myapp.vercel.app" }
# -----------------------------------------------------------------------------

labs_applications = {
  # myapp = { origin_domain = "myapp.vercel.app" }
}
