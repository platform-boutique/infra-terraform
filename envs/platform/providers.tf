provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# Helm and kubectl talk to the cluster this same configuration creates. Their settings are known only once the cluster exists, which is
# fine: they are used by modules that depend on it. Authentication is the caller's own AWS identity (aws eks get-token).
locals {
  exec_auth = {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes = {
    host                   = module.eks_cluster.endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)
    exec                   = local.exec_auth
  }
}

provider "kubectl" {
  host                   = module.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = local.exec_auth.api_version
    command     = local.exec_auth.command
    args        = local.exec_auth.args
  }
}
