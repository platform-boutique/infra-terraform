variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Name of the platform: cluster, VPC and load balancer (at most 28 characters)."
  type        = string
  default     = "platform-demo"
}

variable "azs" {
  description = "Availability zones (high availability: two, one NAT gateway and one subnet pair each)."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "vpc_cidr" {
  description = "CIDR of the VPC; the subnets are /24 blocks of it."
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Kubernetes version of the cluster."
  type        = string
  default     = "1.35"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint: your own address as /32, for example [\"203.0.113.7/32\"]."
  type        = list(string)
}

variable "alb_allowed_cidrs" {
  description = "CIDRs allowed to reach the ALB on port 80: your own address as /32. Plain HTTP (there is no domain for a certificate), so keep it narrow."
  type        = list(string)
}

variable "admin_principal_arns" {
  description = "Extra IAM principals that get cluster-admin, by label (the principal that runs Terraform always has it)."
  type        = map(string)
  default     = {}
}

variable "node_instance_types" {
  description = "Instance types of the Spot worker nodes. All 4 vCPU / 16 GiB, in several families so Spot can pick whichever is cheapest and available."
  type        = list(string)
  default     = ["m6i.xlarge", "m6a.xlarge", "m5.xlarge", "m5a.xlarge", "m7i.xlarge", "m7a.xlarge"]
}

variable "node_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2
}

variable "node_disk_size_gib" {
  description = "Root volume of each node."
  type        = number
  default     = 100
}

variable "gateway_port" {
  description = "Port the Cilium Gateway listeners bind on every node; the ALB forwards to it. The Gateway's listener must use the same port."
  type        = number
  default     = 8080
}
