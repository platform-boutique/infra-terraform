# The worker nodes and the add-ons that need them. This module is applied after Cilium (see modules/eks-cluster).

data "aws_partition" "current" {}

# --- gVisor on every node ----------------------------------------------------------------------------------------------------
# A second, sandboxed container runtime next to runc: a pod that sets runtimeClassName: gvisor (the RuntimeClass object, handler
# runsc, is created by GitOps) runs on gVisor's user-space kernel instead of directly on the node's kernel. Two cloud-init parts,
# both run BEFORE the part EKS adds for the node group (the module only accepts these "pre" parts for a managed node group, EKS merges
# in its own nodeadm configuration):
#   1. a script that installs the pinned, checksum-verified release (gvisor-install.sh.tftpl),
#   2. a nodeadm NodeConfig whose inline containerd TOML adds the runtime handler named exactly runsc. nodeadm merges that TOML into
#      /etc/containerd/config.toml. The keys are containerd 2.x's (config version 3): "io.containerd.cri.v1.runtime"; nodeadm
#      recognises that and refuses it on containerd 1.x, which fails the boot loudly instead of ignoring the runtime.
# Changing either part changes the launch template, so the node group replaces its nodes (one at a time, see update_config).
locals {
  gvisor_install_script = templatefile("${path.module}/gvisor-install.sh.tftpl", {
    release  = var.gvisor_release
    sha512   = var.gvisor_sha512
    platform = var.gvisor_platform
  })

  gvisor_node_config = <<-EOT
    ---
    apiVersion: node.eks.aws/v1alpha1
    kind: NodeConfig
    spec:
      containerd:
        config: |
          [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc]
            runtime_type = 'io.containerd.runsc.v1'

          [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc.options]
            TypeUrl = 'io.containerd.runsc.v1.options'
            ConfigPath = '/etc/containerd/runsc.toml'
  EOT
}

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

  # IMDSv2 only, and one network hop: a pod (which is one hop further away than the node's own processes) cannot reach the instance
  # metadata service, so it cannot read the node role's credentials. Pods that need AWS use IRSA (the EBS CSI driver below and the
  # External Secrets role); Cilium and the Gateway run in the host network and are not affected. These are also the module's defaults,
  # written down so that nothing changes them silently. (The EBS CSI driver may log that it falls back from IMDS to the Kubernetes
  # API for the node's zone and instance ID: it still works, see docs/architecture.md.)
  metadata_options = {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  cloudinit_pre_nodeadm = [
    {
      content_type = "text/x-shellscript; charset=\"us-ascii\""
      filename     = "gvisor-install.sh"
      content      = local.gvisor_install_script
    },
    {
      content_type = "application/node.eks.aws"
      filename     = "gvisor-containerd.yaml"
      content      = local.gvisor_node_config
    },
  ]

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
