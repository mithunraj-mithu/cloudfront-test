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

output "cloudfront_log_bucket" {
  description = "S3 bucket for CloudFront access logs."
  value       = aws_s3_bucket.cloudfront_logs.bucket
}

output "kms_key_arn" {
  description = "KMS key ARN used to encrypt the log bucket."
  value       = aws_kms_key.cloudfront_logs.arn
}

output "application_urls" {
  description = "Map of app name to public URL."
  value = {
    for name in keys(var.labs_applications) :
    name => "https://${local.labs_fqdn}/${name}/"
  }
}
