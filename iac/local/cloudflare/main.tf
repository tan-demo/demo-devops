provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_dns_record" "quote_api" {
  zone_id = var.zone_id
  name    = "quote-api.${var.domain}"
  type    = "A"
  content = var.origin_ip
  ttl     = 1
  proxied = true
}

resource "cloudflare_ruleset" "cache" {
  zone_id = var.zone_id
  name    = "quote-api cache policy"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      description = "Bypass cache for the API"
      expression  = "starts_with(http.request.uri.path, \"/api/\")"
      action      = "set_cache_settings"
      action_parameters = {
        cache = false
      }
    },
    {
      description = "Cache static assets aggressively"
      expression  = "http.request.uri.path matches \".*\\.(css|js|png|jpg|jpeg|gif|svg|woff2|ico)$\""
      action      = "set_cache_settings"
      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = 2592000
        }
        browser_ttl = {
          mode    = "override_origin"
          default = 86400
        }
      }
    }
  ]
}

import {
  to = cloudflare_dns_record.adopted
  id = "${var.zone_id}/${var.adopted_record_id}"
}

resource "cloudflare_dns_record" "adopted" {
  zone_id = var.zone_id
  name    = "legacy.${var.domain}"
  type    = "CNAME"
  content = "quote-api.${var.domain}"
  ttl     = 1
  proxied = true
}
