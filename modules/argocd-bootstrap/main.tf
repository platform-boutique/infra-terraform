# Argo CD, installed once by Terraform, which then hands the cluster over to Git.
#
# Terraform builds what has to exist before anything can be deployed from Git (network, control plane, Cilium, nodes, storage class) and
# installs ONLY Argo CD, the root Application and the two things Git cannot carry (see below). From the moment the root Application
# syncs, Git is the single source of truth: Argo CD re-applies its own full configuration (gitops/argocd/values.yaml: Dex single sign-on,
# RBAC, resources ...) and manages its own upgrades through the `argocd` Application of the Helm repository, exactly as kind/up.sh
# does locally (helm install, then the root Application).
#
#   Terraform (this module)                              Git (platform-demo-helm, gitops/)
#   -----------------------                              ---------------------------------
#   namespaces argocd, external-secrets                  apps/: projects, ApplicationSets, Kyverno, policies ...
#   ServiceAccount external-secrets/external-secrets  -> apps/ (External Secrets Operator, serviceAccount.create=false)
#   helm release argocd (minimal bootstrap values)       apps/application-argocd.yaml: Argo CD manages itself
#   helm release argocd-root (AppProject + root app) ->  the root app syncs apps/
#
# Everything here is installed with the Helm provider only: it is the one that can plan before the cluster exists (kubernetes_manifest
# cannot). Hence the two tiny local charts in charts/. Nothing here creates an AWS resource from Kubernetes: Argo CD has no
# LoadBalancer Service and no Ingress, it is reached through the ALB and the Cilium Gateway (docs/alb-and-gateway.md).
#
# The cluster is brand new when this runs: no Kyverno (its policies and webhooks arrive later through Git), no External Secrets Operator,
# no monitoring CRDs, no Gateway. Nothing in the bootstrap depends on them (no ServiceMonitor, no ExternalSecret, no policy exception).

locals {
  # Names that Git refers to. They are fixed on purpose and must not be changed here alone: gitops/apps/application-argocd.yaml has
  # releaseName `argocd` and destination namespace `argocd`, so the resources of the release below keep the names Argo CD will
  # re-apply them under (it adopts them instead of creating a second Argo CD next to the first one).
  argocd_namespace         = "argocd"
  argocd_release_name      = "argocd"
  external_secrets_ns      = split("/", var.external_secrets_service_account)[0]
  external_secrets_account = split("/", var.external_secrets_service_account)[1]
}

# --- Namespaces and the External Secrets service account ----------------------------------------------------------------------------
# Created here and not by Argo CD for two reasons:
#  - the service account carries the IAM role's ARN (eks.amazonaws.com/role-arn), which contains the AWS account id and is only known to
#    Terraform. Git is public and never holds it: the External Secrets chart in Git runs with serviceAccount.create=false and
#    name=external-secrets and simply uses this account,
#  - the Pod Security labels are in place before the first pod is created.
# The Argo CD Applications may still use CreateNamespace/managedNamespaceMetadata on these namespaces: the labels are identical.
# Released in kube-system (a namespace that Helm does not manage), so that uninstalling the release can delete the namespaces it created.
resource "helm_release" "prerequisites" {
  name      = "bootstrap-prerequisites"
  chart     = "${path.module}/charts/prerequisites"
  namespace = "kube-system"

  # Do not wait for the namespaces to disappear on destroy: a namespace with a stuck finalizer would hang the destroy for nothing.
  wait    = false
  timeout = 120

  values = [yamlencode({
    argocd = {
      namespace = local.argocd_namespace
    }
    externalSecrets = {
      namespace      = local.external_secrets_ns
      serviceAccount = local.external_secrets_account
      roleArn        = var.external_secrets_role_arn
    }
  })]
}

# --- Argo CD, bootstrap only --------------------------------------------------------------------------------------------------------
# Chart version: the one gitops/apps/application-argocd.yaml of the Helm repository pins (targetRevision) and kind/up.sh installs. Keep
# the three in step: if they differ, the first sync of the `argocd` Application is an upgrade or downgrade of this release's resources.
#
# THE HAND-OVER. This release is bootstrap-only. After the root Application has synced, the Application `argocd` (releaseName argocd,
# same chart, values from Git) re-applies every resource of this release with the full configuration. Terraform and Argo CD must not
# fight over it, so Terraform stops managing the release after creating it:
#  - lifecycle.ignore_changes on `values` and `version`: a later edit of the bootstrap values below, or of argocd_chart_version, is
#    ignored by plan and apply. To change Argo CD, change the Helm repository; to run a new bootstrap, destroy and rebuild.
#  - Terraform never reads the live objects of the release (the Helm provider only compares the release record, a Secret that Argo CD
#    does not touch: it renders the chart with `helm template` and applies the result itself), so Argo CD's changes show up as no drift.
#  - destroy: scripts/destroy-prepare.sh removes the Argo CD Applications first; Terraform then uninstalls this release and, with the
#    cluster, everything else.
# Only what is needed to get in and to sync is set here. Everything else is Git's.
resource "helm_release" "argocd" {
  name       = local.argocd_release_name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = local.argocd_namespace

  # The namespace is created by the prerequisites release (with its labels), not by Helm.
  create_namespace = false

  # Wait until Argo CD is up: the root Application (next resource) needs its CRDs and controllers. The cluster has Ready nodes,
  # Cilium and CoreDNS by now, so a failure here is a real one.
  wait    = true
  timeout = 900

  values = [yamlencode({
    global = {
      domain = var.hostname
    }

    configs = {
      params = {
        # TLS ends at the ALB; the Cilium Gateway talks plain HTTP to the server inside the cluster.
        "server.insecure" = true
      }
      cm = {
        url = "https://${var.hostname}"

        # Same as gitops/argocd/values.yaml: no local accounts. Git switches it off in any case, so enabling it here is only a window
        # between the install and the first sync (minutes) in which the initial admin password exists: see argocd_admin_enabled.
        "admin.enabled" = tostring(var.admin_enabled)
      }
    }

    # Single sign-on is the standalone Dex that Git installs later; the Dex bundled with Argo CD and the notifications controller
    # are off in Git too, and must not start here only to be deleted again.
    dex = {
      enabled = false
    }
    notifications = {
      enabled = false
    }

    # Reached only through the Gateway: a ClusterIP Service (the chart's default, spelled out). Never a LoadBalancer, never an Ingress:
    # nothing in Kubernetes creates an AWS resource.
    server = {
      service = {
        type = "ClusterIP"
      }
    }
  })]

  lifecycle {
    ignore_changes = [values, version]
  }

  depends_on = [helm_release.prerequisites]
}

# --- The root Application ---------------------------------------------------------------------------------------------------------
# The AppProject platform-admin and the Application platform-root, the same objects as gitops/bootstrap/root.yaml (which kind/up.sh
# applies by hand). The AppProject is ALSO declared in Git (gitops/apps/appproject-platform-admin.yaml, "adopted from bootstrap/root.yaml"):
# the copy here only lets the root Application start, the one in Git is the reviewed one; keep them identical.
# Needs the Argo CD CRDs, hence the dependency on the (waiting) Argo CD release.
resource "helm_release" "root" {
  name      = "argocd-root"
  chart     = "${path.module}/charts/root"
  namespace = local.argocd_namespace

  wait    = false
  timeout = 120

  values = [yamlencode({
    namespace = local.argocd_namespace
    repoURL   = var.git_repo_url
    revision  = var.git_revision
    path      = var.git_path
  })]

  depends_on = [helm_release.argocd]
}
