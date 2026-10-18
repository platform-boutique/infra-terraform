# Cilium as the cluster's CNI, as an overlay (VXLAN), without kube-proxy, serving the Gateway API on the nodes' network.
#
# Why this lives in Terraform and not in Argo CD: nodes do not become Ready without a CNI, and Argo CD needs nodes. Cilium is the
# one piece of cluster software that has to exist before anything else (the same reason kind/up.sh installs it before Argo CD).

# --- Gateway API CRDs --------------------------------------------------------------------------------------------------------
# They must exist before Cilium starts, or its Gateway controller stays off. The release asset is pinned by version and checked
# against a checksum. Applied server-side: the CRDs are too large for client-side apply's annotation.
data "http" "gateway_api_crds" {
  url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.gateway_api_version}/standard-install.yaml"

  lifecycle {
    postcondition {
      condition     = sha256(self.response_body) == var.gateway_api_crds_sha256
      error_message = "standard-install.yaml of Gateway API ${var.gateway_api_version} does not match gateway_api_crds_sha256. Refusing to apply it."
    }
  }
}

data "kubectl_file_documents" "gateway_api_crds" {
  content = data.http.gateway_api_crds.response_body
}

resource "kubectl_manifest" "gateway_api_crds" {
  for_each = data.kubectl_file_documents.gateway_api_crds.manifests

  yaml_body         = each.value
  server_side_apply = true
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

  depends_on = [kubectl_manifest.gateway_api_crds]
}
