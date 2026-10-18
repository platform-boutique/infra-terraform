variable "domain_name" {
  description = "The domain the certificate is for. It also covers every host under it (*.domain_name)."
  type        = string
}

variable "zone_id" {
  description = "Route 53 hosted zone of the domain: the DNS validation records are created in it."
  type        = string
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
