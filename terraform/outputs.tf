# outputs.tf

output "labs_url" {
  description = "Public base URL for the Alamy Labs subdomain."
  value       = "https://${local.labs_fqdn}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — use for cache invalidations."
  value       = aws_cloudfront_distribution.labs.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain (*.cloudfront.net)."
  value       = aws_cloudfront_distribution.labs.domain_name
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate for ${local.labs_fqdn}."
  value       = aws_acm_certificate.labs.arn
}

output "application_urls" {
  description = "Map of application name to its public Alamy Labs URL."
  value = {
    for name in keys(var.labs_applications) :
    name => "https://${local.labs_fqdn}/${name}/"
  }
}
