variable "name" {
  description = "Prefix of the IAM role name (the cluster name)."
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

variable "parameter_prefix" {
  description = "Systems Manager Parameter Store path the platform's secrets live under. Created by hand (never by Terraform, so the values stay out of the state) and kept when the platform is destroyed."
  type        = string

  validation {
    condition     = can(regex("^/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*$", var.parameter_prefix))
    error_message = "parameter_prefix must be a path such as /platform-demo (leading slash, no trailing slash)."
  }
}

variable "secret_arns" {
  description = "ARNs of Secrets Manager secrets (not Parameter Store) the role may also read, for example the master user secret RDS manages. Exact ARNs only; read-only."
  type        = list(string)
  default     = []
}

variable "secret_kms_key_arns" {
  description = "ARNs of the customer-managed KMS keys those secrets are encrypted with: the role may decrypt with them, through Secrets Manager only."
  type        = list(string)
  default     = []
}

variable "service_account" {
  description = "Kubernetes service account that may assume the role, as namespace/name (the External Secrets Operator's)."
  type        = string
  default     = "external-secrets/external-secrets"
}

variable "tags" {
  description = "Tags added to every resource."
  type        = map(string)
  default     = {}
}
