provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "cloudflare_dns_record" "quote_api" {
  zone_id = var.zone_id
  name    = "${var.subdomain}.${var.domain}"
  type    = "A"
  content = var.origin_ip
  ttl     = 1
  proxied = var.proxied
}

resource "cloudflare_ruleset" "cache" {
  zone_id = var.zone_id
  name    = "${var.subdomain} cache policy"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      description = "Bypass cache for the API"
      expression  = "starts_with(http.request.uri.path, \"${var.cache_bypass_path_prefix}\")"
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
          default = var.static_edge_ttl
        }
        browser_ttl = {
          mode    = "override_origin"
          default = var.static_browser_ttl
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
  content = "${var.subdomain}.${var.domain}"
  ttl     = 1
  proxied = var.proxied
}
