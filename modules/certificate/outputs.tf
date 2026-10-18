output "certificate_arn" {
  description = "ARN of the issued certificate (only known once validation has finished)."
  value       = aws_acm_certificate_validation.this.certificate_arn
}

output "domain_name" {
  description = "The domain the certificate covers."
  value       = var.domain_name
}
