locals {
  tags = {
    Project   = "platform-demo"
    ManagedBy = "terraform"
    Stack     = "platform"
  }
}

module "network" {
  source = "../../modules/network"

  name = var.name
  cidr = var.vpc_cidr
  azs  = var.azs
}

# 1. The control plane, with no add-ons and no nodes.
module "eks_cluster" {
  source = "../../modules/eks-cluster"

  name                 = var.name
  kubernetes_version   = var.kubernetes_version
  vpc_id               = module.network.vpc_id
  subnet_ids           = module.network.private_subnet_ids
  public_access_cidrs  = var.api_allowed_cidrs
  admin_principal_arns = var.admin_principal_arns
}

# 2. The CNI. Nodes cannot become Ready without it, so it comes before them. depends_on waits for the whole cluster module, which
#    includes the access entry that lets this run's identity talk to the API.
module "cilium" {
  source = "../../modules/cilium"

  api_server_host = module.eks_cluster.endpoint_host

  depends_on = [module.eks_cluster]
}

# 3. The nodes, and the add-ons that need them (CoreDNS, EBS CSI).
module "eks_nodes" {
  source = "../../modules/eks-nodes"

  cluster_name                       = module.eks_cluster.name
  cluster_endpoint                   = module.eks_cluster.endpoint
  cluster_certificate_authority_data = module.eks_cluster.certificate_authority_data
  cluster_service_cidr               = module.eks_cluster.service_cidr
  kubernetes_version                 = module.eks_cluster.kubernetes_version
  node_security_group_id             = module.eks_cluster.node_security_group_id
  oidc_provider_arn                  = module.eks_cluster.oidc_provider_arn
  oidc_provider                      = module.eks_cluster.oidc_provider

  subnet_ids     = module.network.private_subnet_ids
  instance_types = var.node_instance_types
  capacity_type  = "SPOT"
  desired_size   = var.node_count
  min_size       = var.node_count
  max_size       = var.node_count + 2
  disk_size_gib  = var.node_disk_size_gib

  depends_on = [module.cilium]
}

# The domain's hosted zone (created by AWS when the domain was registered) and its certificate (envs/foundation): looked up, never created,
# so a destroy of the platform cannot remove them.
data "aws_route53_zone" "this" {
  name         = var.domain_name
  private_zone = false
}

data "aws_acm_certificate" "this" {
  domain      = var.domain_name
  statuses    = ["ISSUED"]
  most_recent = true
}

# 4. The front door: an ALB in the public subnets, serving HTTPS with that certificate and forwarding to the Gateway's port on the nodes.
module "alb" {
  source = "../../modules/alb"

  name                    = var.name
  certificate_arn         = data.aws_acm_certificate.this.arn
  vpc_id                  = module.network.vpc_id
  subnet_ids              = module.network.public_subnet_ids
  allowed_cidrs           = var.alb_allowed_cidrs
  gateway_port            = var.gateway_port
  node_security_group_id  = module.eks_cluster.node_security_group_id
  autoscaling_group_names = module.eks_nodes.autoscaling_group_names
}

# 6. Read access to the platform's secrets in Parameter Store for the External Secrets Operator (installed later through GitOps).
module "secrets_access" {
  source = "../../modules/secrets-access"

  name              = module.eks_cluster.name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_provider     = module.eks_cluster.oidc_provider
  parameter_prefix  = var.secrets_parameter_prefix
}

# 5. The host names of the platform's UIs, all pointing at the ALB.
module "dns" {
  source = "../../modules/dns"

  zone_id      = data.aws_route53_zone.this.zone_id
  domain_name  = var.domain_name
  hostnames    = var.hostnames
  alb_dns_name = module.alb.dns_name
  alb_zone_id  = module.alb.zone_id
}
