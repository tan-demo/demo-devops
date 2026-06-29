locals {
  private_subnets  = [for i in range(length(var.azs)) : cidrsubnet(var.cidr, var.subnet_newbits, i)]
  public_subnets   = [for i in range(length(var.azs)) : cidrsubnet(var.cidr, var.subnet_newbits, i + var.public_subnet_offset)]
  database_subnets = var.enable_database_subnets ? [for i in range(length(var.azs)) : cidrsubnet(var.cidr, var.subnet_newbits, i + var.database_subnet_offset)] : []
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.6.1"

  name = var.name
  cidr = var.cidr

  azs             = var.azs
  private_subnets = local.private_subnets
  public_subnets  = local.public_subnets

  enable_nat_gateway     = var.enable_nat_gateway
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = var.one_nat_gateway_per_az

  database_subnets                   = local.database_subnets
  create_database_subnet_group       = var.enable_database_subnets && var.create_database_subnet_group
  create_database_subnet_route_table = var.enable_database_subnets && var.create_database_subnet_route_table
  database_subnet_tags               = var.database_subnet_tags

  enable_dns_hostnames    = var.enable_dns_hostnames
  enable_dns_support      = var.enable_dns_support
  map_public_ip_on_launch = var.map_public_ip_on_launch
  create_igw              = var.create_igw
  instance_tenancy        = var.instance_tenancy

  private_subnet_tags = var.private_subnet_tags
  public_subnet_tags  = var.public_subnet_tags

  tags = var.tags
}
