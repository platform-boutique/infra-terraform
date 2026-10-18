# How the pipeline gets into AWS: GitHub's OIDC identity provider and two roles, so no access key is stored anywhere.
#
#   plan   read-only on the account, plus write access to the state lock and to plans/ in the state bucket. Any job of this repository's
#          branches (and pull requests) may assume it: a plan changes nothing.
#   apply  administrator. Only a job that runs in one of the GitHub environments listed in github_apply_environments may assume it, and
#          those environments need a reviewer's approval and deploy only from main. This is the gate.
#
# Terraform builds IAM, EKS, VPC, KMS, ACM, Route 53 and a load balancer, so a narrower apply role would be a long policy that breaks with
# every new resource type; the protection is who may assume it, not what it may do.

locals {
  github_issuer = "token.actions.githubusercontent.com"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.github_issuer}"
  client_id_list = ["sts.amazonaws.com"]
}

# --- plan -------------------------------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.github_issuer}:sub"
      values = [
        "${var.github_subject_prefix}:ref:refs/heads/*",
        "${var.github_subject_prefix}:pull_request",
      ]
    }
  }
}

data "aws_iam_policy_document" "plan" {
  statement {
    sid       = "ListStateBucket"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  # Terraform locks a state by writing <key>.tflock next to it; saved plans live under plans/.
  statement {
    sid       = "LockStateAndSavePlans"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${aws_s3_bucket.state.arn}/*.tflock", "${aws_s3_bucket.state.arn}/plans/*"]
  }

  statement {
    sid       = "UseStateKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [aws_kms_key.state.arn]
  }

  # ReadOnlyAccess can read secret values. A plan has no reason to, and any branch of the repository can run one.
  statement {
    sid       = "NeverReadSecretValues"
    effect    = "Deny"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath", "secretsmanager:GetSecretValue"]
    resources = ["*"]
  }
}

resource "aws_iam_role" "plan" {
  name               = "${var.name}-github-plan"
  description        = "Terraform plan jobs of ${var.github_repository}: read-only, plus the state lock and saved plans"
  assume_role_policy = data.aws_iam_policy_document.plan_trust.json
}

resource "aws_iam_role_policy_attachment" "plan_read_only" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy" "plan" {
  name   = "state-bucket"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

# --- apply ------------------------------------------------------------------------------------------------------------------------
data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_issuer}:sub"
      values   = [for e in var.github_apply_environments : "${var.github_subject_prefix}:environment:${e}"]
    }
  }
}

resource "aws_iam_role" "apply" {
  name               = "${var.name}-github-apply"
  description        = "Terraform apply and destroy jobs of ${var.github_repository} that a reviewer approved"
  assume_role_policy = data.aws_iam_policy_document.apply_trust.json
}

resource "aws_iam_role_policy_attachment" "apply_admin" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AdministratorAccess"
}
