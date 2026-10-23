# The EKS control plane, and nothing that needs nodes.
#
# What is deliberately NOT here:
#   - the AWS VPC CNI, kube-proxy and CoreDNS: the community module sets bootstrap_self_managed_addons = false. Cilium replaces the
#     first two (modules/cilium); CoreDNS and the EBS CSI driver are EKS add-ons that need nodes, so they are in modules/eks-nodes.
#   - node groups: a managed node group only becomes ACTIVE when its nodes are Ready, and nodes are not Ready until a CNI runs.
#     The order is therefore cluster -> Cilium -> nodes, which needs three modules, not one.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0"

  name               = var.name
  kubernetes_version = var.kubernetes_version

  # Stay on standard support: EKS moves a cluster into paid extended support when its version leaves standard support.
  upgrade_policy = {
    support_type = "STANDARD"
  }

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  endpoint_private_access      = true
  endpoint_public_access       = true
  endpoint_public_access_cidrs = var.public_access_cidrs

  service_ipv4_cidr = var.service_cidr

  # Access through EKS access entries (no aws-auth ConfigMap), all of them explicit. Whoever creates the cluster gets nothing extra, so the
  # result is the same from a laptop and from the pipeline (the creator's own entry would clash with the same principal listed below).
  authentication_mode                      = "API"
  enable_cluster_creator_admin_permissions = false
  access_entries = merge(
    {
      for label, arn in var.admin_principal_arns : label => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
    {
      for label, arn in var.viewer_principal_arns : label => {
        principal_arn = arn
        policy_associations = {
          view = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminViewPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
  )

  # IAM roles for service accounts (the EBS CSI driver uses one).
  enable_irsa = true

  # Kubernetes Secrets are encrypted with a customer-managed key; a short deletion window keeps destroy/recreate cycles cheap.
  create_kms_key                  = true
  kms_key_deletion_window_in_days = 7

  enabled_log_types                      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  # No add-ons here (see the header) and no node groups.
  addons = {}

  # Cilium's overlay: VXLAN between the nodes (UDP 8472), WireGuard (UDP 51871) and ICMP for its health checks. The module's
  # recommended rules already allow the TCP ports (Cilium health, Hubble peer 4244, SPIRE/authentication 4250, Envoy) between nodes
  # (ephemeral range 1025-65535) and from the control plane to the nodes. UDP is not covered by them, hence the rules below.
  node_security_group_additional_rules = {
    ingress_cilium_vxlan = {
      description = "Cilium VXLAN overlay between nodes"
      type        = "ingress"
      protocol    = "udp"
      from_port   = 8472
      to_port     = 8472
      self        = true
    }
    # Cilium's WireGuard encryption (modules/cilium, encryption_enabled): each node sends UDP to port 51871 of the others. The
    # rule is always present (open only to the nodes themselves, so it costs nothing when encryption is off).
    ingress_cilium_wireguard = {
      description = "Cilium WireGuard encryption between nodes"
      type        = "ingress"
      protocol    = "udp"
      from_port   = 51871
      to_port     = 51871
      self        = true
    }
    ingress_cilium_icmp = {
      description = "Cilium health checks (ICMP) between nodes"
      type        = "ingress"
      protocol    = "icmp"
      from_port   = -1
      to_port     = -1
      self        = true
    }
  }

  tags = var.tags
}
