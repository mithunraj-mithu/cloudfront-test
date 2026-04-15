# The alamy.com zone is shared infrastructure — looked up via data source,
# never managed or destroyed by this stack.
data "aws_route53_zone" "main" {
  name         = var.hosted_zone_name
  private_zone = false
}
