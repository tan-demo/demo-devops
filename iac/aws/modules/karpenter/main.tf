provider "helm" {
  kubernetes = {
    host                   = var.eks_endpoint
    cluster_ca_certificate = base64decode(var.cluster_ca_certificate)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
    }
  }
}

provider "kubectl" {
  host                   = var.eks_endpoint
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
  }
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.24.0"

  cluster_name = var.cluster_name
  namespace    = var.namespace

  create_pod_identity_association = var.create_pod_identity_association
  enable_spot_termination         = var.enable_spot_termination

  node_iam_role_use_name_prefix   = var.node_iam_role_use_name_prefix
  node_iam_role_attach_cni_policy = var.node_iam_role_attach_cni_policy

  tags = var.tags
}

resource "helm_release" "karpenter" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = true

  repository = var.chart_repository
  chart      = var.chart_name
  version    = var.karpenter_version

  values = concat([yamlencode({
    replicas = var.karpenter_replicas
    settings = {
      clusterName       = var.cluster_name
      interruptionQueue = module.karpenter.queue_name
    }
    serviceAccount = {
      name = module.karpenter.service_account
    }
  })], var.values)
}

resource "kubectl_manifest" "node_class" {
  for_each = var.node_classes

  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = each.key
    }
    spec = {
      role             = module.karpenter.node_iam_role_name
      amiSelectorTerms = [{ alias = each.value.ami_alias }]
      subnetSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = var.cluster_name }
      }]
      securityGroupSelectorTerms = [{
        tags = { "karpenter.sh/discovery" = var.cluster_name }
      }]
      blockDeviceMappings = [{
        deviceName = each.value.volume_device
        ebs = {
          volumeSize = each.value.volume_size
          volumeType = each.value.volume_type
          encrypted  = each.value.volume_encrypted
        }
      }]
      tags = merge(var.tags, each.value.tags)
    }
  })

  depends_on = [helm_release.karpenter]
}

resource "kubectl_manifest" "node_pool" {
  for_each = { for name, pool in var.node_pools : name => pool if pool.enabled }

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = each.key
    }
    spec = {
      weight = each.value.weight
      template = {
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = each.value.node_class
          }
          taints      = each.value.taints
          expireAfter = var.expire_after
          requirements = concat(
            [
              { key = "karpenter.sh/capacity-type", operator = "In", values = [each.value.capacity_type] },
              { key = "kubernetes.io/arch", operator = "In", values = [each.value.arch] },
            ],
            length(each.value.instance_cpu) > 0 ? [{ key = "karpenter.k8s.aws/instance-cpu", operator = "In", values = each.value.instance_cpu }] : [],
            length(each.value.instance_categories) > 0 ? [{ key = "karpenter.k8s.aws/instance-category", operator = "In", values = each.value.instance_categories }] : [],
            length(each.value.instance_families) > 0 ? [{ key = "karpenter.k8s.aws/instance-family", operator = "In", values = each.value.instance_families }] : [],
          )
        }
      }
      limits = each.value.limits
      disruption = {
        consolidationPolicy = var.consolidation_policy
        consolidateAfter    = var.consolidate_after
        budgets             = var.disruption_budgets
      }
    }
  })

  depends_on = [kubectl_manifest.node_class]
}
