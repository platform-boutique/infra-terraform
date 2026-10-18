output "dns_name" {
  description = "DNS name AWS gives the load balancer: the platform's address while there is no domain."
  value       = aws_lb.this.dns_name
}

output "arn" {
  description = "ARN of the load balancer."
  value       = aws_lb.this.arn
}

output "target_group_arn" {
  description = "ARN of the target group (the nodes, on the gateway port)."
  value       = aws_lb_target_group.gateway.arn
}

output "security_group_id" {
  description = "Security group of the load balancer."
  value       = aws_security_group.alb.id
}
