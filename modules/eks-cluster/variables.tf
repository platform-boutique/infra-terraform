variable "name" {
  description = "Name of the EKS cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version of the control plane (EKS standard support: 1.34 until 2026-12, 1.35 until 2027-03, 1.36 until 2027-08)."
  type        = string
  default     = "1.35"
}

variable "vpc_id" {
  description = "VPC of the cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Private subnets: the control plane's network interfaces and the nodes live here."
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint (your own address, /32). The endpoint is IAM-authenticated, but there is no reason to expose it to the world."
  type        = list(string)

  validation {
    condition     = length(var.public_access_cidrs) > 0 && alltrue([for c in var.public_access_cidrs : can(cidrhost(c, 0))])
    error_message = "Give at least one valid CIDR, for example [\"203.0.113.7/32\"]."
  }
}

variable "service_cidr" {
  description = "CIDR of Kubernetes Services. Set explicitly: EKS otherwise picks 10.100.0.0/16 or 172.20.0.0/16 depending on the VPC, and it must not overlap the VPC or the Cilium pod CIDR."
  type        = string
  default     = "172.20.0.0/16"
}

variable "admin_principal_arns" {
  description = "Extra IAM principals that get cluster-admin, by label. The principal that runs Terraform always has it."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Retention of the control plane logs in CloudWatch."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
