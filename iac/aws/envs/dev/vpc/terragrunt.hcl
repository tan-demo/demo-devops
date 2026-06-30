include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "../../../modules/vpc"
}

inputs = {
  name = "${include.root.locals.cluster_name}-vpc"
  cidr = include.root.locals.vpc_cidr
  azs  = include.root.locals.azs

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_database_subnets      = true
  create_database_subnet_group = true

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = include.root.locals.cluster_name
  }
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  tags = merge(include.root.locals.tags, {
    "karpenter.sh/discovery" = include.root.locals.cluster_name
  })
}
