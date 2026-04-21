# ACM certificate for labs.alamy.com.
# Must use the us_east_1 provider alias — CloudFront only accepts certs from us-east-1.

resource "aws_acm_certificate" "labs" {
  provider = aws.us_east_1

  domain_name               = local.labs_fqdn
  subject_alternative_names = [local.labs_fqdn]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.service}-certificate"
  }
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

# Blocks apply until the certificate reaches ISSUED status.
resource "aws_acm_certificate_validation" "labs" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.labs.arn
  validation_record_fqdns = [for record in aws_route53_record.labs_cert_validation : record.fqdn]
}
