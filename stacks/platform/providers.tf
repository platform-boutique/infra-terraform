provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

# Helm talks to the cluster this same configuration creates. Its settings are known only once the cluster exists, which is
# fine: it is used by modules that depend on it. Authentication is the caller's own AWS identity (aws eks get-token).
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

# The Kubernetes provider is used for exactly one thing: removing the default-class annotation from EKS's own gp2 StorageClass
# (modules/storage-class), which Helm cannot do because EKS, not a Helm release, owns that object. Everything else goes through Helm
# (the one provider that can plan before the cluster exists). Same cluster, same authentication.
provider "kubernetes" {
  host                   = module.eks_cluster.endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.certificate_authority_data)

  exec {
    api_version = local.exec_auth.api_version
    command     = local.exec_auth.command
    args        = local.exec_auth.args
  }
}
