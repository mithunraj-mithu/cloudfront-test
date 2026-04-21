# outputs.tf

output "labs_url" {
  description = "Public base URL for Alamy Labs."
  value       = "https://${local.labs_fqdn}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID — use for cache invalidations."
  value       = aws_cloudfront_distribution.labs.id
}

output "cloudfront_domain_name" {
  description = "CloudFront domain name (*.cloudfront.net)."
  value       = aws_cloudfront_distribution.labs.domain_name
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate."
  value       = aws_acm_certificate.labs.arn
}

output "route53_zone_id" {
  description = "Route 53 hosted zone ID."
  value       = data.aws_route53_zone.main.zone_id
}

output "cloudfront_log_group" {
  description = "CloudWatch Log Group name for CloudFront access logs (always in us-east-1)."
  value       = aws_cloudwatch_log_group.cloudfront_logs.name
}

output "default_origin_bucket" {
  description = "S3 bucket name for the default (catch-all) origin."
  value       = aws_s3_bucket.default_origin.bucket
}

output "application_urls" {
  description = "Map of app name to public URL."
  value = {
    for name in keys(var.labs_applications) :
    name => "https://${local.labs_fqdn}/${name}/"
  }
}