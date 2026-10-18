# Secrets in Parameter Store

What a person has to type once, and where it lives so that a rebuilt cluster does not ask again.

| Parameter (SecureString) | What | Needed by |
|---|---|---|
| `/platform-demo/github-oauth/client-id` | Client ID of the GitHub OAuth App | Dex (GitHub sign-in) |
| `/platform-demo/github-oauth/client-secret` | Client secret of that OAuth App | Dex |
| `/platform-demo/github/token` | A GitHub token that can read the organisation's repositories | Backstage (catalog discovery, releases view) |
| `/platform-demo/dockerhub/username`, `/platform-demo/dockerhub/token` | A read-only Docker Hub token | Kyverno (image signature verification), optional |

Everything else (the random client secrets between Dex, Argo CD, Backstage and Grafana, the Postgres password, the session secret) is
generated, not typed.

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

The role's prefix is `secrets_parameter_prefix` (default `/platform-demo`). The GitHub OAuth App's callback URL must be the HTTPS address
Dex is served on: that needs a domain and a certificate, see [the ALB and the Gateway](alb-and-gateway.md).
