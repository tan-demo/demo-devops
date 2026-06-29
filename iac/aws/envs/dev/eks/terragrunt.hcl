include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id          = "vpc-00000000000000000"
    private_subnets = ["subnet-00000000000000001", "subnet-00000000000000002", "subnet-00000000000000003"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init", "output"]
}

terraform {
  source = "../../../modules/eks"
}

inputs = {
  cluster_name       = include.root.locals.cluster_name
  kubernetes_version = include.root.locals.kubernetes_version

  vpc_id     = dependency.vpc.outputs.vpc_id
  subnet_ids = dependency.vpc.outputs.private_subnets

  endpoint_public_access       = true
  endpoint_private_access      = true
  endpoint_public_access_cidrs = ["0.0.0.0/0"]

  enable_cluster_creator_admin_permissions = true
  create_kms_key                           = true
  enable_kms_key_rotation                  = true

  cluster_admin_users     = ["tan.phan", "abc.nguyen"]
  cluster_developer_users = ["xyz.nguyen"]
  cluster_viewer_users    = []

  node_groups = {
    amd = {
      instance_types = ["m6i.large"]
      ami_type       = "AL2023_x86_64_STANDARD"
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      disk_size      = 50
      user_data      = ""
    }
    arm = {
      instance_types = ["m7g.large"]
      ami_type       = "BOTTLEROCKET_ARM_64"
      min_size       = 2
      max_size       = 3
      desired_size   = 2
      disk_size      = 50
      user_data      = ""
    }
  }

  addon_versions = {
    vpc-cni                = "v1.21.2-eksbuild.2"
    coredns                = "v1.14.2-eksbuild.4"
    kube-proxy             = "v1.36.0-eksbuild.7"
    eks-pod-identity-agent = "v1.3.10-eksbuild.3"
    aws-ebs-csi-driver     = "v1.62.0-eksbuild.1"
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = include.root.locals.cluster_name
  }
  tags = merge(include.root.locals.tags, {
    "karpenter.sh/discovery" = include.root.locals.cluster_name
  })
}
