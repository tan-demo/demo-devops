output "record_id" {
  value = cloudflare_dns_record.quote_api.id
}

output "ruleset_id" {
  value = cloudflare_ruleset.cache.id
}
