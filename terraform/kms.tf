# KMS key for CloudFront log bucket server-side encryption.

# data "aws_iam_policy_document" "cloudfront_logs_kms" {
#   statement {
#     sid    = "AllowRootAdmin"
#     effect = "Allow"

#     principals {
#       type        = "AWS"
#       identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
#     }

#     actions   = ["kms:*"]
#     resources = ["*"]
#   }

#   statement {
#     sid    = "AllowCloudFrontLogDelivery"
#     effect = "Allow"

#     principals {
#       type        = "Service"
#       identifiers = ["delivery.logs.amazonaws.com"]
#     }

#     actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
#     resources = ["*"]
#   }
# }

resource "aws_kms_key" "cloudfront_logs" {
  description             = "CMK for ${var.service} CloudFront access logs (${terraform.workspace})"
  deletion_window_in_days = 14
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.cloudfront_logs_kms.json

  tags = merge(var.tags, {
    Name        = "${var.service}-cloudfront-logs-cmk"
    Environment = terraform.workspace
  })
}

resource "aws_kms_alias" "cloudfront_logs" {
  name          = "alias/${var.service}-cloudfront-logs-${terraform.workspace}"
  target_key_id = aws_kms_key.cloudfront_logs.key_id
}
