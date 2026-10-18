variable "zone_id" {
  description = "Route 53 hosted zone of the domain."
  type        = string
}

variable "domain_name" {
  description = "The domain; the host names are created under it."
  type        = string
}

variable "hostnames" {
  description = "Host names (without the domain) that point at the load balancer, for example [\"argocd\", \"backstage\"]."
  type        = list(string)

  validation {
    condition     = length(var.hostnames) > 0 && alltrue([for h in var.hostnames : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", h))])
    error_message = "hostnames must be lower-case DNS labels such as \"argocd\"."
  }
}

variable "alb_dns_name" {
  description = "DNS name of the load balancer."
  type        = string
}

variable "alb_zone_id" {
  description = "Route 53 zone ID of the load balancer (an alias record needs it)."
  type        = string
}
