variable "region" {
  description = "AWS region of the state bucket (and of the platform)."
  type        = string
}

variable "name" {
  description = "Prefix of the state bucket and of the pipeline's roles; the account ID and region are appended to the bucket name to make it globally unique."
  type        = string
}

variable "github_repository" {
  description = "The repository whose workflows may assume the pipeline roles, as owner/name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "github_apply_environments" {
  description = "GitHub environments whose jobs may assume the apply role. Their required reviewers are what stands between a workflow run and a change in AWS."
  type        = list(string)

  validation {
    condition     = length(var.github_apply_environments) > 0
    error_message = "Name at least one environment."
  }
}
