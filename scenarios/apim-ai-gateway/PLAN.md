# APIM AI Gateway 시나리오 구현 계획

`AI Gateway.pdf` → APIM AI Gateway 기능을 배포·검증하는 시나리오 구현 계획.

## 산출물

```
scenarios/apim-ai-gateway/
  DESIGN.md  PLAN.md  README.md  README.en.md
  infra/
    providers.tf  variables.tf  main.tf  outputs.tf
    terraform.tfvars.example  .gitignore
    policies/ai-gateway.xml.tftpl
  tests/run-scenarios.sh
```

## 단계

1. **브랜치**: `scenario/apim-ai-gateway` (main 직접 커밋 금지)
2. **인프라 코어**: RG → Azure OpenAI(primary/secondary) + 배포 → APIM(v2)+MI → 롤 부여
3. **AI Gateway 기능**:
   - azapi backend(circuit breaker) + load-balanced Pool
   - App Insights + logger + diagnostic (관측성)
   - Managed Redis + apim redis cache (semantic cache, 옵션)
   - API + catch-all operation + `templatefile` policy(token-limit / emit-metric / semantic-cache / MI auth / set-backend-service)
4. **검증 스크립트**: keyless / TPM 429 / LB 성공률 / 캐시 지연
5. **문서**: DESIGN/PLAN/README/README.en + 최상위 README 인덱스 갱신
6. **정적 검증**: `terraform fmt` + `terraform validate`
7. **커밋 / PR**

## 결정 사항

- IaC: **Terraform**(acr 시나리오와 동일 스택). backend Pool/circuit breaker는 **azapi**로 관리.
- APIM SKU 기본 `StandardV2_1` (AI Gateway policy는 Consumption 외 전 tier 지원).
- 무거운 리소스(secondary OpenAI, Redis, App Insights)는 **토글 변수**로 on/off.
- 실제 리소스명/ID 미하드코딩 — `name_prefix` + random suffix + 변수.

## 검증 상태

- [x] 브랜치 생성
- [x] infra(providers/variables/main/outputs/tfvars.example/.gitignore) 작성
- [x] policy 템플릿 작성
- [x] tests/run-scenarios.sh 작성 (bash -n 통과)
- [x] `terraform fmt` / `terraform validate` 통과
- [x] 문서 작성 + 최상위 README 인덱스 갱신
- [ ] 실제 `terraform apply` 검증 — 사용자 구독에서 수행

## 후속 후보 (YAGNI로 제외)

- Private Endpoint/VNet 통합, 커스텀 도메인
- REST → MCP 도구 변환(PDF 14p), API Center 레지스트리, Developer Portal
