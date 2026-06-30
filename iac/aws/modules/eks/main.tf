data "aws_caller_identity" "current" {}

locals {
  role_users = {
    "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" = var.cluster_admin_users
    "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"         = var.cluster_developer_users
    "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"         = var.cluster_viewer_users
  }

  role_access_entries = merge([
    for policy_arn, users in local.role_users : {
      for u in users : u => {
        principal_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${u}"
        policy_associations = {
          this = {
            policy_arn   = policy_arn
            access_scope = { type = "cluster" }
          }
        }
      }
    }
  ]...)

  eks_managed_node_groups = {
    for name, ng in var.node_groups : name => merge(
      {
        instance_types = ng.instance_types
        ami_type       = ng.ami_type
        capacity_type  = ng.capacity_type
        min_size       = ng.min_size
        max_size       = ng.max_size
        desired_size   = ng.desired_size
        labels         = ng.labels
        taints         = ng.taints

        block_device_mappings = {
          root = {
            device_name = startswith(ng.ami_type, "BOTTLEROCKET") ? "/dev/xvdb" : "/dev/xvda"
            ebs = {
              volume_size           = ng.disk_size
              volume_type           = ng.disk_type
              encrypted             = true
              delete_on_termination = true
            }
          }
        }
      },
      ng.user_data == "" ? {} : (
        startswith(ng.ami_type, "BOTTLEROCKET")
        ? { bootstrap_extra_args = ng.user_data }
        : { pre_bootstrap_user_data = ng.user_data }
      )
    )
  }

  addons = {
    coredns = {
      addon_version               = var.addon_versions["coredns"]
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    kube-proxy = {
      addon_version               = var.addon_versions["kube-proxy"]
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    eks-pod-identity-agent = {
      addon_version               = var.addon_versions["eks-pod-identity-agent"]
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    vpc-cni = {
      addon_version               = var.addon_versions["vpc-cni"]
      service_account_role_arn    = module.cni_irsa.arn
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
    aws-ebs-csi-driver = {
      addon_version               = var.addon_versions["aws-ebs-csi-driver"]
      service_account_role_arn    = module.ebs_csi_irsa.arn
      resolve_conflicts_on_create = "OVERWRITE"
      resolve_conflicts_on_update = "OVERWRITE"
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.subnet_ids
  control_plane_subnet_ids = length(var.control_plane_subnet_ids) > 0 ? var.control_plane_subnet_ids : var.subnet_ids

  endpoint_public_access       = var.endpoint_public_access
  endpoint_private_access      = var.endpoint_private_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs

  enable_irsa = var.enable_irsa

  enable_cluster_creator_admin_permissions = var.enable_cluster_creator_admin_permissions
  access_entries                           = merge(local.role_access_entries, var.access_entries)

  create_kms_key          = var.create_kms_key
  enable_kms_key_rotation = var.enable_kms_key_rotation
  kms_key_administrators  = var.kms_key_administrators

  eks_managed_node_groups = local.eks_managed_node_groups
  addons                  = local.addons

  node_security_group_tags = var.node_security_group_tags

  tags = var.tags
}

module "cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.6.1"

  name = "${var.cluster_name}-vpc-cni"

  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    this = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = var.tags
}

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "6.6.1"

  name = "${var.cluster_name}-ebs-csi"

  attach_ebs_csi_policy = true

  oidc_providers = {
    this = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = var.tags
}
