# The cluster's default StorageClass: gp3, encrypted, through the EBS CSI driver.
#
# EKS ships only the legacy `gp2` class (in-tree provisioner, unencrypted unless the account default says so, default of the cluster),
# and there is no gp3 class. PersistentVolumeClaims (Cilium's SPIRE server, and through GitOps Postgres, Loki, Mimir, Grafana ...) should
# get encrypted gp3 volumes, so this module creates the class and makes it the one default.
#
# This module must be applied AFTER the EBS CSI add-on (modules/eks-nodes): a claim whose class is created before the driver exists
# just waits, but nothing proves the driver can provision until it runs, and the stack orders it after the nodes module anyway.
# (The SPIRE server's claim is created earlier, by Cilium, and stays Pending until this class exists: that is expected.)

# --- The gp3 class, as a tiny local chart --------------------------------------------------------------------------------------
# Installed with the Helm provider like the Gateway API CRDs (modules/cilium): the Helm provider is the one that can plan before the
# cluster exists (kubernetes_manifest cannot). Release namespace kube-system holds only the release's bookkeeping Secret; a
# StorageClass is cluster-scoped.
resource "helm_release" "storage_class" {
  name      = "storage-class-${var.name}"
  chart     = "${path.module}/charts/storage-class"
  namespace = "kube-system"

  values = [yamlencode({
    name    = var.name
    default = var.make_default
  })]
}

# --- gp2 stops being the default -----------------------------------------------------------------------------------------------
# A cluster has one default class. Kubernetes (1.26+) tolerates two by picking the newest, which would work by accident, but a
# claim should never depend on creation order, and the annotation on gp2 is not ours to keep. Helm cannot do this: it only manages
# objects its own release created, and gp2 is created by EKS. So the annotation is set to "false" with the Kubernetes provider's
# `kubernetes_annotations`, which patches only that one annotation (server-side apply, field manager of Terraform) and leaves
# the rest of EKS's object alone. `force` takes the field over from EKS's own manager.
# On destroy the annotation is removed again (the cluster is going away anyway).
resource "kubernetes_annotations" "legacy_class_not_default" {
  count = var.make_default && var.demote_legacy_class ? 1 : 0

  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = var.legacy_class_name
  }
  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }
  force = true

  # Demote gp2 only once gp3 exists, so that there is never a moment without a default.
  depends_on = [helm_release.storage_class]
}
