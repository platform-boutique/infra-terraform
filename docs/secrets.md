# Secrets in Parameter Store, and the database

What a person has to type once, and where it lives so that a rebuilt cluster does not ask again.

| Parameter (SecureString) | What | Needed by |
|---|---|---|
| `/platform-demo/github-oauth/client-id` | Client ID of the GitHub OAuth App | Dex (GitHub sign-in) |
| `/platform-demo/github-oauth/client-secret` | Client secret of that OAuth App | Dex |
| `/platform-demo/github/token` | A GitHub token that can read the organisation's repositories | Backstage (catalog discovery, releases view) |
| `/platform-demo/dockerhub/username`, `/platform-demo/dockerhub/token` | A read-only Docker Hub token | Kyverno (image signature verification), optional |

Everything else (the random client secrets between Dex, Argo CD, Backstage and Grafana, the session secret) is generated, not typed. The
database password is generated too, by RDS, and never passes through Terraform or the repositories ([the database](#the-database) below).

## Why by hand and not with Terraform

A `aws_ssm_parameter` resource puts the value into the Terraform state and into the plan output, and destroying the platform would delete
it. Created in the console, the value never touches Git or the state, and it survives every `terraform destroy`.

## Create a parameter (AWS console)

1. Systems Manager -> **Parameter Store** -> **Create parameter**. Region **us-east-1**.
2. **Name** the full path, for example `/platform-demo/github-oauth/client-secret`. **Tier**: Standard (free). **Type**: **SecureString**.
3. **KMS key source**: My current account, key `alias/aws/ssm` (the default, free).
4. **Value**: the secret. **Create parameter**. Repeat for each row.

## How the cluster gets them

`module.secrets_access` creates an IAM role, `<cluster>-external-secrets`, that may read **only** `/platform-demo/*` (and decrypt through
Systems Manager). The External Secrets Operator, installed through GitOps with its service account annotated with that role
(`terraform output external_secrets_role_arn`), turns the parameters into the Kubernetes Secrets the charts expect
(`sso/dex-secrets`, `backstage/backstage-secrets`).

The role's prefix is `secrets_parameter_prefix` in `platform.auto.tfvars` (`/platform-demo`). The GitHub OAuth App's callback URL is the HTTPS address
Dex is served on: **`https://dex.platform-demo.click/callback`** (see [the ALB and the Gateway](alb-and-gateway.md)).

## The database

Backstage's PostgreSQL is a Multi-AZ RDS instance that Terraform creates and destroys with the platform ([Architecture](architecture.md#database)).
Its connection details reach the cluster in two parts, so that nothing in the repositories has to know the generated host name and no password is ever in the state:

| What | Where | Type | Written by |
|---|---|---|---|
| host (the address only, no port) | `/platform-demo/rds/backstage/host` | Parameter Store, **String** | Terraform |
| port | `/platform-demo/rds/backstage/port` | String | Terraform |
| database name | `/platform-demo/rds/backstage/database` | String | Terraform |
| user name | `/platform-demo/rds/backstage/username` | String | Terraform |
| **password** | Secrets Manager secret `rds!db-...` (JSON keys `username` and `password`); its ARN is `terraform output database_secret_arn` | Secrets Manager, encrypted with the database's KMS key | **RDS** (`manage_master_user_password`) |

The first four are plain `aws_ssm_parameter` resources of type String under `<secrets_parameter_prefix>/rds/backstage` (the prefix is
`secrets_parameter_prefix` in `platform.auto.tfvars`). They are not secret, so having them in the state does no harm, and unlike the typed
SecureString parameters above they are removed with the platform and written again by the next one. The password exists only in Secrets
Manager.

**What the External Secrets role may read.** `module.secrets_access` adds, besides `/platform-demo/*` in Parameter Store, exactly two things, both
read-only: `secretsmanager:GetSecretValue` and `DescribeSecret` on **that one secret's ARN** (no wildcard, no listing of other secrets), and `kms:Decrypt` on the
database's KMS key, only when the request comes through Secrets Manager (`kms:ViaService`). The role's ARN is unchanged
(`terraform output external_secrets_role_arn`). In the Helm repository an `ExternalSecret` reads the four parameters (`ssm`) and the secret
(`secretsmanager`, `remoteRef.key` = the ARN from `terraform output database_secret_arn`, `property: password`).

**The password rotates.** RDS rotates a managed master password by itself, every 7 days, and keeps the same secret ARN with a new version. A
consumer that read the password once would break a week later, so the consumer has to pick it up again: External Secrets refreshes the
Kubernetes Secret on its `refreshInterval`, and a Reloader restarts the pods that mount it (both are set up in the Helm repository). Connections already open
keep working until they end; only new connections need the new password.

**Production.** The ephemeral environment destroys the database without a snapshot and without protection. A production environment sets, in its tfvars,
`database_deletion_protection = true` and `database_skip_final_snapshot = false`; the database then refuses `terraform destroy` until protection is
switched off in a separate, reviewed change. Cross-region replicas, Performance Insights and enhanced monitoring are left out of this test environment on purpose (inline
`#checkov:skip` with the reason, next to `aws_db_instance`).

**The pipeline's plan role** may not read Parameter Store values (it is read-only and any branch can run a plan), except the
`/platform-demo/rds/*` parameters, which hold no secret and which Terraform has to refresh. That exception is in `stacks/bootstrap`
(`github-oidc.tf`) and takes effect when `scripts/bootstrap.sh` is run again. The Secrets Manager values stay denied.
