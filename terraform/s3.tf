# S3 bucket for CloudFront Standard Logs (legacy delivery via logging_config).
#
# Delivery model: the aws_cloudfront_distribution logging_config block uses
# CloudFront's legacy log delivery path. AWS's delivery fleet writes objects
# using the "awslogsdelivery" account and applies the log-delivery-write canned
# ACL on each PUT. This hard-wired behaviour requires:
#   • object_ownership = "BucketOwnerPreferred"  (ACLs must remain enabled)
#   • aws_s3_bucket_acl "log-delivery-write"
#   • block_public_acls = false  (the delivery PUT carries an ACL header)
#
# KMS CMK encryption is NOT compatible with legacy delivery — the CloudFront
# fleet cannot call kms:GenerateDataKey on a customer-managed key. SSE-S3
# (AES-256) is used instead; objects are encrypted at rest by S3 itself.
# The DenyNonTLS bucket policy statement in iam.tf ensures all access is
# over HTTPS regardless.
#
# Log lifecycle (production):
#   0–30 d   → S3 Standard        (hot — active querying / alerting)
#   30–90 d  → S3 Standard-IA     (warm — occasional incident lookups)
#   90–365 d → S3 Glacier IR      (cold — compliance / forensic retention)
#   > 365 d  → permanently expired

resource "aws_s3_bucket" "cloudfront_logs" {
  bucket = "${var.service}-cloudfront-logs-${terraform.workspace}"

  # Production: prevent accidental destruction of audit logs.
  # Set to true only when decommissioning the environment intentionally.
  force_destroy = false

  tags = merge(var.tags, {
    Name        = "${var.service}-cloudfront-logs"
    Environment = terraform.workspace
    Purpose     = "cloudfront-access-logs"
  })
}

# ── Public access block ───────────────────────────────────────────────────────
# block_public_acls / ignore_public_acls must be FALSE: CloudFront's legacy
# delivery fleet sets the log-delivery-write canned ACL on each PUT. Blocking
# ACLs at this level causes every delivery write to fail with AccessDenied.
#
# block_public_policy and restrict_public_buckets remain TRUE: the bucket
# policy in iam.tf is a resource-based policy (not a public policy), so these
# controls do not interfere with log delivery and still block any future
# operator error that would make the bucket or its policy public.
resource "aws_s3_bucket_public_access_block" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  block_public_acls       = false # must be false — delivery sets ACL on PUT
  ignore_public_acls      = false # must be false — delivery reads ACL on PUT
  block_public_policy     = true
  restrict_public_buckets = true
}

# ── Ownership: BucketOwnerPreferred ───────────────────────────────────────────
# Required for legacy CloudFront log delivery. The delivery fleet writes objects
# under the awslogsdelivery account; BucketOwnerPreferred ensures the bucket
# owner automatically takes ownership of each log object, even though the PUT
# originates from a different AWS account.
resource "aws_s3_bucket_ownership_controls" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# ── ACL: log-delivery-write ───────────────────────────────────────────────────
# Grants the awslogsdelivery group permission to write objects and read the
# bucket ACL — the two permissions the legacy delivery path requires.
resource "aws_s3_bucket_acl" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  acl    = "log-delivery-write"

  depends_on = [
    aws_s3_bucket_ownership_controls.cloudfront_logs,
    aws_s3_bucket_public_access_block.cloudfront_logs,
  ]
}

# ── Server-side encryption (SSE-S3 / AES-256) ────────────────────────────────
# SSE-S3 is used rather than a KMS CMK because CloudFront's legacy log delivery
# fleet does not have permission to call kms:GenerateDataKey on a customer-
# managed key — applying a CMK here causes every log delivery PUT to fail with
# KMS.DisabledException or AccessDenied.
#
# SSE-S3 still encrypts every object at rest with AES-256; the key is managed
# by S3 and rotated automatically by AWS. All access to the bucket is gated by
# the DenyNonTLS statement in the bucket policy (iam.tf), so data in transit
# is protected by TLS regardless of the at-rest encryption mechanism.
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── Versioning ────────────────────────────────────────────────────────────────
# Enables recovery of accidentally overwritten or deleted log objects.
resource "aws_s3_bucket_versioning" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── Lifecycle ─────────────────────────────────────────────────────────────────
resource "aws_s3_bucket_lifecycle_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  # Depends on versioning being enabled before lifecycle rules apply to
  # non-current versions.
  depends_on = [aws_s3_bucket_versioning.cloudfront_logs]

  # Current-version tiering and expiry.
  rule {
    id     = "log-tiering"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 365
    }
  }

  # Non-current versions (overwritten objects) — retain briefly for recovery,
  # then expire to avoid unbounded storage growth.
  rule {
    id     = "noncurrent-version-expiry"
    status = "Enabled"

    filter {}

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # Clean up incomplete multipart uploads — CloudFront does not use MPU,
  # but this is a hardening best-practice for all buckets.
  rule {
    id     = "abort-incomplete-mpu"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
