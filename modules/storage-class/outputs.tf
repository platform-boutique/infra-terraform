output "name" {
  description = "Name of the StorageClass."
  value       = var.name
}

output "release_name" {
  description = "Name of the Helm release (callers depend on it, so they run after the class exists)."
  value       = helm_release.storage_class.name
}
