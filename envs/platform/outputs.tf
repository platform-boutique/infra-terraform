output "alb_dns_name" {
  description = "Address of the platform: the DNS name AWS gave the ALB."
  value       = module.alb.dns_name
}

output "alb_url" {
  description = "The same as a URL."
  value       = "http://${module.alb.dns_name}"
}

output "gateway_port" {
  description = "Port the Gateway listeners must use (hostNetwork); the ALB forwards to it."
  value       = var.gateway_port
}

output "cluster_name" {
  description = "Cluster name."
  value       = module.eks_cluster.name
}

output "kubeconfig_command" {
  description = "Writes the cluster into your kubeconfig."
  value       = "aws eks update-kubeconfig --name ${module.eks_cluster.name} --region ${var.region}"
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "nat_public_ips" {
  description = "Addresses the private subnets reach the internet from (for allow-lists elsewhere)."
  value       = module.network.nat_public_ips
}

output "external_secrets_role_arn" {
  description = "IAM role for the External Secrets Operator's service account (annotation eks.amazonaws.com/role-arn)."
  value       = module.secrets_access.role_arn
}

output "secrets_parameter_prefix" {
  description = "Parameter Store path the External Secrets Operator may read."
  value       = module.secrets_access.parameter_prefix
}
