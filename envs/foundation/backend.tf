# Remote state in the bucket bootstrap/ created: terraform init -backend-config="bucket=..." -backend-config="region=..."
terraform {
  backend "s3" {
    key          = "foundation/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
