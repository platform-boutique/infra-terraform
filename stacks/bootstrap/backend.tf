# The bucket this stack creates holds this stack's own state too. The bucket name contains the account ID, so it is not written here:
#   terraform init -backend-config="bucket=$(scripts/state-bucket.sh)" -backend-config="region=us-east-1"
# The very first run, when the bucket does not exist yet, is scripts/bootstrap.sh.
terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
