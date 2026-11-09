# AWS 자격 증명 없이 기본 배포 스택과 공유 OIDC 신뢰 구성을 검증한다.
mock_provider "aws" {}

run "base_stack" {
  command = plan

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0 && length(aws_iam_role.github) == 0
    error_message = "The default stack must not create GitHub OIDC resources."
  }

  assert {
    condition = one([
      for statement in jsondecode(aws_iam_role_policy.ssm.policy).Statement :
      statement.Resource if contains(statement.Action, "ssm:UpdateInstanceInformation")
    ]) == "arn:aws:ec2:ap-southeast-2:983367475494:instance/i-0139ec3ffa95b74c4"
    error_message = "EC2 registration must be scoped to the deployment instance."
  }
}

run "reuse_oidc_provider" {
  command = plan

  variables {
    enable_github_oidc       = true
    github_oidc_provider_arn = "arn:aws:iam::983367475494:oidc-provider/token.actions.githubusercontent.com"
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 0
    error_message = "Do not manage the shared OIDC provider in this stack."
  }

  assert {
    condition = (
      jsondecode(aws_iam_role.github[0].assume_role_policy).Statement[0].Principal.Federated == var.github_oidc_provider_arn &&
      jsondecode(aws_iam_role.github[0].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:kitschcatch-App/kitschcatch-backend:environment:development-sydney"
    )
    error_message = "GitHub role trust must use the shared provider and Sydney deployment environment."
  }
}

run "explicitly_create_provider" {
  command = plan

  variables {
    enable_github_oidc          = true
    create_github_oidc_provider = true
  }

  assert {
    condition     = length(aws_iam_openid_connect_provider.github) == 1 && length(aws_iam_role.github) == 1
    error_message = "Explicit provider creation must configure both the provider and the deployment role."
  }
}
