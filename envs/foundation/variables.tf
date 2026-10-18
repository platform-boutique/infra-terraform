variable "region" {
  description = "AWS region. The certificate must be in the region of the load balancer."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "The registered domain (Route 53 -> Registered domains), for example platform-demo.click."
  type        = string
}
