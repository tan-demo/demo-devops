include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_name                       = "demo-dev"
    cluster_endpoint                   = "https://mock.eks.amazonaws.com"
    cluster_certificate_authority_data = "TU9DSw=="
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "output"]
}

terraform {
  source = "../../../modules/karpenter"
}

inputs = {
  cluster_name           = dependency.eks.outputs.cluster_name
  eks_endpoint           = dependency.eks.outputs.cluster_endpoint
  cluster_ca_certificate = dependency.eks.outputs.cluster_certificate_authority_data
  aws_region             = include.root.locals.region

  karpenter_version  = "1.13.0"
  karpenter_replicas = 2

  consolidate_after = "10m"
  expire_after      = "Never"

  node_classes = {
    gpu = {
      ami_alias   = "bottlerocket@v1.62.0"
      volume_size = "100Gi"
    }
  }

  node_pools = {
    gpu-spot = {
      node_class        = "gpu"
      capacity_type     = "spot"
      instance_families = ["g5", "g4dn"]
      weight            = 100
      taints            = [{ key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }]
      limits            = { "nvidia.com/gpu" = "16" }
    }
    gpu-ondemand = {
      node_class        = "gpu"
      capacity_type     = "on-demand"
      instance_families = ["g5", "g4dn"]
      weight            = 10
      taints            = [{ key = "nvidia.com/gpu", value = "true", effect = "NoSchedule" }]
      limits            = { "nvidia.com/gpu" = "8" }
    }
  }

  tags = merge(include.root.locals.tags, {
    "karpenter.sh/discovery" = include.root.locals.cluster_name
  })
}
