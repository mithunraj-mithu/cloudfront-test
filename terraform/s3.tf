# S3 bucket for CloudFront Standard Logs
#
# Delivery model (Modernized): ACLs are fully disabled via BucketOwnerEnforced.
# The bucket is locked down completely (all Public Access Blocks = true).
# Delivery is permitted explicitly by the AllowCloudFrontStandardLogDelivery 
# statement in the bucket policy (iam.tf).

resource "aws_s3_bucket" "cloudfront_logs" {
  bucket = "${var.service}-cloudfront-logs-${terraform.workspace}"

  # Production: prevent accidental destruction of audit logs.
  force_destroy = false

  tags = merge(var.tags, {
    Name        = "${var.service}-cloudfront-logs"
    Environment = terraform.workspace
    Purpose     = "cloudfront-access-logs"
  })
}

# ── Public access block ─────────────────
resource "aws_s3_bucket_public_access_block" "cloudfront_logs" {
  bucket                  = aws_s3_bucket.cloudfront_logs.id
  block_public_acls       = true 
  ignore_public_acls      = true 
  block_public_policy     = true
  restrict_public_buckets = true
}

# ── Ownership ───────────────────
# Disables ACLs completely. All objects are owned by the bucket owner.
resource "aws_s3_bucket_ownership_controls" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ── Server-side encryption (SSE-S3 / AES-256) ────────────────────────────────
# Note: CloudFront standard logging still does NOT support SSE-KMS, even with 
# the modern IAM delivery. SSE-S3 is natively used.
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── Versioning ────────────────────────────────────────────────────────────────
resource "aws_s3_bucket_versioning" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── Lifecycle ─────────────────────────────────────────────────────────────────
resource "aws_s3_bucket_lifecycle_configuration" "cloudfront_logs" {
  bucket = aws_s3_bucket.cloudfront_logs.id
  depends_on = [aws_s3_bucket_versioning.cloudfront_logs]

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

  rule {
    id     = "abort-incomplete-mpu"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}