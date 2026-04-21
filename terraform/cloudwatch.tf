# cloudwatch.tf
#
# CloudFront is a global service — all log delivery resources and the Log Group
# must reside in us-east-1 regardless of the stack's primary region.
# The ACCESS_LOGS log type is only supported in us-east-1.
#
# When troubleshooting, set your AWS region to us-east-1 — the Log Group
# /aws/cloudfront/labs-{workspace} will not appear in any other region.

resource "aws_cloudwatch_log_group" "cloudfront_logs" {
  provider          = aws.us_east_1
  name              = "/aws/cloudfront/labs-${terraform.workspace}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.cloudfront_logs.arn

  tags = {
    Name = "${var.service}-cloudfront-logs"
  }
}

resource "aws_cloudwatch_log_delivery_destination" "cloudfront_logs" {
  provider = aws.us_east_1
  name     = "labs-cw-destination-${terraform.workspace}"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.cloudfront_logs.arn
  }
}

resource "aws_cloudwatch_log_delivery_source" "cloudfront_logs" {
  provider     = aws.us_east_1
  name         = "labs-cf-source-${terraform.workspace}"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.labs.arn
}

# Wires the delivery source to the destination.
resource "aws_cloudwatch_log_delivery" "cloudfront_logs" {
  provider                 = aws.us_east_1
  delivery_source_name     = aws_cloudwatch_log_delivery_source.cloudfront_logs.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cloudfront_logs.arn
}