locals {
  environment        = "dev"
  region             = "ap-southeast-1"
  cluster_name       = "demo-dev"
  kubernetes_version = "1.36"
  vpc_cidr           = "10.100.0.0/16"
  azs                = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]

  tags = {
    Project     = "demo"
    Environment = "dev"
    ManagedBy   = "terragrunt"
  }

  cloudflare = {
    zone_id           = "REPLACE_WITH_ZONE_ID"
    domain            = "example.com"
    origin_ip         = "192.0.2.1"
    adopted_record_id = "REPLACE_WITH_RECORD_ID"
  }
}

generate "backend" {
  path      = "backend.tf"
  if_exists = "overwrite_terragrunt"
  disable   = tobool(get_env("TG_DISABLE_BACKEND", "false"))
  contents  = <<-EOF
    terraform {
      backend "s3" {
        bucket         = "${local.cluster_name}-tfstate"
        key            = "${local.cluster_name}/${path_relative_to_include()}/terraform.tfstate"
        region         = "${local.region}"
        dynamodb_table = "${local.cluster_name}-tflock"
        encrypt        = true
      }
    }
  EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "${local.region}"
    }
  EOF
}
