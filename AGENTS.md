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
