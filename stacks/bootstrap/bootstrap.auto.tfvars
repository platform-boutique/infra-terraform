region            = "us-east-1"
name              = "platform-demo"
github_repository = "platform-boutique/infra-terraform"
# Immutable subject of this repository: gh api repos/platform-boutique/infra-terraform/actions/oidc/customization/sub --jq .sub_claim_prefix
github_subject_prefix     = "repo:platform-boutique@343984461/infra-terraform@1424363754"
github_apply_environments = ["production", "destruction"]
