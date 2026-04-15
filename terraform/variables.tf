# =============================================================================
# variables.tf — workspace-specific values live in workspaces/{env}.tfvars
# =============================================================================

variable "region" {
  type        = string
  default     = "eu-west-1"
  description = "Primary AWS region. ACM is always provisioned in us-east-1 regardless."
}

variable "service" {
  type        = string
  default     = "alamy-labs"
  description = "Service identifier used for resource naming and tagging."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags merged with provider default_tags."
}

variable "hosted_zone_name" {
  type        = string
  default     = "alamy.com"
  description = "Route 53 hosted zone name. Must exist and be managed outside this stack."
}

variable "alamy_domain" {
  type        = string
  default     = "alamy.com"
  description = "Root domain combined with labs_subdomain to produce the public FQDN."
}

variable "labs_subdomain" {
  type        = string
  default     = "labs"
  description = "Subdomain prefix — produces labs.alamy.com by default."
}

variable "default_origin_domain" {
  type        = string
  description = "Fallback origin for unmatched paths (e.g. a static error page)."
}

variable "cloudfront_price_class" {
  type        = string
  default     = "PriceClass_100"
  description = "CloudFront edge coverage. PriceClass_100 = US/EU, PriceClass_All = global."

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

# Each key becomes a path prefix on labs.alamy.com and a CloudFront behaviour.
# labs.alamy.com/{key}/* → {origin_domain}/*
variable "labs_applications" {
  type = map(object({
    origin_domain = string
  }))
  description = "Map of app name to external origin. Each key creates a behaviour and origin."
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.labs_applications : can(regex("^[a-z0-9-]+$", k))])
    error_message = "Keys must be lowercase alphanumeric with hyphens only (e.g. 'my-app')."
  }
}
