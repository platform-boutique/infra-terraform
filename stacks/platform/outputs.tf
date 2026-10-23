output "alb_dns_name" {
  description = "Address of the platform: the DNS name AWS gave the ALB."
  value       = module.alb.dns_name
}

output "alb_url" {
  description = "The ALB's own address (it answers on the host names below; its certificate is for the domain)."
  value       = "https://${module.alb.dns_name}"
}

output "urls" {
  description = "The platform's UIs."
  value       = { for k, v in module.dns.fqdns : k => "https://${v}" }
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

# ==================================================================================================================================
# The database
# ==================================================================================================================================
output "database_host" {
  description = "Host name of Backstage's PostgreSQL database (also in Parameter Store under database_connection_parameter_path)."
  value       = module.database.address
}

output "database_port" {
  description = "Port of the database."
  value       = module.database.port
}

output "database_name" {
  description = "Name of the database."
  value       = module.database.database_name
}

output "database_username" {
  description = "Master user of the database (its password is only in the Secrets Manager secret below)."
  value       = module.database.username
}

output "database_secret_arn" {
  description = "Secrets Manager secret RDS keeps the master password in (JSON keys username and password, rotated every 7 days). The External Secrets role may read it."
  value       = module.database.master_user_secret_arn
}

output "database_connection_parameter_path" {
  description = "Parameter Store path of the non-secret connection details: <path>/host, /port, /database, /username."
  value       = module.database.connection_parameter_path
}
