# Routes labs.alamy.com/{app}/* to external origins, path is forwarded as-is.
# Unmatched paths fall through to the S3 default origin (OAC).

# Forwards cookies, query strings, and CORS headers to external origins.
# Host header excluded — CloudFront sends the origin domain as Host,
# which external platforms (Vercel, Bolt) require for project routing.
resource "aws_cloudfront_origin_request_policy" "labs_external" {
  name    = "${var.service}-external-origin-policy"
  comment = "Forwards cookies, query strings, and CORS headers to external origins."

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = [
        "Origin",
        "Access-Control-Request-Headers",
        "Access-Control-Request-Method",
        "CloudFront-Viewer-Address",
      ]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

# Caching disabled — origins remain authoritative.
resource "aws_cloudfront_cache_policy" "labs_nocache" {
  name        = "${var.service}-no-cache"
  comment     = "TTL=0. Enable per-app once stable."
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }
    headers_config {
      header_behavior = "none"
    }
    query_strings_config {
      query_string_behavior = "none"
    }
    enable_accept_encoding_gzip   = false
    enable_accept_encoding_brotli = false
  }
}

# OAC for the S3 default origin — sigv4 signing, no credentials in URL.
resource "aws_cloudfront_origin_access_control" "default_origin" {
  name                              = "${var.service}-default-origin-oac"
  description                       = "OAC for the S3 default (catch-all) origin."
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "labs" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Alamy Labs reverse proxy (${terraform.workspace})"
  price_class         = var.cloudfront_price_class
  aliases             = [local.labs_fqdn]
  http_version        = "http2and3"
  wait_for_deployment = true

  # Default (catch-all) origin — S3 bucket served via OAC.
  # Returns index.html for unmatched paths via custom error responses below.
  origin {
    domain_name              = aws_s3_bucket.default_origin.bucket_regional_domain_name
    origin_id                = "default-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.default_origin.id
  }

  # S3 returns 403 (not 404) for missing objects when public access is blocked.
  # Both are mapped to index.html so the holding page is always served.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  # One origin per application.
  dynamic "origin" {
    for_each = var.labs_applications

    content {
      domain_name         = origin.value.origin_domain
      origin_id           = "labs-app-${origin.key}"
      connection_attempts = 3
      connection_timeout  = 10

      custom_origin_config {
        http_port                = 80
        https_port               = 443
        origin_protocol_policy   = "https-only"
        origin_ssl_protocols     = ["TLSv1.2"]
        origin_keepalive_timeout = 60
        origin_read_timeout      = 30
      }

      custom_header {
        name  = "X-Forwarded-Host"
        value = local.labs_fqdn
      }
    }
  }

  # Default behaviour — serves index.html from S3 for unmatched paths.
  default_cache_behavior {
    target_origin_id       = "default-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id = aws_cloudfront_cache_policy.labs_nocache.id
  }

  # Per-application behaviours — /{app}* matches root and all sub-paths.
  dynamic "ordered_cache_behavior" {
    for_each = var.labs_applications

    content {
      path_pattern           = "/${ordered_cache_behavior.key}*"
      target_origin_id       = "labs-app-${ordered_cache_behavior.key}"
      viewer_protocol_policy = "redirect-to-https"
      allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true

      cache_policy_id          = aws_cloudfront_cache_policy.labs_nocache.id
      origin_request_policy_id = aws_cloudfront_origin_request_policy.labs_external.id
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.labs.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name = "${var.service}-distribution"
  }
}
