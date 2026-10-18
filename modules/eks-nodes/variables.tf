variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "cluster_endpoint" {
  description = "API server endpoint (https://...)."
  type        = string
}

variable "cluster_certificate_authority_data" {
  description = "Base64 CA of the API server."
  type        = string
}

variable "cluster_service_cidr" {
  description = "CIDR of Kubernetes Services."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version of the nodes (the control plane's)."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets of the nodes, one per availability zone: the node group spreads across them."
  type        = list(string)
}

variable "node_security_group_id" {
  description = "Security group of the nodes (created with the cluster)."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster's OIDC provider."
  type        = string
}

variable "oidc_provider" {
  description = "Issuer of the OIDC provider without the scheme."
  type        = string
}

variable "instance_types" {
  description = "Instance types of the node group. All must have the same vCPU and memory so Spot can pick the cheapest available one."
  type        = list(string)
}

variable "capacity_type" {
  description = "SPOT or ON_DEMAND."
  type        = string

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.capacity_type)
    error_message = "capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "desired_size" {
  description = "Number of nodes."
  type        = number
}

variable "min_size" {
  description = "Smallest number of nodes."
  type        = number
}

variable "max_size" {
  description = "Largest number of nodes (room for the surge node of a rolling update)."
  type        = number
}

variable "disk_size_gib" {
  description = "Size of each node's root volume."
  type        = number
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
