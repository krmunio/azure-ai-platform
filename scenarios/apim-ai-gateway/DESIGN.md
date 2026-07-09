# APIM AI Gateway 기능/이점 검증 시나리오 설계

## 배경 / 목적

`AI Gateway.pdf`의 핵심 메시지는 **"AI Gateway는 사실 API Management(APIM)"** 이다.
지능형 앱이 늘어나면 다중 AI 모델 엔드포인트, 토큰 사용량 추적, 인증/권한, 토큰 기반 제약 등
**확장성·비용·보안·거버넌스** 문제가 생기고, APIM이 이를 게이트웨이 계층에서 해결한다.

이 시나리오는 그 주장을 **실제로 배포·검증**한다. APIM 앞단에 Azure OpenAI(Foundry)를 두고,
PDF가 제시한 대표 policy를 적용한 뒤, 각 기능의 **이점을 측정 가능한 형태**로 재현한다.

## 매핑: PDF 기능 → 이 시나리오 구현

| PDF 항목 | 구현 | 검증 이점 |
| --- | --- | --- |
| Keyless managed identities | APIM system-assigned MI + `Cognitive Services OpenAI User` 롤 + `authentication-managed-identity` policy | 키 없이 안전한 백엔드 인증 (보안) |
| 예시1: 토큰 제한 policy (TPM) | `azure-openai-token-limit` (counter-key = 구독 ID) | 초과 시 429 스로틀링 (비용/남용 제어) |
| 예시2: Load Balancer + Circuit Breaker | azapi backend 2개(circuit breaker) + load-balanced **Pool** | 부하/장애 하 가용성 (복원력) |
| 예시3: Semantic Caching policy | `azure-openai-semantic-cache-lookup/store` + Azure Managed Redis(RediSearch) | 유사 프롬프트 재사용 → 지연/비용↓ |
| Token usage metrics / logging | App Insights logger + `azure-openai-emit-token-metric` | 소비자별 토큰 관측성 |

## 범위

- 포함: RG, Azure OpenAI(1~2 리전) + 배포, APIM(v2) + MI + 롤, API/operation/policy,
  azapi backend + Pool + circuit breaker, (옵션) App Insights, (옵션) Managed Redis + 시맨틱 캐시
- 제외: Private Endpoint/VNet 통합, 커스텀 도메인, 다중 구독, CI 파이프라인 (YAGNI)
- 제외: 실제 리소스명/ID 하드코딩 — 전부 `name_prefix` + random suffix + 변수로 일반화

## 아키텍처

```
        Ocp-Apim-Subscription-Key                 Managed Identity (keyless)
Client ───────────────────────────▶  APIM  ──────────────────────────────▶ Azure OpenAI (primary)
                                     (StandardV2)   set-backend-service         └ chat / embeddings 배포
                                       │  policy: token-limit → emit-metric        ▲
                                       │          → semantic-cache → MI auth        │ load-balanced Pool
                                       └──────────────────────────────────────────▶ Azure OpenAI (secondary)
                                                                                    (circuit breaker per backend)
```

## Terraform 구성 (단일 평면 state)

`infra/`는 모듈 분리 없이 평면 구성이다. 무거운 부분은 토글 변수로 켠다.

- **azurerm**: RG, `azurerm_cognitive_account`/`_deployment`, `azurerm_api_management`(+MI),
  `azurerm_role_assignment`, API/operation/policy, App Insights/logger/diagnostic,
  Redis Enterprise + `azurerm_api_management_redis_cache`
- **azapi**: `Microsoft.ApiManagement/service/backends` — circuit breaker 규칙과 **Pool** 타입은
  azurerm에서 안정적으로 표현되지 않아 azapi로 직접 관리
- **random**: 전역 고유 이름 suffix

### 토글 변수
- `enable_load_balancing` (default true) — secondary OpenAI + Pool + circuit breaker
- `enable_semantic_cache` (default false) — Managed Redis + 임베딩 배포 + 캐시 policy (비용/시간↑)
- `enable_observability` (default true) — App Insights + `emit-token-metric`

### policy 조립
`policies/ai-gateway.xml.tftpl`을 `templatefile()`로 렌더링한다. 토글에 따라 emit-metric·
semantic-cache 조각을 포함/제외하고, `set-backend-service`의 backend-id를 Pool 또는 단일 backend로 바꾼다.

## 라우팅 규칙

- API `path = "openai"`, 단일 catch-all operation `POST /{*path}`
- backend url = `${account.endpoint}openai` → 클라이언트가 `/openai/deployments/<dep>/chat/completions`를
  호출하면 접미사 이후 경로가 backend url에 이어 붙어 `.../openai/deployments/...`로 전달된다.
- upstream 인증은 policy의 관리 ID 토큰으로 처리(키 미사용).

## 검증 (`tests/run-scenarios.sh`)

APIM 구독 키로 프록시를 호출해 4가지를 측정한다: ① keyless 200, ② TPM 초과 429 + ratelimit 헤더,
③ 부하 하 성공률(Pool 복원력), ④ 유사 프롬프트 2회차 지연 급감(semantic cache).
엔드포인트/키는 환경변수로만 받는다(실명 커밋 방지).

## 정적 검증

- `terraform fmt -check`, `terraform validate` (apply는 실제 구독 필요 → 사용자 환경에서 수행)

## 비범위 (YAGNI)

- 원격 state backend, 멀티 workspace/environment
- Private networking, 커스텀 도메인/인증서
- API Center·Developer Portal 커스터마이즈, MCP 변환(예시 14p) — 후속 시나리오 후보
