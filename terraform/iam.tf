# IAM resources for the CloudFront logs S3 bucket.
#
# Delivery model: Because ACLs are disabled, CloudFront requires an explicit
# resource-based bucket policy allowing s3:PutObject from the CloudFront 
# service principal.

data "aws_iam_policy_document" "cloudfront_logs_bucket" {
  
  # 1. Enforce TLS (Existing)
  statement {
    sid    = "DenyNonTLS"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.cloudfront_logs.arn,
      "${aws_s3_bucket.cloudfront_logs.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # 2. Allow Modern CloudFront Standard Log Delivery
  statement {
    sid    = "AllowCloudFrontStandardLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudfront_logs.arn}/*"]

    # Prevents Confused Deputy attacks
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.labs.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  policy = data.aws_iam_policy_document.cloudfront_logs_bucket.json

  # Bucket policy must be applied AFTER public access block and ownership controls.
  depends_on = [
    aws_s3_bucket_public_access_block.cloudfront_logs,
    aws_s3_bucket_ownership_controls.cloudfront_logs,
  ]
}

# ── Supporting data sources───────────────────────────────
data "aws_caller_identity" "current" {}