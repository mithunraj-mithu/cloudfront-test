# acm.tf — TLS certificate for labs.alamy.com.
# Must be provisioned in us-east-1 — CloudFront only accepts certs from that region.

resource "aws_acm_certificate" "labs" {
  domain_name       = local.labs_fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.tags, {
    Name = "alamy-labs-certificate"
  })
}

# DNS validation records written to Route 53 automatically.
resource "aws_route53_record" "labs_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.labs.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = data.aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

# Blocks apply until the certificate is fully validated.
resource "aws_acm_certificate_validation" "labs" {
  certificate_arn         = aws_acm_certificate.labs.arn
  validation_record_fqdns = [for record in aws_route53_record.labs_cert_validation : record.fqdn]
}
