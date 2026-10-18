output "vpc_id" {
  description = "ID of the VPC."
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR of the VPC."
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnets (load balancer), one per availability zone."
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnets (nodes), one per availability zone."
  value       = module.vpc.private_subnets
}

output "nat_public_ips" {
  description = "Public addresses of the NAT gateways: everything in the private subnets reaches the internet from these."
  value       = module.vpc.nat_public_ips
}
