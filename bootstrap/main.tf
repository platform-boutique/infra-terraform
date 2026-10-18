# Remote state for every other stack in this repository. Run once, with local state (the bucket cannot hold its own state):
# the state of this tiny stack is a single bucket and can be re-imported if the local file is lost.

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "platform-demo"
      ManagedBy = "terraform"
      Stack     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  bucket_name = "${var.name}-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

resource "aws_s3_bucket" "state" {
  #checkov:skip=CKV_AWS_18:Access logging needs another bucket; the state bucket is private, versioned and used by one account.
  #checkov:skip=CKV_AWS_144:Cross-region replication is not worth its cost for the state of a test environment; versioning protects against overwrites.
  #checkov:skip=CKV2_AWS_62:No consumer of bucket events.
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# State holds secrets (generated passwords, certificate material): encrypt it with a customer-managed key that rotates every year.
# The key policy says what the default one says (the account's IAM policies decide who may use the key), written out so it is reviewable.
data "aws_iam_policy_document" "state_key" {
  #checkov:skip=CKV_AWS_109:This is the standard KMS key policy: the account root delegates to IAM, which decides who may use the key. It is not a grant to anyone.
  #checkov:skip=CKV_AWS_111:Same: the standard delegating key policy.
  #checkov:skip=CKV_AWS_356:A key policy's Resource is always "*" (the key itself).
  statement {
    sid       = "EnableIAMPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "state" {
  description             = "Terraform state of ${var.name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.state_key.json
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.name}-tfstate"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}
