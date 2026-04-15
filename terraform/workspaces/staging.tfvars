# =============================================================================
# workspaces/staging.tfvars
#
# Deployed automatically on merge to main.
# =============================================================================

region                = "eu-west-1"
hosted_zone_name      = "alamy.com"
default_origin_domain = "your-fallback-origin.example.com"

# -----------------------------------------------------------------------------
# POC Applications
#
# Add an entry per application. The map key becomes the URL path prefix.
#
#   https://labs.alamy.com/{key}/*  →  https://{origin_domain}/*
#
# Example:
#   myapp = { origin_domain = "myapp.vercel.app" }
# -----------------------------------------------------------------------------

labs_applications = {
  # myapp = { origin_domain = "myapp.vercel.app" }
}
