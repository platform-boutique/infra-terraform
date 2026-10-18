output "name" {
  description = "Cluster name."
  value       = module.eks.cluster_name
}

output "endpoint" {
  description = "API server endpoint (https://...)."
  value       = module.eks.cluster_endpoint
}

output "endpoint_host" {
  description = "API server host name without the scheme: what Cilium needs, because without kube-proxy it cannot use the kubernetes Service."
  value       = replace(module.eks.cluster_endpoint, "https://", "")
}

output "certificate_authority_data" {
  description = "Base64 CA of the API server."
  value       = module.eks.cluster_certificate_authority_data
}

output "service_cidr" {
  description = "CIDR of Kubernetes Services."
  value       = module.eks.cluster_service_cidr
}

output "kubernetes_version" {
  description = "Kubernetes version of the control plane."
  value       = var.kubernetes_version
}

output "node_security_group_id" {
  description = "Security group of the worker nodes."
  value       = module.eks.node_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN of the cluster's OIDC provider (IAM roles for service accounts)."
  value       = module.eks.oidc_provider_arn
}

output "oidc_provider" {
  description = "Issuer of the OIDC provider without the scheme."
  value       = module.eks.oidc_provider
}
