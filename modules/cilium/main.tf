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

# --- Optional features, each behind a variable -------------------------------------------------------------------------------
locals {
  # Mutual authentication (SPIFFE/SPIRE), the same settings as kind/cilium-values.yaml of the Helm repository. Beta, and deprecated
  # by Cilium 1.20 (removal announced for 1.21): the pinned chart still ships it, and it is what the platform's policies are written
  # against. Cilium installs its own SPIRE server (StatefulSet) and agents (DaemonSet) in the namespace cilium-spire.
  #
  # Ordering that Terraform cannot express (see docs/architecture.md): Cilium starts BEFORE the SPIRE server exists, and the server
  # needs a node and its volume (the gp3 StorageClass, modules/storage-class, comes after the nodes). Cilium agents and operator
  # retry the connection, nodes do not wait for SPIRE, but they only pick up their SPIFFE identity after a restart once the
  # server is Ready. That restart is a post-sync Job in the GitOps repository, not a Terraform step.
  mutual_authentication_values = var.mutual_authentication_enabled ? {
    authentication = {
      enabled = true
      mutual = {
        spire = {
          enabled = true
          install = {
            enabled = true
            server = {
              # The SPIRE CA and registration entries live on a PersistentVolume, so restarting the server does not change the
              # trust domain's CA and does not disturb running workloads. The class is named explicitly (and not left to the
              # default) so that the volume cannot silently end up on the legacy gp2 class EKS ships.
              dataStorage = {
                enabled      = true
                size         = var.spire_data_size
                accessMode   = "ReadWriteOnce"
                storageClass = var.spire_storage_class_name
              }

              # Same workaround as kind/cilium-values.yaml: the SPIRE image defaults to uid 1000, which breaks the chart on EKS too:
              #  1. the hostPath directory for the admin socket (DirectoryOrCreate) is created root:root 0755 by the kubelet, so
              #     uid 1000 cannot bind the socket ("bind: permission denied"; SPIRE then hangs instead of exiting),
              #  2. the cilium-init sidecar registers Cilium's identities through /proc/<pid>/root of the server process, which
              #     Linux only allows across different users with CAP_SYS_PTRACE: nothing is registered and every handshake
              #     fails with "no SPIFFE ID",
              #  3. (EKS only) the EBS volume is mounted root-owned and the chart sets no fsGroup, so uid 1000 could not write
              #     the data directory.
              # The container is not privileged (no extra capabilities) and only the cluster reaches it (ClusterIP). If a chart
              # release ever sets fsGroup and registers without root, remove this block.
              securityContext = {
                runAsUser  = 0
                runAsGroup = 0
              }
            }
          }
        }
      }
    }
  } : {}

  # Transparent encryption with WireGuard. Compatibility with this cluster (checked against the Cilium documentation):
  #  - tunnel routing (VXLAN): supported; pod traffic is encapsulated twice (VXLAN, then WireGuard) and Cilium subtracts both
  #    overheads from the MTU on its own (the nodes' ENIs have an MTU of 9001),
  #  - kube-proxy replacement: supported (Services are translated before the packet is encrypted),
  #  - kernel: WireGuard needs CONFIG_WIREGUARD (Linux 5.6+); the AL2023 EKS AMI ships a 6.x kernel. The agent fails to start when
  #    it cannot create the cilium_wg0 device, which would keep every node NotReady: see the risks in docs/architecture.md,
  #  - nodes must allow UDP 51871 between each other (modules/eks-cluster),
  #  - Gateway API in host-network mode: traffic from the Envoy on a node to a pod on another node is encrypted with node
  #    encryption; client traffic from the ALB into the node is not (and cannot be: it comes from outside the cluster),
  #  - Hubble Relay and UI: unaffected (their traffic is ordinary pod and node traffic and is encrypted like the rest).
  # Pods on the same node are not encrypted, by design. Strict mode (drop unencrypted traffic) is not on: with tunnelling it needs
  # allowRemoteNodeIdentities, and it would drop traffic during a half-finished rollout.
  encryption_values = var.encryption_enabled ? {
    encryption = {
      enabled        = true
      type           = "wireguard"
      nodeEncryption = var.node_encryption_enabled
    }
  } : {}
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

  values = [yamlencode(merge({
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
    },
    local.mutual_authentication_values,
    local.encryption_values,
  ))]

  depends_on = [helm_release.gateway_api_crds]
}
