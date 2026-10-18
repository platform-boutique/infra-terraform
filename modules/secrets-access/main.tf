# Read-only access for the External Secrets Operator to the platform's secrets in Systems Manager Parameter Store.
#
# The secrets that cannot be generated (the GitHub OAuth App's client ID and secret, a GitHub token, a Docker Hub token) are typed into the
# AWS console ONCE as SecureString parameters under var.parameter_prefix. They are not Terraform resources on purpose: their values would
# end up in the state, and a destroyed platform would destroy them. The operator copies them into Kubernetes Secrets on every new cluster.

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
