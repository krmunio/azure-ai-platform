# AGENTS.md

이 저장소에서 작업하는 모든 에이전트/기여자를 위한 규칙.

## 브랜치 워크플로우 (필수)

`main`에 직접 커밋하지 않는다. 모든 변경 작업은 **별도의 브랜치**를 생성해서 진행하고,
완료 후 PR(또는 머지)로 `main`에 통합한다.

### 작업 시작 절차

```bash
git checkout main
git pull
git checkout -b <type>/<short-description>
```

### 브랜치 네이밍 규칙

형식: `<type>/<kebab-case-설명>`

- 모두 소문자, 단어는 하이픈(`-`)으로 구분(kebab-case)한다.
- 설명은 간결하게(권장 5단어 이내), 무엇을 하는지 알 수 있게 작성한다.
- 이슈 번호가 있으면 타입 뒤에 붙인다: `<type>/<issue>-<설명>` (예: `fix/123-login-redirect`).

| Type | 용도 | 예시 |
|------|------|------|
| `feature` | 새 기능 추가 | `feature/aks-gpu-node-pool` |
| `scenario` | 새 시나리오 추가/수정 | `scenario/rag-on-aks` |
| `fix` | 버그 수정 | `fix/terraform-validate-error` |
| `hotfix` | 긴급 수정 | `hotfix/broken-deploy-script` |
| `docs` | 문서 변경 | `docs/update-readme` |
| `refactor` | 동작 변경 없는 구조 개선 | `refactor/extract-network-module` |
| `chore` | 의존성/설정 등 기타 | `chore/bump-provider-version` |

## 실제 리소스명 하드코딩 금지 (필수)

> **이 규칙은 강제(MUST)다. 위반된 변경은 머지하지 않는다.**

문서·예시·스크립트·코드(Terraform 포함)에 **실제 환경의 구체적인 리소스명/식별자를 그대로 기입하지 않는다.**
대신 **중괄호 placeholder**(`{...명}`)나 변수로 일반화한다. 실제 식별자는 한 번 커밋되면
커밋 히스토리에 영구히 남아, 제거하려면 전체 히스토리 재작성(`git filter-repo`)과 모든 브랜치
force-push가 필요하다(공유 브랜치·PR에 영향). 따라서 **처음부터 넣지 않는 것**이 유일하게 안전한 방법이다.

### 금지 대상 식별자 (예시)
- ACR·스토리지·Key Vault 등 **리소스 이름** (예: `devacrxxxx` 같은 실제 명칭)
- **리소스 그룹·VNet·Subnet·Private Endpoint·NIC** 등 네트워크/그룹 이름
- **구독 ID·테넌트 ID·전체 리소스 ID 경로·객체 ID(principalId 등)**
- 실제 **사설/공인 IP**, FQDN 중 환경 고유 부분, 계정·조직 고유 식별자
- 비밀(키·토큰·암호·연결 문자열)은 당연히 절대 커밋하지 않는다.

### 권장 표기 (placeholder 컨벤션)
- 한글 placeholder: `{acr명}`, `{rg명}`, `{pe명}`, `{vnet명}`, `{subnet명}`, `{구독ID}`
- 또는 꺾쇠 표기: `<acr-name>`, `<resource-group>`, `<subscription-id>`
- Terraform·스크립트는 하드코딩 대신 **변수**(`var.*`)·환경변수·`*.tfvars.example`로 분리한다.

```bash
# ❌ 금지 — 실제 이름이 그대로 박힘
az acr show -n devacrxxxx -g dev-rg-xxxx

# ✅ 권장 — placeholder로 일반화
az acr show -n {acr명} -g {rg명}
```

### 커밋 전 자기 점검 (권장)
변경을 커밋하기 전, 스테이징된 diff에 실제 식별자가 섞이지 않았는지 확인한다.

```bash
# 실제 구독/리소스 ID 패턴 점검 (GUID, /subscriptions/ 경로 등)
git diff --cached | grep -nEi '/subscriptions/[0-9a-f-]{36}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
  && echo "⚠️ 실제 ID 의심 — placeholder로 치환 필요"
# 환경 고유 명명 패턴(조직 접두사 등)도 함께 점검한다.
```

> 이미 커밋·푸시된 실제 식별자를 발견하면, 새로 추가하지 않도록 즉시 placeholder로 치환하고,
> 히스토리 정리가 필요하면 `git filter-repo --replace-text` + 전 브랜치 force-push로 처리한다
> (백업 후 진행, 머지된 PR ref는 GitHub 지원 필요).
