#!/usr/bin/env bash
# Prints the name of the state bucket: <name>-tfstate-<account>-<region>. The one place this rule is written down;
# stacks/bootstrap/main.tf builds the same name, and the pipeline reads the result from the repository variable TF_STATE_BUCKET.
set -euo pipefail

name="${1:-platform-demo}"
region="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
account="$(aws sts get-caller-identity --query Account --output text)"
echo "${name}-tfstate-${account}-${region}"
