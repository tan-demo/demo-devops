variable "cluster_name" {
  type        = string
  description = "EKS cluster Karpenter provisions nodes for."
}

variable "namespace" {
  type    = string
  default = "kube-system"
}

variable "create_pod_identity_association" {
  type    = bool
  default = true
}

variable "enable_spot_termination" {
  type    = bool
  default = true
}

variable "node_iam_role_use_name_prefix" {
  type    = bool
  default = false
}

variable "node_iam_role_attach_cni_policy" {
  type    = bool
  default = true
}

variable "eks_endpoint" {
  type = string
}

variable "cluster_ca_certificate" {
  type        = string
  description = "Base64-encoded cluster CA certificate (from the eks module)."
}

variable "aws_region" {
  type = string
}

variable "karpenter_version" {
  type        = string
  description = "Karpenter Helm chart version."
  default     = "1.13.0"
}

variable "release_name" {
  type    = string
  default = "karpenter"
}

variable "chart_repository" {
  type    = string
  default = "oci://public.ecr.aws/karpenter"
}

variable "chart_name" {
  type    = string
  default = "karpenter"
}

variable "values" {
  type        = list(string)
  description = "Extra raw YAML value documents for the Karpenter Helm release."
  default     = []
}

variable "node_classes" {
  type = map(object({
    ami_alias        = optional(string, "bottlerocket@latest")
    volume_device    = optional(string, "/dev/xvdb")
    volume_size      = optional(string, "50Gi")
    volume_type      = optional(string, "gp3")
    volume_encrypted = optional(bool, true)
    tags             = optional(map(string), {})
  }))
  description = "EC2NodeClasses keyed by name; each NodePool references one by name (e.g. a dedicated 'gpu' class). The bottlerocket/al2023 alias auto-selects the NVIDIA variant for GPU instance types."
  default     = { default = {} }
}

variable "karpenter_replicas" {
  type    = number
  default = 2
}

variable "consolidation_policy" {
  type    = string
  default = "WhenEmpty"
}

variable "consolidate_after" {
  type    = string
  default = "5m"
}

variable "expire_after" {
  type    = string
  default = "720h"
}

variable "disruption_budgets" {
  type    = list(object({ nodes = string }))
  default = [{ nodes = "10%" }]
}

variable "node_pools" {
  type = map(object({
    node_class          = optional(string, "default")
    capacity_type       = string
    instance_categories = optional(list(string), [])
    instance_families   = optional(list(string), [])
    instance_cpu        = optional(list(string), [])
    arch                = optional(string, "amd64")
    weight              = optional(number, 10)
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    limits  = optional(map(string), {})
    enabled = optional(bool, true)
  }))
  description = "Karpenter NodePools keyed by name; the module renders one enabled NodePool per entry against the shared EC2NodeClass."
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
