output "bucket" {
  description = "Name of the state bucket (repository variable TF_STATE_BUCKET)."
  value       = aws_s3_bucket.state.bucket
}

output "plan_role_arn" {
  description = "Role of the plan jobs (repository variable AWS_PLAN_ROLE_ARN)."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Role of the apply and destroy jobs (repository variable AWS_APPLY_ROLE_ARN)."
  value       = aws_iam_role.apply.arn
}
