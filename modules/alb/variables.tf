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

variable "certificate_arn" {
  description = "ACM certificate of the domain (stacks/foundation). The load balancer serves HTTPS with it; port 80 only redirects to HTTPS."
  type        = string
}

variable "ssl_policy" {
  description = "TLS policy of the HTTPS listener (TLS 1.2 and 1.3)."
  type        = string
  default     = "ELBSecurityPolicy-TLS13-1-2-2021-06"
}

variable "allowed_cidrs" {
  description = "CIDRs allowed to reach the load balancer on ports 80 and 443 (your own address, /32)."
  type        = list(string)

  validation {
    condition     = length(var.allowed_cidrs) > 0 && alltrue([for c in var.allowed_cidrs : can(cidrhost(c, 0))])
    error_message = "Give at least one valid CIDR, for example [\"203.0.113.7/32\"]."
  }
}

variable "internal_cidrs" {
  description = "Addresses inside the platform that may also reach the load balancer on ports 80 and 443: the NAT gateways' public IPs. Pods (Argo CD, Backstage) reach https://dex.<domain> through the NAT gateway and the ALB, so without them single sign-on cannot work. A list whose LENGTH is known at plan time (the values need not be)."
  type        = list(string)
  default     = []
}

variable "gateway_port" {
  description = "Port the Cilium Gateway listeners bind on every node (hostNetwork). The load balancer sends traffic here. Above 1023: Cilium's Envoy has no privileges for lower ports."
  type        = number

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
