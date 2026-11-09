# 시드니 개발 EC2 배포 인프라

기존 시드니 개발 인스턴스를 대상으로 배포 전용 S3 버킷, SSM 명령 문서와 최소 권한, GitHub OIDC 역할을 구성한다. 기존 개발 스택과 state를 분리한다.

```sh
terraform init -backend-config=backend.hcl.example
terraform plan -out=sydney-deploy.tfplan
terraform apply sydney-deploy.tfplan
```

AWS 자격 증명의 계정이 시드니 개발 계정인지 확인하고 계획의 변경 범위를 검토한다. 기본 계획은 S3와 SSM 기반만 관리한다.

조직에서 OIDC를 허용하면 `enable_github_oidc=true`로 배포 역할을 구성한다. 계정에 공유 GitHub OIDC 공급자가 이미 있다면 `github_oidc_provider_arn`에 ARN을 지정해 참조한다. 공급자가 없는 계정에서는 `create_github_oidc_provider=true`를 명시해 생성한다. 두 설정 중 하나를 선택한다. 이 스택이 생성한 공급자는 삭제 방지 설정을 유지하며, 배포 역할을 끌 때는 공급자 생성 설정을 유지한다. GitHub의 실제 OIDC subject 형식이 기본값과 다르면 `github_subject`를 지정한다.

`development-sydney` GitHub 환경은 `develop` 브랜치 배포만 허용한다. OIDC 역할은 이 환경의 토큰만 신뢰하고, 전용 버킷의 `backend/` 접두사와 지정 인스턴스·SSM 문서에만 명령을 보낸다. EC2 역할에는 배포 파일 읽기, 지정 인스턴스의 SSM 상태 갱신, 시드니 리전의 메시지 채널 권한을 부여한다. SSM 에이전트가 `Online`이고 문서의 환경 변수 보간을 지원하는 버전인지 확인한다.

EC2에 백엔드 저장소의 `deploy/sydney/` 배포 프로그램과 systemd 서비스를 설치한 뒤 SSM의 `status` 호출로 연결을 확인한다. GitHub 환경의 `SYDNEY_DEPLOY_ROLE_ARN`에 Terraform 출력의 역할 ARN을 설정한다. 다른 환경 변수와 배포·복구 절차는 백엔드 운영 문서에서 관리한다. [백엔드 이슈 #111](https://github.com/kitschcatch-App/kitschcatch-backend/issues/111)

## 시드니 적용 상태

S3 버킷·버전 관리·공개 접근 차단·암호화·수명 주기, SSM 명령 문서, 기존 EC2 역할의 인라인 정책 두 개를 적용했다. 기존 개발 인스턴스·네트워크·DB 변경은 0개다.

AWS 조직 SCP가 `iam:CreateOpenIDConnectProvider`를 명시적으로 차단해 GitHub 역할은 생성하지 못했다. IAM 정책 평가에서도 EC2 역할의 `ssm:UpdateInstanceInformation`이 조직 정책에 의해 `explicitDeny`였다. 에이전트가 관리 노드로 등록되지 않아 Run Command가 `InvalidInstanceId`를 반환한다. 두 조직 제한이 해결될 때까지 기본 설정으로 적용한 기반 리소스를 관리한다.

PR에서는 AWS 자격 증명 없이 `terraform fmt -check -recursive`, `init -backend=false`, `validate`, 모의 공급자를 이용한 `terraform test`를 실행한다.
