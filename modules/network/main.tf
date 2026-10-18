# VPC with one public and one private /24 subnet per availability zone and one NAT gateway per zone.
#
#   public  subnets  10.0.0.0/24, 10.0.1.0/24, ...    only the load balancer lives here (and the NAT gateways)
#   private subnets  10.0.10.0/24, 10.0.11.0/24, ...  nodes; egress through the NAT gateway of the same zone
#
# Pods do not use VPC addresses (Cilium runs as an overlay), so /24 subnets only have to hold nodes.

locals {
  subnet_newbits = 24 - tonumber(split("/", var.cidr)[1])

  public_subnets  = [for i, _ in var.azs : cidrsubnet(var.cidr, local.subnet_newbits, i)]
  private_subnets = [for i, _ in var.azs : cidrsubnet(var.cidr, local.subnet_newbits, 10 + i)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.7.3"

  name = var.name
  cidr = var.cidr
  azs  = var.azs

  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_dns_hostnames = true
  enable_dns_support   = true

  enable_nat_gateway     = true
  single_nat_gateway     = false
  one_nat_gateway_per_az = true

  # The default security group stays but allows nothing: nothing may rely on it by accident.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  tags = var.tags
}
