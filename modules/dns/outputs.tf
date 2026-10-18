output "fqdns" {
  description = "The full host names, by short name."
  value       = { for k, r in aws_route53_record.host : k => r.fqdn }
}
