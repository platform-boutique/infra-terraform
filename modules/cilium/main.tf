# Cilium as the cluster's CNI, as an overlay (VXLAN), without kube-proxy, serving the Gateway API on the nodes' network.
#
# Why this lives in Terraform and not in Argo CD: nodes do not become Ready without a CNI, and Argo CD needs nodes. Cilium is the
# one piece of cluster software that has to exist before anything else (the same reason kind/up.sh installs it before Argo CD).

# --- Gateway API CRDs --------------------------------------------------------------------------------------------------------
# They must exist before Cilium starts, or its Gateway controller stays off. The release asset is kept in charts/gateway-api-crds
# exactly as upstream publishes it, and its SHA-256 is checked, so what is installed is what was reviewed. They are installed with the
# Helm provider, not the kubectl provider: only the Helm provider can plan before the cluster exists.
resource "helm_release" "gateway_api_crds" {
  name      = "gateway-api-crds"
  chart     = "${path.module}/charts/gateway-api-crds"
  version   = trimprefix(var.gateway_api_version, "v")
  namespace = "kube-system"

  lifecycle {
    precondition {
      condition     = filesha256("${path.module}/charts/gateway-api-crds/templates/standard-install.yaml") == var.gateway_crds_sha256
      error_message = "charts/gateway-api-crds/templates/standard-install.yaml does not match gateway_crds_sha256 (Gateway API ${var.gateway_api_version}). Refusing to install it; use scripts/update-gateway-api-crds.sh."
    }
  }
}

# --- Cilium ------------------------------------------------------------------------------------------------------------------
# wait = false: there are no nodes yet, so nothing can become ready here. The node group (modules/eks-nodes) waits for its nodes to
# be Ready, and they only are once the Cilium agent runs on them, so a broken Cilium fails that step instead of this one.
resource "helm_release" "cilium" {
  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  wait = false

  values = [yamlencode({
    # Overlay: pod traffic between nodes is VXLAN-encapsulated, so pods need no VPC addresses and the VPC can stay small.
    routingMode    = "tunnel"
    tunnelProtocol = "vxlan"
    ipam = {
      mode = "cluster-pool"
      operator = {
        clusterPoolIPv4PodCIDRList = [var.pod_cidr]
        clusterPoolIPv4MaskSize    = var.pod_cidr_mask_size
      }
    }

    # No kube-proxy on this cluster: Cilium implements Services and reaches the API server by name.
    kubeProxyReplacement = true
    k8sServiceHost       = var.api_server_host
    k8sServicePort       = 443

    # The Gateway API is served by Cilium, with the listeners bound on the nodes' own network (hostNetwork). No Service of type
    # LoadBalancer is created, so Kubernetes never creates a load balancer in AWS: the ALB is Terraform's (modules/alb).
    gatewayAPI = {
      enabled     = true
      hostNetwork = { enabled = true }
    }

    # Flow visibility (the portal's Network view reads Hubble Relay).
    hubble = {
      enabled = true
      relay   = { enabled = true }
      ui      = { enabled = true }
    }

    operator = {
      replicas = var.operator_replicas
    }
  })]

  depends_on = [helm_release.gateway_api_crds]
}
