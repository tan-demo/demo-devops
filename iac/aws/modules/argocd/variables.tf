variable "eks_endpoint" {
  type        = string
  description = "EKS API server endpoint the Helm provider talks to."
}

variable "cluster_ca_certificate" {
  type        = string
  description = "Base64-encoded cluster CA certificate (from the eks module)."
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name, used for the aws eks get-token auth exec."
}

variable "aws_region" {
  type = string
}

variable "release_name" {
  type    = string
  default = "argo-cd"
}

variable "namespace" {
  type    = string
  default = "argocd"
}

variable "create_namespace" {
  type    = bool
  default = true
}

variable "chart_repository" {
  type    = string
  default = "https://argoproj.github.io/argo-helm"
}

variable "chart_version" {
  type        = string
  description = "argo-cd Helm chart version."
  default     = "10.0.0"
}

variable "max_history" {
  type        = number
  description = "Max number of Helm release revisions kept in history."
  default     = 3
}

variable "values" {
  type        = list(string)
  description = "Raw YAML value documents passed to the Helm release (e.g. file(\"values.yaml\"))."
  default     = []
}

variable "set_values" {
  type        = map(string)
  description = "Individual Helm --set overrides."
  default     = {}
}
