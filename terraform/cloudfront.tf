# CloudFront reverse proxy — routes labs.alamy.com/{app}/* to external origins.
# A CloudFront Function strips the /{app} prefix before forwarding:
#   /myapp/eu/login  →  /eu/login
#
# To add an application: add one entry to labs_applications in the tfvars.

# Strips the leading /{app} segment on viewer-request.
resource "aws_cloudfront_function" "path_rewrite" {
  name    = "${var.service}-path-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Strips /{app} prefix. /app/a/b → /a/b"
  publish = true

  code = <<-EOF
    function handler(event) {
      var request = event.request;
      var stripped = request.uri.replace(/^\/[^\/]*/, '');
      request.uri = stripped.length > 0 ? stripped : '/';
      return request;
    }
  EOF
}

# Forwards cookies, query strings, and CORS headers to origins.
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
        "CloudFront-Viewer-Address"
      ]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

# Caching disabled — POC origins remain authoritative.
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

resource "aws_cloudfront_distribution" "labs" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Alamy Labs reverse proxy (${terraform.workspace})"
  price_class         = var.cloudfront_price_class
  aliases             = [local.labs_fqdn]
  http_version        = "http2and3"
  wait_for_deployment = true

  logging_config {
    bucket          = aws_s3_bucket.cloudfront_logs.bucket_regional_domain_name
    prefix          = "${var.service}/${terraform.workspace}/"
    include_cookies = false
  }

  # Fallback origin for unmatched paths.
  origin {
    domain_name = var.default_origin_domain
    origin_id           = "default-origin"
    connection_attempts = 3
    connection_timeout  = 10

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_keepalive_timeout = 60
      origin_read_timeout      = 60
    }

    custom_header {
      name  = "X-Forwarded-Host"
      value = local.labs_fqdn
    }
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

      # Lets origins reconstruct the public labs.alamy.com URL if needed.
      custom_header {
        name  = "X-Forwarded-Host"
        value = local.labs_fqdn
      }
    }
  }

  # Default behaviour — catch-all for unmatched paths.
  default_cache_behavior {
    target_origin_id       = "default-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = aws_cloudfront_cache_policy.labs_nocache.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.labs_external.id
  }

  # Per-application behaviours.
  # /{app}* matches both the bare root (/app) and sub-paths (/app/page).
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

      function_association {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.path_rewrite.arn
      }
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

  tags = merge(var.tags, {
    Name = "${var.service}-distribution"
  })
}
