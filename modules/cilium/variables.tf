variable "api_server_host" {
  description = "Host name of the Kubernetes API server (no scheme). Without kube-proxy, Cilium reaches the API server directly."
  type        = string
}

variable "cilium_version" {
  description = "Version of the cilium/cilium Helm chart. Keep it in step with kind/up.sh of the Helm repository."
  type        = string
}

variable "gateway_api_version" {
  description = "Version of the Gateway API CRDs (standard channel). Keep it in step with kind/up.sh of the Helm repository."
  type        = string
}

variable "gateway_crds_sha256" {
  description = "SHA-256 of standard-install.yaml of that release: the download is refused if it differs."
  type        = string
}

variable "pod_cidr" {
  description = "CIDR the pods get their addresses from. An overlay: it is not routed in the VPC, so it only must not overlap the VPC or the service CIDR."
  type        = string
}

variable "pod_cidr_mask_size" {
  description = "Size of the block of pod addresses each node gets."
  type        = number
  default     = 24
}

variable "operator_replicas" {
  description = "Replicas of the Cilium operator (2 = highly available, one per node)."
  type        = number
  default     = 2
}

variable "mutual_authentication_enabled" {
  description = "Install SPIRE with Cilium and enable mutual authentication (SPIFFE identities, authentication.mode: required in policies). Beta in Cilium, deprecated in 1.20."
  type        = bool
}

variable "spire_storage_class_name" {
  description = "StorageClass of the SPIRE server's PersistentVolumeClaim (the gp3 class of modules/storage-class). Only a name: the class does not exist yet when Cilium is installed, so the claim stays Pending until it does."
  type        = string
}

variable "spire_data_size" {
  description = "Size of the SPIRE server's volume (a small database and the CA)."
  type        = string
}

variable "encryption_enabled" {
  description = "Transparent WireGuard encryption of pod traffic between nodes. Needs UDP 51871 between the nodes and a kernel with WireGuard."
  type        = bool
}

variable "node_encryption_enabled" {
  description = "Also encrypt node-to-node, pod-to-node and node-to-pod traffic (covers the Gateway's host-network Envoy). Beta in Cilium; only effective when encryption_enabled is true."
  type        = bool
}
