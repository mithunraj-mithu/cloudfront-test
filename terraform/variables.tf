# variables.tf
#
# All input variable declarations with validation.
# No variable should be read directly from a provider or data source here.

variable "region" {
  type        = string
  default     = "eu-west-1"
  description = "Primary AWS region. ACM, CloudWatch Logs, and KMS are always provisioned in us-east-1 via provider alias."
}

variable "service" {
  type        = string
  default     = "alamy-labs"
  description = "Service identifier used in resource names and tags."
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
# labs.alamy.com/{key}/* → https://{origin_domain}/{key}/*
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

variable "s3_force_destroy" {
  type        = bool
  default     = false
  description = "Allow Terraform to destroy the default-origin S3 bucket even if it contains objects. Set true only for non-production workspaces."
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "CloudWatch Log Group retention in days for CloudFront access logs."

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "Must be a valid CloudWatch Logs retention period."
  }
}