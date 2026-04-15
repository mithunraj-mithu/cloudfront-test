#fetching the hosted zone ID for the given domain name, which is needed to create DNS records in Route 53.
data "aws_route53_zone" "main" {
  name         = var.hosted_zone_name
  private_zone = false
}
