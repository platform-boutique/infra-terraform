output "bucket" {
  description = "Name of the state bucket."
  value       = aws_s3_bucket.state.bucket
}

output "backend_hcl" {
  description = "Contents of envs/platform/backend.hcl."
  value       = <<-EOT
    bucket = "${aws_s3_bucket.state.bucket}"
    region = "${var.region}"
  EOT
}
