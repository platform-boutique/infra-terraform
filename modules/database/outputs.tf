output "address" {
  description = "Host name of the database (the address only, no port)."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port of the database."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Name of the database."
  value       = aws_db_instance.this.db_name
}

output "username" {
  description = "Master user."
  value       = aws_db_instance.this.username
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret RDS keeps the master password in (JSON keys username and password). Rotated by RDS every 7 days."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "kms_key_arn" {
  description = "KMS key that encrypts the storage, the backups and the master user secret: a reader of the secret needs kms:Decrypt on it."
  value       = aws_kms_key.this.arn
}

output "security_group_id" {
  description = "Security group of the database."
  value       = aws_security_group.this.id
}

output "connection_parameter_path" {
  description = "Parameter Store path of the non-secret connection details."
  value       = var.connection_parameter_path
}
