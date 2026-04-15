# ALIAS records for labs.alamy.com → CloudFront.
# Both A (IPv4) and AAAA (IPv6) are required as is_ipv6_enabled = true.

resource "aws_route53_record" "labs_a" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.labs_fqdn
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.labs.domain_name
    zone_id                = aws_cloudfront_distribution.labs.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "labs_aaaa" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = local.labs_fqdn
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.labs.domain_name
    zone_id                = aws_cloudfront_distribution.labs.hosted_zone_id
    evaluate_target_health = false
  }
}
