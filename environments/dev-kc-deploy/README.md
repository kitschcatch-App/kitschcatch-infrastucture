# 시드니 개발 EC2 배포 인프라

기존 시드니 개발 인스턴스를 대상으로 배포 전용 S3 버킷, SSM 명령 문서와 최소 권한, GitHub OIDC 역할을 구성한다. 기존 개발 스택과 state를 분리한다.

```sh
terraform init -backend-config=backend.hcl.example
terraform plan -out=sydney-deploy.tfplan
terraform apply sydney-deploy.tfplan
```

AWS 자격 증명의 계정이 시드니 개발 계정인지 확인하고, 계획에 기존 인스턴스·네트워크·DB 변경이나 삭제가 없는지 확인한다. OIDC 공급자가 이미 관리 중이면 해당 리소스를 이 state에 가져오기 전에 기존 state의 소유 관계를 확인한다. GitHub의 실제 OIDC subject 형식이 기본값과 다르면 `github_subject`를 지정한다.

`development-sydney` GitHub 환경은 `develop` 브랜치 배포만 허용한다. OIDC 역할은 이 환경의 토큰만 신뢰하고, 전용 버킷의 `backend/` 접두사와 지정 인스턴스·SSM 문서에만 명령을 보낸다. EC2 역할에는 배포 파일 읽기와 관리 노드 등록·메시지 채널 권한을 부여한다. SSM 에이전트가 `Online`이고 문서의 환경 변수 보간을 지원하는 버전인지 확인한다.

EC2에 백엔드 저장소의 `deploy/sydney/` 배포 프로그램과 systemd 서비스를 설치한 뒤 SSM의 `status` 호출로 연결을 확인한다. GitHub 환경의 `SYDNEY_DEPLOY_ROLE_ARN`에 Terraform 출력의 역할 ARN을 설정한다. 다른 환경 변수와 배포·복구 절차는 백엔드 운영 문서에서 관리한다. [백엔드 이슈 #111](https://github.com/kitschcatch-App/kitschcatch-backend/issues/111)

## 시드니 적용 상태

S3 버킷·버전 관리·공개 접근 차단·암호화·수명 주기, SSM 명령 문서, 기존 EC2 역할의 인라인 정책 두 개를 적용했다. 기존 개발 인스턴스·네트워크·DB 변경은 0개다.

AWS 조직 SCP가 `iam:CreateOpenIDConnectProvider`를 명시적으로 차단해 GitHub 역할은 생성하지 못했다. 조직에서 공급자 사용을 허용하기 전에는 아래 옵션으로 적용한 기반 리소스만 관리한다.

```sh
terraform plan -var enable_github_oidc=false
```
