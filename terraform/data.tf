# Read-only data sources for the stack.
#
# Nothing in this file creates or destroys infrastructure.

# The hosted zone is shared infrastructure managed outside this stack.
# Using a data source ensures this stack can never accidentally destroy it.
data "aws_route53_zone" "main" {
  name         = var.hosted_zone_name
  private_zone = false
}

# Current AWS account ID — used in KMS key policy ARNs and IAM condition values.
data "aws_caller_identity" "current" {}

# KMS key policy: grants the account root and CloudWatch Logs service permission
# to use the CMK, scoped to the specific log group ARN.
data "aws_iam_policy_document" "cloudwatch_kms" {
  statement {
    sid       = "EnableIAMUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.us-east-1.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:us-east-1:${data.aws_caller_identity.current.account_id}:log-group:/aws/cloudfront/labs-${terraform.workspace}"]
    }
  }
}
# S3 bucket policy for the default origin.
# Grants CloudFront OAC read access only — scoped to this distribution and this account.
data "aws_iam_policy_document" "default_origin_bucket" {
  statement {
    sid     = "AllowCloudFrontOACReadOnly"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      "${aws_s3_bucket.default_origin.arn}/*"
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.labs.arn]
    }
  }
}
