variable "name" {
  description = "Name of the load balancer (at most 28 characters: the target group appends \"-gw\")."
  type        = string

  validation {
    condition     = length(var.name) <= 28
    error_message = "name must be at most 28 characters."
  }
}

variable "vpc_id" {
  description = "VPC of the load balancer and the nodes."
  type        = string
}

variable "subnet_ids" {
  description = "Public subnets of the load balancer, one per availability zone."
  type        = list(string)
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach the load balancer on port 80 (your own address, /32). There is no TLS without a domain, so do not open it to the world."
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidrs) > 0 && alltrue([for c in var.allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "Give at least one valid CIDR, for example [\"203.0.113.7/32\"]."
  }
}

variable "gateway_port" {
  description = "Port the Cilium Gateway listeners bind on every node (hostNetwork). The load balancer sends traffic here. Above 1023: Cilium's Envoy has no privileges for lower ports."
  type        = number
  default     = 8080

  validation {
    condition     = var.gateway_port > 1023 && var.gateway_port < 65536
    error_message = "gateway_port must be between 1024 and 65535."
  }
}

variable "node_security_group_id" {
  description = "Security group of the nodes: it gets a rule that lets the load balancer reach gateway_port."
  type        = string
}

variable "autoscaling_group_names" {
  description = "Auto Scaling groups whose instances are the load balancer's targets, by a static key."
  type        = map(string)
}

variable "deletion_protection" {
  description = "Protect the load balancer from deletion (turn on once the platform is long-lived)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
