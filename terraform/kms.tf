# KMS Customer Managed Key for CloudFront log group encryption.
# Must reside in us-east-1 to encrypt the Log Group in that region.

resource "aws_kms_key" "cloudfront_logs" {
  provider                = aws.us_east_1
  description             = "CMK for CloudFront access log group (${terraform.workspace})"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.cloudwatch_kms.json

  tags = {
    Name = "${var.service}-cloudfront-logs-cmk"
  }
}

resource "aws_kms_alias" "cloudfront_logs" {
  provider      = aws.us_east_1
  name          = "alias/${var.service}-cloudfront-logs-${terraform.workspace}"
  target_key_id = aws_kms_key.cloudfront_logs.key_id
}
