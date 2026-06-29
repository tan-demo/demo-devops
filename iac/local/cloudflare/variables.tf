variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "zone_id" {
  type = string
}

variable "domain" {
  type    = string
  default = "example.com"
}

variable "origin_ip" {
  type    = string
  default = "192.0.2.1"
}

variable "adopted_record_id" {
  type        = string
  description = "ID of a pre-existing, manually-created DNS record to adopt into Terraform"
}
