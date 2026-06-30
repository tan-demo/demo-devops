variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster."
}

variable "kubernetes_version" {
  type    = string
  default = "1.33"
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type        = list(string)
  description = "Subnets the worker nodes run in (usually the private subnets)."
}

variable "control_plane_subnet_ids" {
  type        = list(string)
  description = "Subnets for the EKS control-plane ENIs. Falls back to subnet_ids when empty."
  default     = []
}

variable "endpoint_public_access" {
  type    = bool
  default = true
}

variable "endpoint_private_access" {
  type    = bool
  default = true
}

variable "endpoint_public_access_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0"]
}

variable "enable_irsa" {
  type        = bool
  description = "Create the OIDC provider so IRSA roles can be assumed."
  default     = true
}

variable "enable_cluster_creator_admin_permissions" {
  type        = bool
  description = "Grant the identity that creates the cluster full admin via an access entry."
  default     = true
}

variable "cluster_admin_users" {
  type        = list(string)
  description = "IAM usernames (in this account) granted cluster-admin via AmazonEKSClusterAdminPolicy."
  default     = []
}

variable "cluster_developer_users" {
  type        = list(string)
  description = "IAM usernames granted edit access via AmazonEKSEditPolicy."
  default     = []
}

variable "cluster_viewer_users" {
  type        = list(string)
  description = "IAM usernames granted read-only access via AmazonEKSViewPolicy."
  default     = []
}

variable "access_entries" {
  type        = any
  description = "Raw EKS access entries for anything else (roles, SSO, cross-account), merged on top."
  default     = {}
}

variable "create_kms_key" {
  type        = bool
  description = "Create a dedicated KMS key for cluster secrets envelope encryption."
  default     = true
}

variable "enable_kms_key_rotation" {
  type    = bool
  default = true
}

variable "kms_key_administrators" {
  type        = list(string)
  description = "IAM principal ARNs that administer the cluster encryption KMS key."
  default     = []
}

variable "node_groups" {
  type = map(object({
    instance_types = optional(list(string), ["m6i.large"])
    ami_type       = optional(string, "AL2023_x86_64_STANDARD")
    capacity_type  = optional(string, "ON_DEMAND")
    min_size       = optional(number, 2)
    max_size       = optional(number, 3)
    desired_size   = optional(number, 2)
    disk_size      = optional(number, 50)
    disk_type      = optional(string, "gp3")
    user_data      = optional(string, "")
    labels         = optional(map(string), {})
    taints         = optional(any, {})
  }))
  description = "Managed node groups keyed by name; the module creates one group per key. Pick the OS/arch per group via ami_type (e.g. AL2023_x86_64_STANDARD, AL2023_ARM_64, BOTTLEROCKET_x86_64, BOTTLEROCKET_ARM_64)."
  default = {
    system = {
      instance_types = ["m6i.large"]
      desired_size   = 2
    }
  }
}

variable "addon_versions" {
  type        = map(string)
  description = "Pinned add-on version per name, so a version is not silently bumped on every apply. Get exact strings from: aws eks describe-addon-versions --kubernetes-version <ver> --addon-name <name>."
  default = {
    vpc-cni                = "v1.21.2-eksbuild.2"
    coredns                = "v1.14.2-eksbuild.4"
    kube-proxy             = "v1.36.0-eksbuild.7"
    eks-pod-identity-agent = "v1.3.10-eksbuild.3"
    aws-ebs-csi-driver     = "v1.62.0-eksbuild.1"
  }
}

variable "node_security_group_tags" {
  type        = map(string)
  description = "Extra tags on the node security group (e.g. Karpenter discovery)."
  default     = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}
