# Read-only access for the External Secrets Operator to the platform's secrets in Systems Manager Parameter Store.
#
# The secrets that cannot be generated (the GitHub OAuth App's client ID and secret, a GitHub token, a Docker Hub token) are typed into the
# AWS console ONCE as SecureString parameters under var.parameter_prefix. They are not Terraform resources on purpose: their values would
# end up in the state, and a destroyed platform would destroy them. The operator copies them into Kubernetes Secrets on every new cluster.
#
# Besides that, the role can read named Secrets Manager secrets that Terraform-made resources keep by themselves (var.secret_arns, with
# the keys that encrypt them in var.secret_kms_key_arns): today the RDS master user secret of modules/database. Read-only, exact ARNs.

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  parameter_arn_base = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${var.parameter_prefix}"
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:sub"
      values   = ["system:serviceaccount:${var.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "read_secrets" {
  statement {
    sid = "ReadPlatformParameters"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [
      local.parameter_arn_base,
      "${local.parameter_arn_base}/*",
    ]
  }

  # Decrypting a SecureString: only through Systems Manager, so the role cannot use any key for anything else.
  statement {
    sid       = "DecryptThroughSsmOnly"
    actions   = ["kms:Decrypt"]
    resources = ["arn:${data.aws_partition.current.partition}:kms:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:key/*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${data.aws_region.current.region}.amazonaws.com"]
    }
  }

  # Secrets Manager secrets that Terraform-made resources keep by themselves (the RDS master user secret): read-only, on the exact ARNs.
  # Reading is limited to those ARNs, so the role cannot read any other secret.
  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []

    content {
      sid = "ReadNamedSecrets"
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      resources = var.secret_arns
    }
  }

  # The RDS secret is named `rds!db-<random id>` and the id changes with every new database, so the External Secrets Operator FINDS it by
  # name (ListSecrets) instead of having the id written into Git. ListSecrets cannot be limited to a resource; it returns names, not values.
  dynamic "statement" {
    for_each = length(var.secret_arns) > 0 ? [1] : []

    content {
      sid       = "FindNamedSecrets"
      actions   = ["secretsmanager:ListSecrets"]
      resources = ["*"]
    }
  }

  # Those secrets are encrypted with customer-managed keys: decrypt with exactly those keys, and only through Secrets Manager.
  dynamic "statement" {
    for_each = length(var.secret_kms_key_arns) > 0 ? [1] : []

    content {
      sid       = "DecryptNamedSecretsThroughSecretsManagerOnly"
      actions   = ["kms:Decrypt"]
      resources = var.secret_kms_key_arns

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["secretsmanager.${data.aws_region.current.region}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  name               = "${var.name}-external-secrets"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "read_secrets" {
  name   = "read-platform-parameters"
  role   = aws_iam_role.external_secrets.id
  policy = data.aws_iam_policy_document.read_secrets.json
}
