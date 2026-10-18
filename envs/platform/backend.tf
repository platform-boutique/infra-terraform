# Remote state in the bucket that bootstrap/ created. The bucket and region are not repeated here (a backend block cannot use
# variables, and the bucket name contains the account ID): terraform init -backend-config=backend.hcl
terraform {
  backend "s3" {
    key          = "platform/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
