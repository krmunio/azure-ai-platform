# APIM AI Gateway 기능/이점 검증 — 테스트 결과보고서

- **일시**: 2026-07-09 15:26:51 ~ 15:29:44 (KST)
- **대상 게이트웨이**: `https://<apim>.azure-api.net` (APIM AI Gateway)
- **러너**: [`run-scenarios.sh`](./run-scenarios.sh)
- **원본 로그**: `aigw-test-20260709-152651.log`
- **종합 결과**: **PASS 2 / FAIL 1 / SKIP 1**

## 요약

| # | 항목 | 결과 | 근거 |
|---|------|------|------|
| 1 | Keyless 연결 (Managed Identity → Azure OpenAI) | ✅ PASS | 프록시 경유 chat completion 200, 키 미사용 |
| 2 | 토큰 제한 policy (TPM 초과 시 429) | ✅ PASS | 요청 #17에서 429 + `Retry-After: 24`, `x-ratelimit-remaining-tokens` 헤더 관측 |
| 3 | 로드밸런싱 + 서킷브레이커 (Pool 백엔드) | ❌ FAIL | 12회 중 정상 처리(200/429) 7회 (기준 9회 미달) |
| 4 | 시맨틱 캐싱 (유사 프롬프트 2회차 지연) | ⚠️ SKIP | 1회차 401·2회차 200으로 비교 불가, 지연 오히려 증가 |

## 상세

### [1] Keyless 연결 — PASS
APIM Managed Identity로 Azure OpenAI를 키 없이 호출, 200 반환. 키리스 인증/롤 전파 정상.

### [2] 토큰 제한(TPM) — PASS
연속 호출 중 17번째 요청에서 429 스로틀링 발생(`Retry-After: 24s`). `x-ratelimit-remaining-tokens` 헤더도 관측되어 비용/남용 제어 이점 확인.

### [3] 로드밸런싱/복원력 — FAIL ⚠️
부하 하 12회 중 게이트웨이 정상 처리(200/429)가 **7회에 그침**(합격 기준 75% = 9회). 나머지는 다른 상태코드로 실패 추정.
- **점검 필요**: Pool 백엔드 상태, circuit breaker 개방 여부, 백엔드 quota, 5xx 응답 원인.
- **참고**: [2]에서 TPM 창을 소진한 뒤 61초 대기했으나 창이 완전히 회복되지 않았을 가능성 → 대기 시간 상향 또는 별도 TPM으로 격리 후 재측정 권장.

### [4] 시맨틱 캐싱 — SKIP
1회차 `code=401`(인증 실패)로 캐시 저장 자체가 안 되어 2회차와 비교 불가. 2회차는 200이나 지연이 오히려 증가(0.28s→1.10s).
- **점검 필요**: `enable_semantic_cache=true`(Redis) 설정 여부, 유사도 임계값, 1회차 401 원인(간헐 토큰 전파 지연 추정).

## 조치 권고

1. **[3] 우선 조사**: 실패 응답의 실제 상태코드/본문 로깅 추가 후 circuit breaker·backend health 확인.
2. **[4] 재현성 확보**: 시맨틱 캐시 활성화 확인 및 1회차 401 제거 후 재측정.
3. **테스트 안정화**: TPM 소진 후 회복 대기(현재 61초)를 실제 `tokens_per_minute` 창(60s+여유)에 맞춰 상향.
