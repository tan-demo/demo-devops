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
  source = "../../../modules/argocd"
}

inputs = {
  eks_endpoint           = dependency.eks.outputs.cluster_endpoint
  cluster_ca_certificate = dependency.eks.outputs.cluster_certificate_authority_data
  cluster_name           = dependency.eks.outputs.cluster_name
  aws_region             = include.root.locals.region

  chart_version = "10.0.0"
  max_history   = 3
  values        = [file("${get_terragrunt_dir()}/values.yaml")]
}
