variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token. Inject via TF_VAR_cloudflare_api_token, never commit it."
  sensitive   = true
  default     = null
}

variable "zone_id" {
  type = string
}

variable "domain" {
  type    = string
  default = "example.com"
}

variable "subdomain" {
  type    = string
  default = "quote-api"
}

variable "origin_ip" {
  type    = string
  default = "192.0.2.1"
}

variable "proxied" {
  type        = bool
  description = "Route the record through Cloudflare's proxy (orange cloud)."
  default     = true
}

variable "adopted_record_id" {
  type        = string
  description = "ID of a pre-existing record to adopt into Terraform via an import block."
  default     = ""
}

variable "cache_bypass_path_prefix" {
  type        = string
  description = "URI prefix that must always bypass the edge cache (the dynamic API)."
  default     = "/api/"
}

variable "static_edge_ttl" {
  type    = number
  default = 2592000
}

variable "static_browser_ttl" {
  type    = number
  default = 86400
}
