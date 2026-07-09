# APIM AI Gateway 기능/이점 검증 시나리오

*이 문서의 [English 버전](./README.en.md).*

`AI Gateway.pdf`의 핵심 **"AI Gateway == Azure API Management(APIM)"** 를 실제로 배포·검증하는
시나리오다. APIM 앞단에 Azure OpenAI(Foundry)를 두고, PDF가 소개한 대표 policy(토큰 제한,
로드밸런싱+서킷브레이커, 시맨틱 캐싱)와 Keyless/관측성을 적용한 뒤 각 **이점을 측정**한다.

- 설계: [`DESIGN.md`](./DESIGN.md)
- 구현 계획: [`PLAN.md`](./PLAN.md)
- 인프라 코드: [`infra/`](./infra/) (Terraform, 단일 평면 state)
- 검증 스크립트: [`tests/run-scenarios.sh`](./tests/run-scenarios.sh)

## AI Gateway 기능 → 이점 매핑

| 기능 | policy / 리소스 | 검증 이점 |
| --- | --- | --- |
| Keyless (Managed Identity) | APIM MI + `Cognitive Services OpenAI User` 롤 + `authentication-managed-identity` | 키 없이 안전한 백엔드 인증 |
| 토큰 제한 (TPM) | `azure-openai-token-limit` | 초과 시 429 스로틀링 → 비용/남용 제어 |
| 로드밸런싱 + 서킷브레이커 | azapi backend Pool + circuit breaker | 부하/장애 하 가용성 → 복원력 |
| 시맨틱 캐싱 (옵션) | `azure-openai-semantic-cache-*` + Managed Redis | 유사 프롬프트 재사용 → 지연/비용↓ |
| 토큰 메트릭/로깅 | App Insights + `azure-openai-emit-token-metric` | 소비자별 관측성 |

## 배포되는 리소스

| 리소스 | 조건 | 비고 |
| --- | --- | --- |
| Resource Group | 항상 | `koreacentral` 기본 |
| Azure OpenAI (primary) + chat 배포 | 항상 | `gpt-4o-mini` 기본 |
| Azure OpenAI (secondary) + chat 배포 | `enable_load_balancing=true` | secondary 리전 |
| API Management (StandardV2) + System MI | 항상 | AI Gateway 게이트웨이 |
| Role assignment (OpenAI User) | 항상(+secondary) | keyless |
| azapi backend + Pool + circuit breaker | LB 시 Pool, 아니면 단일 | `Microsoft.ApiManagement/service/backends` |
| APIM API / operation / policy | 항상 | `path=openai`, catch-all `POST /{*path}` |
| App Insights + logger + diagnostic | `enable_observability=true` | 토큰 메트릭/로깅 |
| Managed Redis(RediSearch) + APIM cache + 임베딩 배포 | `enable_semantic_cache=true` | 시맨틱 캐시 |

## 사전 요구사항

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- 인증된 Azure CLI (`az login`)
- 구독에 Azure OpenAI 및 사용 모델(예: `gpt-4o-mini`) 배포 쿼터
- APIM v2 및 (옵션) Redis Enterprise 생성 권한

> **참고**: APIM(v2) 프로비저닝은 수십 분, Redis Enterprise도 시간이 걸린다. 첫 배포는 여유를 둔다.

## 배포 절차

```bash
cd scenarios/apim-ai-gateway/infra
cp terraform.tfvars.example terraform.tfvars   # 필요 시 값 조정
terraform init
terraform plan
terraform apply
```

주요 출력값:

```bash
terraform output apim_gateway_url        # https://<apim>.azure-api.net
terraform output openai_proxy_base_url   # <gateway>/openai
terraform output chat_deployment_name
terraform output openai_api_version
```

## 검증 절차

APIM 구독 키가 필요하다(포털 **APIM > Subscriptions**의 built-in "Unlimited" 또는 신규 구독 키).
실제 값은 코드에 넣지 말고 환경변수로만 전달한다.

```bash
cd scenarios/apim-ai-gateway/tests

export APIM_GATEWAY_URL="$(terraform -chdir=../infra output -raw apim_gateway_url)"
export APIM_SUBSCRIPTION_KEY="<apim-subscription-key>"   # 포털에서 발급
export CHAT_DEPLOYMENT="$(terraform -chdir=../infra output -raw chat_deployment_name)"
export OPENAI_API_VERSION="$(terraform -chdir=../infra output -raw openai_api_version)"

./run-scenarios.sh
```

검증 항목:

1. **Keyless 연결** — MI로 Azure OpenAI 호출(키 없이) 200
2. **토큰 제한** — 연속 호출 시 429 + `x-ratelimit-remaining-tokens` 헤더
3. **로드밸런싱/복원력** — 부하 하 성공률 유지(Pool + circuit breaker)
4. **시맨틱 캐싱**(옵션) — 유사 프롬프트 2회차 지연 급감

> 예시2·3의 효과를 뚜렷이 보려면 `tokens_per_minute`를 낮추고(예: 200),
> `chat_capacity`를 작게(예: 1) 두어 스로틀링/페일오버를 유도한다.
> 시맨틱 캐싱은 `enable_semantic_cache=true`로 배포해야 동작한다.

## 이점을 눈으로 확인하기 (선택)

- **토큰 메트릭**: App Insights > Metrics > 네임스페이스 `ai-gateway`의 토큰 카운트(소비자 차원별).
- **프롬프트/응답 로깅**: APIM diagnostic가 App Insights로 요청을 로깅.
- **circuit breaker**: 한 backend가 429/5xx를 반복하면 `tripDuration` 동안 제외되고 Pool의 다른 backend로 라우팅.

## 정리(삭제)

```bash
cd scenarios/apim-ai-gateway/infra
terraform destroy
```

> APIM(v2)·Redis Enterprise 삭제에도 시간이 걸릴 수 있다.

## 규칙 준수 메모

- 문서/코드/스크립트에 **실제 리소스명·구독/테넌트 ID·키를 하드코딩하지 않는다**
  (전부 `name_prefix`+random suffix+변수, 테스트는 환경변수).
- `main` 직접 커밋 금지 — 이 시나리오는 `scenario/apim-ai-gateway` 브랜치에서 작업한다.
