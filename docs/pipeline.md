# The pipeline

The workflows are thin callers of the shared Terraform pipeline in `platform-demo-workflows` (`terraform-ci`, `terraform-plan`,
`terraform-apply`). AWS is reached through GitHub OIDC: no access key is stored anywhere.

| Workflow | When | What |
|---|---|---|
| **CI** (`ci.yaml`) | every pull request | secret scan, workflow lint, `fmt` + `validate`, **TFLint**, **Trivy**, **Checkov**, an **Infracost** estimate and a **plan** as a comment. Changes nothing in AWS (read-only role). |
| **Foundation** (`foundation.yaml`) | by hand, once | plans the certificate, then reviews and applies that plan after your approval. Destroy never touches it. |
| **Deploy plan** (`deploy-plan.yaml`) | by hand, with a reason | plans the platform and saves the plan. Changes nothing. The run page shows your reason, what would change and a **plan id**. |
| **Deploy apply** (`deploy-apply.yaml`) | by hand, with the plan id | **Review** shows the saved plan again; then **Apply** waits for your approval on the `production` environment and applies exactly that plan. |
| **Destroy plan** (`destroy-plan.yaml`) | by hand, reason + `destroy platform-demo` | plans the destruction of `stacks/platform` and saves it. |
| **Destroy apply** (`destroy-apply.yaml`) | by hand, with the plan id | Review, approval on the `destruction` environment, then `scripts/destroy-prepare.sh` empties the cluster, Terraform destroys, `scripts/destroy-verify.sh` lists leftovers. |

## What you approve is what runs

The plan is saved in the state bucket under `plans/<stack>/<plan id>/` (encrypted, deleted after 7 days or once applied); it is not an
artifact, because artifacts of a public repository are public and a plan file can hold secret values. The Review job refuses a plan that
- was made for another commit (the code changed after it: plan again),
- is older than 24 hours,
- is a destroy plan when the workflow deploys, or the reverse,
- no longer matches its recorded checksum.

The Apply job re-checks the checksum after your approval and runs `terraform apply` on that file; Terraform itself rejects a plan whose
state changed in the meantime.

## Who may do what

| Role | Who can assume it | Can do |
|---|---|---|
| `platform-demo-github-plan` | jobs of this repository's branches and pull requests | read the account, write the state lock and `plans/`; cannot read secret values |
| `platform-demo-github-apply` | only a job in the `production` or `destruction` environment | administrator |

The environments need a required reviewer and deploy only from `main`. Both roles are created by `stacks/bootstrap`.

## Setup (done once)

- **Variables** (Settings -> Secrets and variables -> Actions -> Variables): `TF_STATE_BUCKET`, `AWS_PLAN_ROLE_ARN`, `AWS_APPLY_ROLE_ARN` (all printed by
  `scripts/bootstrap.sh`) and `ALB_ALLOWED_CIDRS` (JSON list with your address, for example `["203.0.113.7/32"]`).
- **Secret (optional):** `INFRACOST_API_KEY` (free at infracost.io; without it the cost job is skipped).
- **Environments:** `production` and `destruction`, each with a required reviewer and only `main` allowed.

## Accepted risks

Scanners fail on HIGH/CRITICAL findings. What is accepted is written down with its reason: `.trivyignore.yaml`, inline
`#checkov:skip=ID:reason` next to the resource, and one line in `.checkov.yaml`.
- The ALB is public by design (it admits only your address).
- The EKS API endpoint is public and open to every address, authenticated by IAM, so that a runner and a laptop can reach it and a saved plan does not depend on either's address.
- The apply role is an administrator: Terraform creates IAM, EKS, VPC, KMS and more, and the protection is who may assume it.
- It is a test environment: no WAF, no access logs, no replication.
