variable "region" {
  description = "AWS region of the state bucket (and of the platform)."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Prefix of the state bucket name; the account ID and region are appended to make it globally unique."
  type        = string
  default     = "platform-demo"
}
