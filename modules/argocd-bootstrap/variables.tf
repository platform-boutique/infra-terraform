variable "argocd_chart_version" {
  description = "Version of the argo/argo-cd Helm chart used for the bootstrap install. Keep it equal to targetRevision in gitops/apps/application-argocd.yaml of the Helm repository (and ARGOCD_CHART_VERSION in kind/up.sh). Only used when the release is created: Argo CD upgrades itself from Git afterwards."
  type        = string
}

variable "hostname" {
  description = "Full host name Argo CD is served on through the Gateway (argocd.<domain>): its global.domain and public URL."
  type        = string
}

variable "admin_enabled" {
  description = "Keep Argo CD's built-in admin account enabled in the bootstrap install. false (recommended): nobody has a password, break-glass is `argocd --core` with the cluster-admin IAM identity. Git disables it either way once the root Application has synced; this only matters for the minutes in between and is ignored after the first install."
  type        = bool
}

variable "git_repo_url" {
  description = "Git repository the root Application syncs from (the Helm repository)."
  type        = string
}

variable "git_revision" {
  description = "Branch, tag or commit of that repository the root Application follows."
  type        = string
}

variable "git_path" {
  description = "Directory of the repository the root Application syncs (it holds the projects, ApplicationSets and Argo CD's own Application)."
  type        = string
}

variable "external_secrets_service_account" {
  description = "namespace/name of the External Secrets Operator's service account. Terraform creates it with the IAM role annotation; the chart in Git must use it with serviceAccount.create=false. Must equal the service account modules/secrets-access lets assume its role."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?/[a-z0-9]([-a-z0-9.]*[a-z0-9])?$", var.external_secrets_service_account))
    error_message = "external_secrets_service_account must be namespace/name, for example external-secrets/external-secrets."
  }
}

variable "external_secrets_role_arn" {
  description = "ARN of the IAM role (modules/secrets-access) the service account is annotated with. Never committed to Git: the account id is in it."
  type        = string
}
