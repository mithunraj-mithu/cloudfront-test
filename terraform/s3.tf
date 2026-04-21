# s3.tf
#
# S3 bucket serving the default (catch-all) origin for unmatched paths.
# Access is restricted to CloudFront via Origin Access Control — no public access.
# The holding page (static/index.html) is uploaded as an S3 object.

resource "aws_s3_bucket" "default_origin" {
  bucket        = "${var.service}-default-origin-${terraform.workspace}"
  force_destroy = var.s3_force_destroy

  tags = {
    Name = "${var.service}-default-origin"
  }
}

resource "aws_s3_bucket_public_access_block" "default_origin" {
  bucket = aws_s3_bucket.default_origin.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "default_origin" {
  bucket = aws_s3_bucket.default_origin.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "default_origin" {
  bucket = aws_s3_bucket.default_origin.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Expire non-current versions after 30 days.
resource "aws_s3_bucket_lifecycle_configuration" "default_origin" {
  bucket = aws_s3_bucket.default_origin.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# Bucket policy — grants CloudFront OAC read access only.
resource "aws_s3_bucket_policy" "default_origin" {
  bucket = aws_s3_bucket.default_origin.id
  policy = data.aws_iam_policy_document.default_origin_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.default_origin]
}

# Holding page — returned for all unmatched paths via CloudFront custom error response.
# Source file lives at terraform/static/index.html relative to this module root.
resource "aws_s3_object" "default_origin_index" {
  bucket       = aws_s3_bucket.default_origin.id
  key          = "index.html"
  source       = "${path.module}/static/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/static/index.html")

  tags = {
    Name = "${var.service}-default-origin-index"
  }
}