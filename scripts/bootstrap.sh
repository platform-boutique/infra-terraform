#!/usr/bin/env bash
# One-time (and repeatable) setup of stacks/bootstrap with the credentials of an administrator: the state bucket, GitHub's OIDC provider and
# the pipeline's two roles. The bucket cannot hold its own state before it exists, so the first run applies with a local state file and
# then moves that state into the bucket; every later run just uses the bucket.
#
#   scripts/bootstrap.sh            plan, show it, ask, apply
#   scripts/bootstrap.sh --plan     only plan
set -euo pipefail

cd "$(dirname "$0")/../stacks/bootstrap"
export AWS_REGION="${AWS_REGION:-us-east-1}"
only_plan=false
[ "${1:-}" = "--plan" ] && only_plan=true

bucket="$(../../scripts/state-bucket.sh)"
echo "State bucket: $bucket"
backend=(-backend-config="bucket=$bucket" -backend-config="region=$AWS_REGION")

# A local state file means a first run that has not finished moving its state (the bucket may already exist): carry on in local mode.
if [ ! -f terraform.tfstate ] && aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
  echo "The bucket exists: using it as the backend."
  terraform init -input=false -lockfile=readonly "${backend[@]}"
  first_run=false
else
  echo "Starting with a local state file (override file, not committed)."
  printf 'terraform {\n  backend "local" {}\n}\n' > backend_override.tf
  trap 'rm -f backend_override.tf' EXIT
  terraform init -input=false -lockfile=readonly -reconfigure
  first_run=true
fi

terraform plan -input=false -out=tfplan
$only_plan && exit 0

read -r -p "Apply this plan? [type yes] " answer
[ "$answer" = "yes" ] || { echo "Nothing was changed."; exit 1; }
terraform apply -input=false tfplan
rm -f tfplan

if $first_run; then
  echo "Moving the state into the bucket."
  rm -f backend_override.tf
  terraform init -input=false -lockfile=readonly -migrate-state -force-copy "${backend[@]}"
  rm -f terraform.tfstate terraform.tfstate.backup
fi

echo
echo "Repository variables for the pipeline (gh variable set ... --repo platform-boutique/infra-terraform):"
echo "  TF_STATE_BUCKET   = $(terraform output -raw bucket)"
echo "  AWS_PLAN_ROLE_ARN = $(terraform output -raw plan_role_arn)"
echo "  AWS_APPLY_ROLE_ARN = $(terraform output -raw apply_role_arn)"
