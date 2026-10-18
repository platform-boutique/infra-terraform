data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  tags = {
    Project   = "platform-demo"
    ManagedBy = "terraform"
    Stack     = "platform"
  }

  iam_arn_base = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}"

  # Who gets into the cluster besides its creator, by a label that names them.
  admin_principal_arns = merge(
    { for n in var.admin_role_names : "role-${n}" => "${local.iam_arn_base}:role/${n}" },
    { for n in var.admin_user_names : "user-${n}" => "${local.iam_arn_base}:user/${n}" },
  )
  viewer_principal_arns = { for n in var.viewer_role_names : "role-${n}" => "${local.iam_arn_base}:role/${n}" }
}

# The three address ranges are carved out by hand, so check them: an overlap would not fail anywhere until pods cannot reach services.
# (Terraform has no function for "do these CIDRs overlap": compare the first and last address of each as numbers.)
locals {
  cidr_ranges = {
    for name, cidr in { vpc = var.vpc_cidr, service = var.service_cidr, pod = var.pod_cidr } : name => {
      first                 = sum([for i, octet in split(".", cidrhost(cidr, 0)) : tonumber(octet) * pow(256, 3 - i)])
      size                  = pow(2, 32 - tonumber(split("/", cidr)[1]))
    }
  }
  cidr_pairs = [["vpc", "service"], ["vpc", "pod"], ["service", "pod"]]
}

check "address_ranges_do_not_overlap" {
  assert {
    condition = alltrue([
      for p in local.cidr_pairs :
      local.cidr_ranges[p[0]].first + local.cidr_ranges[p[0]].size <= local.cidr_ranges[p[1]].first ||
      local.cidr_ranges[p[1]].first + local.cidr_ranges[p[1]].size <= local.cidr_ranges[p[0]].first
    ])
    error_message = "vpc_cidr, service_cidr and pod_cidr must not overlap."
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

  name                  = var.name
  kubernetes_version    = var.kubernetes_version
  vpc_id                = module.network.vpc_id
  subnet_ids            = module.network.private_subnet_ids
  public_access_cidrs   = var.api_allowed_cidrs
  service_cidr          = var.service_cidr
  admin_principal_arns  = local.admin_principal_arns
  viewer_principal_arns = local.viewer_principal_arns
  log_retention_days    = var.log_retention_days
}

# 2. The CNI. Nodes cannot become Ready without it, so it comes before them. depends_on waits for the whole cluster module, which
#    includes the access entries that let this run's identity talk to the API.
module "cilium" {
  source = "../../modules/cilium"

  api_server_host     = module.eks_cluster.endpoint_host
  cilium_version      = var.cilium_version
  gateway_api_version = var.gateway_api_version
  gateway_crds_sha256 = var.gateway_crds_sha256
  pod_cidr            = var.pod_cidr

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
  capacity_type  = var.node_capacity_type
  desired_size   = var.node_count
  min_size       = var.node_count
  max_size       = var.node_count + 2
  disk_size_gib  = var.node_disk_size_gib

  depends_on = [module.cilium]
}

# The domain's hosted zone (created by AWS when the domain was registered) and its certificate (stacks/foundation): looked up, never
# created, so a destroy of the platform cannot remove them. If the certificate is missing, run the Foundation workflow first.
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

# 5. The host names of the platform's UIs, all pointing at the ALB.
module "dns" {
  source = "../../modules/dns"

  zone_id      = data.aws_route53_zone.this.zone_id
  domain_name  = var.domain_name
  hostnames    = var.hostnames
  alb_dns_name = module.alb.dns_name
  alb_zone_id  = module.alb.zone_id
}

# 6. Read access to the platform's secrets in Parameter Store for the External Secrets Operator (installed later through GitOps).
module "secrets_access" {
  source = "../../modules/secrets-access"

  name              = module.eks_cluster.name
  oidc_provider_arn = module.eks_cluster.oidc_provider_arn
  oidc_provider     = module.eks_cluster.oidc_provider
  parameter_prefix  = var.secrets_parameter_prefix
}
