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
