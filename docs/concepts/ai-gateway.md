# AI Gateway

LLM/AI API(예: Azure OpenAI) **앞단에 두는 관리·제어 계층**. 클라이언트와 모델 사이에서
**인증·트래픽 제어·비용 관리·관측성·안전성**을 한 곳에서 강제한다.
파사드([facade-pattern](./facade-pattern.md))처럼 여러 백엔드 모델을 **단일 진입점**으로 감싼다.

> 이 repo에서는 **"AI Gateway == Azure API Management(APIM)"** 로 보고 실제 배포·검증한다.
> → 시나리오: [`scenarios/apim-ai-gateway`](../../scenarios/apim-ai-gateway/)

## 왜 필요한가

직접 앱 → 모델로 붙이면 각 앱마다 키·재시도·비용통제·로깅을 중복 구현해야 한다.
AI Gateway가 이 공통 관심사를 **중앙에서** 처리한다.

## 핵심 기능 → 이점

| 기능 | 설명 | 이점 |
| --- | --- | --- |
| **Keyless 인증** | Managed Identity로 백엔드(모델) 호출 | 키 하드코딩 제거, 안전 |
| **토큰 제한(TPM)** | 소비자별 토큰/분 제한, 초과 시 429 | 비용·남용 제어 |
| **로드밸런싱 + 서킷브레이커** | 여러 모델 엔드포인트 분산·장애 격리 | 가용성·복원력 |
| **시맨틱 캐싱** | 유사 프롬프트 응답 재사용(벡터 유사도) | 지연·비용↓ |
| **토큰 메트릭/로깅** | 소비자별 토큰 소비 관측 | 과금·모니터링 |
| **콘텐츠 안전** | 유해 입출력 필터 | 안전·규정 대응 |

## 구조

```
클라이언트 앱들
     │
     ▼
[ AI Gateway (APIM) ]  ── 인증·TPM·캐싱·로깅·라우팅 정책
     │            │
     ▼            ▼
Azure OpenAI    Azure OpenAI   (primary / secondary … 풀 + 서킷브레이커)
```

## Azure 구현

- **API Management (APIM)** 를 게이트웨이로, 대표 policy 적용:
  - `azure-openai-token-limit` (토큰 제한)
  - azapi backend Pool + circuit breaker (LB/복원력)
  - `azure-openai-semantic-cache-*` + Managed Redis (시맨틱 캐싱)
  - `authentication-managed-identity` (Keyless)
  - App Insights + `azure-openai-emit-token-metric` (관측성)
- 상세 배포·검증: [`scenarios/apim-ai-gateway`](../../scenarios/apim-ai-gateway/) 참고.

## 국내 의료 맥락 ⚠️

- 게이트웨이 로그/프롬프트에 **PHI(실명·민감정보) 유입** 주의 → 마스킹·최소 로깅
- APIM·OpenAI 모두 **국내 리전 고정**, 공공/의료면 **CSAP 범위** 확인
  ([korea-medical-data-cloud 가이드](../compliance/korea-medical-data-cloud/) 참고)
- RAG/추론에 쓰는 데이터는 **가명처리** 후 사용, 프롬프트·응답 로그의 재식별 위험 점검

## 혼동 주의

- **API Gateway**: 일반 API 라우팅·인증 / **AI Gateway**: 여기에 **토큰·시맨틱 캐싱·모델 풀 등
  LLM 특화 제어**를 더한 것 (구현은 같은 APIM일 수 있음).
