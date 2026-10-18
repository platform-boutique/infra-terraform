output "release_name" {
  description = "Name of the Helm release (the nodes module waits for it)."
  value       = helm_release.cilium.name
}
