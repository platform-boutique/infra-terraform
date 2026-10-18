# Remote state in the bucket stacks/bootstrap created. The bucket name contains the account ID, so it is given at init:
#   terraform init -backend-config="bucket=$(scripts/state-bucket.sh)" -backend-config="region=us-east-1"
terraform {
  backend "s3" {
    key          = "foundation/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
