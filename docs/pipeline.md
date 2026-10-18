# The pipeline

The workflows are thin callers of the shared Terraform pipeline in `platform-demo-workflows` (`terraform-ci`, `terraform-plan`,
`terraform-apply`). AWS is reached through GitHub OIDC: no access key is stored anywhere.

| Workflow | When | What |
|---|---|---|
| **CI** (`ci.yaml`) | every pull request | secret scan, workflow lint, `fmt` + `validate`, **TFLint**, **Trivy**, **Checkov**, an **Infracost** estimate and a **plan** as a comment. Changes nothing in AWS (read-only role). |
| **Foundation** (`foundation.yaml`) | by hand, once | plans the certificate, then reviews and applies that plan after your approval. Destroy never touches it. |
| **Deploy** (`deploy.yaml`) | by hand, with a reason | one run: **Plan** (saved, shows your reason and what would change), **Review** (checks the saved plan and shows it again), then **Apply**, which waits for your approval on the `production` environment and applies exactly that plan. |
| **Destroy** (`destroy.yaml`) | by hand, reason + `destroy platform-demo` | the same three steps for `stacks/platform`; approval on the `destruction` environment. Before the destroy `scripts/destroy-prepare.sh` empties the cluster; afterwards `scripts/destroy-verify.sh` lists leftovers. |

## What you approve is what runs

The plan is saved in the state bucket under `plans/<stack>/<plan id>/` (encrypted, deleted after 7 days or once applied); it is not an
artifact, because artifacts of a public repository are public and a plan file can hold secret values. The Review job refuses a plan that
- was made for another commit (the code changed after it: plan again),
- is older than 24 hours,
- is a destroy plan when the workflow deploys, or the reverse,
- no longer matches its recorded checksum.

The plan id is passed between the jobs of the run. The Apply job re-checks the checksum after your approval and runs `terraform apply` on that file; Terraform itself rejects a plan whose
state changed in the meantime.

## What you see before you approve

The Review job's run page shows, in this order: your reason, **At a glance** (totals, anything **destroyed or replaced** listed first,
which settings change on updates; computed by script from the plan, no values), and every change. Approve from that list.

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
