# =============================================================================
# cloudfront.tf — Alamy Labs reverse proxy
#
# Routes labs.alamy.com/{app}/* to external origins (Vercel, Bolt, etc.).
# A CloudFront Function strips the /{app} prefix before forwarding:
#   /myapp/eu/login  →  /eu/login
#
# To add an application: add one entry to labs_applications in the tfvars.
# =============================================================================

resource "aws_cloudfront_function" "path_rewrite" {
  name    = "alamy-labs-path-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "Strips /{app} prefix before forwarding to origin"
  publish = true

  code = <<-EOF
    function handler(event) {
      var request = event.request;
      request.uri = request.uri.replace(/^\/[^\/]+/, '') || '/';
      return request;
    }
  EOF
}

# Forwards cookies, query strings, and CORS headers.
# Host header is intentionally excluded — origins use their own domain as Host.
resource "aws_cloudfront_origin_request_policy" "labs_external" {
  name    = "alamy-labs-external-origin-policy"
  comment = "Forwards cookies, query strings, and CORS headers to external origins"

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
      ]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

# Caching disabled — POC origins remain strictly authoritative.
resource "aws_cloudfront_cache_policy" "labs_nocache" {
  name        = "alamy-labs-no-cache"
  comment     = "No caching for POC applications"
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
  comment             = "Alamy Labs — reverse proxy to external POC origins"
  price_class         = var.cloudfront_price_class
  aliases             = [local.labs_fqdn]
  http_version        = "http2and3"
  wait_for_deployment = false

  # Fallback origin for unmatched paths
  origin {
    domain_name = var.default_origin_domain
    origin_id   = "default-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  dynamic "origin" {
    for_each = var.labs_applications

    content {
      domain_name = origin.value.origin_domain
      origin_id   = "labs-app-${origin.key}"

      custom_origin_config {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  default_cache_behavior {
    target_origin_id       = "default-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = aws_cloudfront_cache_policy.labs_nocache.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.labs_external.id
  }

  dynamic "ordered_cache_behavior" {
    for_each = var.labs_applications

    content {
      path_pattern           = "/${ordered_cache_behavior.key}/*"
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

  # TLS 1.2+ enforced for viewers; TLS 1.3 negotiated automatically where supported
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

  depends_on = [aws_acm_certificate_validation.labs]

  tags = merge(var.tags, {
    Name = "alamy-labs-distribution"
  })
}
