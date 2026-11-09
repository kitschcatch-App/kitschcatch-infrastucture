terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {}
}

provider "aws" {
  region              = "ap-southeast-2"
  allowed_account_ids = [var.account_id]
}

variable "account_id" {
  type    = string
  default = "983367475494"
}
variable "instance_id" {
  type    = string
  default = "i-0139ec3ffa95b74c4"
}
variable "instance_role" {
  type    = string
  default = "kitschcatch-dev-kc-ec2-role"
}
variable "enable_github_oidc" {
  type    = bool
  default = false
}
variable "create_github_oidc_provider" {
  type    = bool
  default = false
}
variable "github_oidc_provider_arn" {
  type    = string
  default = null
  validation {
    condition     = var.github_oidc_provider_arn == null || var.github_oidc_provider_arn == "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
    error_message = "Use the GitHub Actions OIDC provider ARN in this deployment account."
  }
}
variable "github_subject" {
  type    = string
  default = "repo:kitschcatch-App/kitschcatch-backend:environment:development-sydney"
}

locals {
  artifact_prefix = "backend"
  oidc_host       = "token.actions.githubusercontent.com"
  instance_arn    = "arn:aws:ec2:ap-southeast-2:${var.account_id}:instance/${var.instance_id}"
  github_provider = var.github_oidc_provider_arn != null ? var.github_oidc_provider_arn : try(aws_iam_openid_connect_provider.github[0].arn, null)
}

resource "aws_s3_bucket" "releases" {
  bucket = "kitschcatch-dev-kc-releases-${var.account_id}"
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "releases" {
  bucket                  = aws_s3_bucket.releases.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "releases" {
  bucket = aws_s3_bucket.releases.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "releases" {
  bucket = aws_s3_bucket.releases.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "releases" {
  bucket     = aws_s3_bucket.releases.id
  depends_on = [aws_s3_bucket_versioning.releases]
  rule {
    id     = "expire-ci-artifacts"
    status = "Enabled"
    filter {
      prefix = "${local.artifact_prefix}/"
    }
    expiration {
      days = 30
    }
    noncurrent_version_expiration {
      noncurrent_days = 7
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 1
    }
  }
}

resource "aws_iam_role_policy" "ssm" {
  name = "kitschcatch-dev-kc-ssm-run-command"
  role = var.instance_role
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:UpdateInstanceInformation"]
        Resource = local.instance_arn
      },
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestedRegion" = "ap-southeast-2" }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "read_releases" {
  name = "kitschcatch-dev-kc-read-releases"
  role = var.instance_role
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:GetObjectVersion"]
      Resource = "${aws_s3_bucket.releases.arn}/${local.artifact_prefix}/*"
    }]
  })
}

resource "aws_ssm_document" "deploy" {
  name            = "KitschCatch-Dev-Sydney-Deploy"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Run the installed KitschCatch development deployment entry point."
    parameters = {
      operation = { type = "String", interpolationType = "ENV_VAR", allowedPattern = "^(start|status|confirm)$" }
      releaseId = { type = "String", interpolationType = "ENV_VAR", allowedPattern = "^[0-9a-f]{40}-[0-9]{1,20}-[0-9]{1,10}$" }
      manifestSha = {
        type = "String", interpolationType = "ENV_VAR", allowedPattern = "^([0-9a-f]{64}|none)$", default = "none"
      }
      mode = { type = "String", interpolationType = "ENV_VAR", allowedPattern = "^(preflight|deploy)$", default = "preflight" }
    }
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "deployment"
      inputs = {
        timeoutSeconds = "30"
        runCommand = [
          "set -eu",
          "exec /usr/bin/python3 /opt/kitschcatch/deploy/deploy.py \"$SSM_operation\" \"$SSM_releaseId\" \"$SSM_manifestSha\" \"$SSM_mode\""
        ]
      }
    }]
  })
}

resource "aws_iam_openid_connect_provider" "github" {
  count          = var.create_github_oidc_provider ? 1 : 0
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.github_oidc_provider_arn == null
      error_message = "Choose either an existing GitHub OIDC provider or a new one."
    }
  }
}

resource "aws_iam_role" "github" {
  count                = var.enable_github_oidc ? 1 : 0
  name                 = "kitschcatch-dev-kc-github-deploy"
  max_session_duration = 3600

  lifecycle {
    precondition {
      condition     = var.github_oidc_provider_arn != null || var.create_github_oidc_provider
      error_message = "Supply an existing provider ARN or explicitly enable provider creation."
    }
  }

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = local.github_provider }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = var.github_subject
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "deploy" {
  count = var.enable_github_oidc ? 1 : 0
  name  = "deploy-only-to-sydney-development"
  role  = aws_iam_role.github[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.releases.arn}/${local.artifact_prefix}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:SendCommand"]
        Resource = [aws_ssm_document.deploy.arn, local.instance_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetCommandInvocation", "elasticloadbalancing:DescribeTargetHealth"]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:RequestedRegion" = "ap-southeast-2" }
        }
      }
    ]
  })
}

output "deployment_role_arn" {
  value = try(aws_iam_role.github[0].arn, null)
}
output "artifact_bucket" {
  value = aws_s3_bucket.releases.id
}
output "ssm_document" {
  value = aws_ssm_document.deploy.name
}
