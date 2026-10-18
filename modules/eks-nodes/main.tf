# The worker nodes and the add-ons that need them. This module is applied after Cilium (see modules/eks-cluster).

data "aws_partition" "current" {}

# --- Managed node group ------------------------------------------------------------------------------------------------------
module "node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "21.29.0"

  name               = "workers"
  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version

  cluster_endpoint     = var.cluster_endpoint
  cluster_auth_base64  = var.cluster_certificate_authority_data
  cluster_service_cidr = var.cluster_service_cidr

  # One group over all private subnets = one Auto Scaling group across the zones. The ALB module attaches its target group to it.
  subnet_ids = var.subnet_ids

  # The nodes use the cluster's node security group; the group makes none of its own.
  create_security_group  = false
  vpc_security_group_ids = [var.node_security_group_id]

  ami_type       = "AL2023_x86_64_STANDARD"
  capacity_type  = var.capacity_type
  instance_types = var.instance_types

  min_size     = var.min_size
  max_size     = var.max_size
  desired_size = var.desired_size

  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = var.disk_size_gib
        volume_type           = "gp3"
        encrypted             = true
        delete_on_termination = true
      }
    }
  }

  update_config = {
    max_unavailable = 1
  }

  # No VPC CNI on this cluster, so no CNI policy. Session Manager gives a shell on a node without SSH keys or open ports.
  iam_role_attach_cni_policy = false
  iam_role_additional_policies = {
    ssm = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = var.tags
}

# With access entries (no aws-auth ConfigMap) the node role has to be registered explicitly, or its nodes cannot join.
resource "aws_eks_access_entry" "nodes" {
  cluster_name  = var.cluster_name
  principal_arn = module.node_group.iam_role_arn
  type          = "EC2_LINUX"
}

# --- Add-ons that need nodes ------------------------------------------------------------------------------------------------
resource "aws_eks_addon" "coredns" {
  cluster_name = var.cluster_name
  addon_name   = "coredns"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.node_group]
}

# The EBS CSI driver provides PersistentVolumes (Postgres, Mimir, Loki, Grafana ...). Its controller assumes this role through the
# cluster's OIDC provider (IRSA).
data "aws_iam_policy_document" "ebs_csi_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  # Volumes the driver creates for PersistentVolumeClaims are not Terraform resources. The driver tags every one of them with
  # ebs.csi.aws.com/cluster=true, which is how what a destroyed cluster leaves behind can be found (docs/operations.md).

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [module.node_group, aws_iam_role_policy_attachment.ebs_csi]
}
