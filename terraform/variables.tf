variable "region" {
  type        = string
  default     = "eu-west-1"
  description = "Primary AWS region. ACM is always provisioned in us-east-1 via provider alias."
}

variable "service" {
  type        = string
  default     = "alamy-labs"
  description = "Service identifier used in resource names and tags."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags merged with provider default_tags."
}

variable "hosted_zone_name" {
  type        = string
  default     = "alamy.com"
  description = "Route 53 hosted zone name. Must exist outside this stack."
}

variable "labs_subdomain" {
  type        = string
  default     = "labs"
  description = "Subdomain prefix — produces labs.alamy.com."

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.labs_subdomain))
    error_message = "Must be lowercase alphanumeric with hyphens only."
  }
}

variable "default_origin_domain" {
  type        = string
  description = "Fallback origin hostname for unmatched paths. No protocol prefix."

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9\\-\\.]+[a-zA-Z0-9]$", var.default_origin_domain))
    error_message = "Must be a valid hostname without a protocol prefix."
  }
}

variable "cloudfront_price_class" {
  type        = string
  default     = "PriceClass_100"
  description = "PriceClass_100 = US/EU. PriceClass_200 adds Asia/SA. PriceClass_All = global."

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.cloudfront_price_class)
    error_message = "Must be one of: PriceClass_100, PriceClass_200, PriceClass_All."
  }
}

# Map of app name → external origin hostname.
# Each key creates a CloudFront origin and ordered cache behaviour.
# labs.alamy.com/{key}/* → https://{origin_domain}/*
#
# Example:
#   labs_applications = {
#     myapp = { origin_domain = "myapp.vercel.app" }
#   }
variable "labs_applications" {
  type = map(object({
    origin_domain = string
  }))
  description = "Map of app name to external origin. Keys must be lowercase alphanumeric with hyphens."
  default     = {}

  validation {
    condition     = alltrue([for k, v in var.labs_applications : can(regex("^[a-z0-9-]+$", k))])
    error_message = "Keys must be lowercase alphanumeric with hyphens only."
  }

  validation {
    condition     = alltrue([for k, v in var.labs_applications : can(regex("^[a-zA-Z0-9][a-zA-Z0-9\\-\\.]+[a-zA-Z0-9]$", v.origin_domain))])
    error_message = "origin_domain values must be valid hostnames without a protocol prefix."
  }
}
