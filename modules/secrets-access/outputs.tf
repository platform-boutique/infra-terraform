output "role_arn" {
  description = "IAM role of the External Secrets Operator: annotate its service account with eks.amazonaws.com/role-arn."
  value       = aws_iam_role.external_secrets.arn
}

output "parameter_prefix" {
  description = "Path the secrets live under."
  value       = var.parameter_prefix
}
