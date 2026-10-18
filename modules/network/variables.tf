variable "name" {
  description = "Name of the VPC and prefix of everything in it."
  type        = string
}

variable "cidr" {
  description = "CIDR of the VPC. Every subnet is a /24 carved out of it, so it must be a /16 or larger (up to /8)."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr, 0)) && tonumber(split("/", var.cidr)[1]) >= 8 && tonumber(split("/", var.cidr)[1]) <= 16
    error_message = "cidr must be a valid IPv4 CIDR between /8 and /16."
  }
}

variable "azs" {
  description = "Availability zones, one public and one private /24 subnet and one NAT gateway each."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 10
    error_message = "Use between 2 and 10 availability zones (a highly available platform needs at least 2)."
  }
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
