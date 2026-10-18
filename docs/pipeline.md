# The pipeline

All workflows call the shared Terraform pipeline in `platform-demo-workflows` (`terraform-ci`, `terraform-apply`, `terraform-destroy`).

| Workflow | When | What |
|---|---|---|
| **CI** (`ci.yaml`) | every pull request | secret scan, workflow lint, then: `fmt` + `validate`, **TFLint**, **Trivy** (misconfigurations), **Checkov** (policy as code), an **Infracost** monthly estimate and a **plan** as a pull request comment. Changes nothing in AWS. |
| **Bootstrap** (`bootstrap.yaml`) | by hand, once | creates the S3 state bucket. Run it before the first Deploy. |
| **Deploy** (`deploy.yaml`) | by hand | init, plan, apply. Waits for your approval on the `production` environment. |
| **Destroy** (`destroy.yaml`) | by hand | type `destroy platform-demo`, approve on the `destruction` environment. Empties the cluster (Argo CD apps, PVCs, LoadBalancer Services), destroys, lists leftovers. Never touches the state bucket. |

## Setup (done once)

- **Secrets** (Settings -> Secrets and variables -> Actions): `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`. Optional: `INFRACOST_API_KEY`
  (free: sign up at infracost.io; without it the cost job is skipped). A GitHub OIDC role (`role_to_assume`) replaces the keys later.
- **Variables:** `TF_STATE_BUCKET` (`platform-demo-tfstate-<account id>-us-east-1`), `API_ALLOWED_CIDRS` and `ALB_ALLOWED_CIDRS`
  (JSON lists such as `["203.0.113.7/32"]`).
- **Environments:** `production` and `destruction`, each with a required reviewer and only `main` allowed.

## Running it

1. Merge to `main`, then Actions -> **Bootstrap** -> Run workflow (once).
2. Actions -> **Deploy** -> Run workflow; approve when it asks. About 20 minutes.
3. Actions -> **Destroy** -> type the confirmation -> approve. Tick "delete leftover volumes" to remove unattached EBS volumes the driver created.

## Accepted risks

Scanners fail on HIGH/CRITICAL findings. What is accepted is written down with its reason: `.trivyignore.yaml`, inline
`#checkov:skip=ID:reason` next to the resource, and one line in `.checkov.yaml`. Every accepted risk has the same cause: there is no
domain yet (HTTP only, public ALB restricted to your address) or the environment is a test one (no WAF, no access logs, no replication).

## The cluster API and the runners

The API endpoint admits only listed addresses (yours). A GitHub-hosted runner has a new address on every run, so Deploy and Destroy add
the runner's address to `api_allowed_cidrs` and, if the cluster exists, to the endpoint before Terraform refreshes the cluster's Helm and
manifest resources. The PR plan does not refresh (`-refresh=false`) and so needs no such access.
