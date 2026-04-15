# IAM resources for the CloudFront logs S3 bucket.
#
# Delivery model: CloudFront's legacy logging_config delivery path writes
# objects using the awslogsdelivery AWS account and the log-delivery-write
# canned ACL (granted in s3.tf). No IAM role, user, or service-principal
# bucket policy statement is needed for delivery itself.


# ── S3 bucket policy — TLS enforcement only ───────────────────────────────────
data "aws_iam_policy_document" "cloudfront_logs_bucket" {
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
}



data "aws_iam_policy_document" "cloudfront_logs_kms" {
  statement {
    sid    = "AllowRootAdmin"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudFrontLogDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]
  }
}


resource "aws_s3_bucket_policy" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  policy = data.aws_iam_policy_document.cloudfront_logs_bucket.json

  # Bucket policy must be applied after the public access block and ACL are in
  # place; Terraform can otherwise race between block_public_policy = true and
  # the policy attachment during a fresh apply.
  depends_on = [
    aws_s3_bucket_public_access_block.cloudfront_logs,
    aws_s3_bucket_acl.cloudfront_logs,
  ]
}

# ── Supporting data sources ───────────────────────────────────────────────────
data "aws_caller_identity" "current" {}
