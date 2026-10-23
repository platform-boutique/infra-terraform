output "argocd_namespace" {
  description = "Namespace Argo CD runs in."
  value       = local.argocd_namespace
}

output "external_secrets_namespace" {
  description = "Namespace of the External Secrets Operator (created here, with the service account)."
  value       = local.external_secrets_ns
}

output "external_secrets_service_account" {
  description = "Name of the pre-created, IAM-annotated service account in that namespace."
  value       = local.external_secrets_account
}

output "root_release_name" {
  description = "Name of the Helm release holding the AppProject and the root Application."
  value       = helm_release.root.name
}
