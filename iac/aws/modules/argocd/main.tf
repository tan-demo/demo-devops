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

resource "helm_release" "argocd" {
  name             = var.release_name
  namespace        = var.namespace
  create_namespace = var.create_namespace

  repository  = var.chart_repository
  chart       = "argo-cd"
  version     = var.chart_version
  max_history = var.max_history

  values = var.values

  set = [for k, v in var.set_values : {
    name  = k
    value = v
  }]
}
