output "certificate_arn" {
  description = "ARN of the certificate for the domain and *.domain (the platform finds it by domain name)."
  value       = module.certificate.certificate_arn
}

output "zone_id" {
  description = "Hosted zone of the domain."
  value       = data.aws_route53_zone.this.zone_id
}
