variable "region" {
  description = "AWS region of the state bucket (and of the platform)."
  type        = string
}

variable "name" {
  description = "Prefix of the state bucket and of the pipeline's roles; the account ID and region are appended to the bucket name to make it globally unique."
  type        = string
}

variable "github_repository" {
  description = "The repository whose workflows may assume the pipeline roles, as owner/name (used in descriptions)."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must look like owner/name."
  }
}

variable "github_subject_prefix" {
  description = "How the repository appears in the subject (sub) claim of its OIDC tokens. Newer repositories use immutable subjects with the numeric owner and repository IDs, for example repo:owner@123/name@456, so a renamed or re-created repository cannot impersonate this one. Read it with: gh api repos/OWNER/NAME/actions/oidc/customization/sub --jq .sub_claim_prefix"
  type        = string

  validation {
    condition     = can(regex("^repo:[^:]+$", var.github_subject_prefix))
    error_message = "github_subject_prefix must look like repo:owner@123/name@456 (or repo:owner/name), with no colon after the repo part."
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
