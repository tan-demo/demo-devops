include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/cloudflare"
}

inputs = {
  zone_id           = include.root.locals.cloudflare.zone_id
  domain            = include.root.locals.cloudflare.domain
  origin_ip         = include.root.locals.cloudflare.origin_ip
  adopted_record_id = include.root.locals.cloudflare.adopted_record_id
}
