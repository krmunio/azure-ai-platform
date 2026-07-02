# Synthea 대량 적재 결과 보고서

Synthea로 생성한 합성 환자 FHIR 번들을 Azure Health Data Services **FHIR service**에 적재한 결과입니다.
모든 식별자(엔드포인트/리소스명/GUID)는 placeholder로 위생처리했습니다.

## 1. 환경

| 항목 | 값 |
|------|-----|
| FHIR 엔드포인트 | `https://{workspace}-{fhir}.fhir.azurehealthcareapis.com` |
| FHIR 버전 | R4 (4.0.1) |
| 리전 | Korea Central |
| 데이터 생성 도구 | Synthea (portable JRE 17, aarch64) |
| 적재 스크립트 | `tests/load-synthea.sh` (transaction Bundle → base URL POST) |

## 2. 생성 데이터

- 환자 15명 요청 → 사망 포함 총 17명, FHIR 번들 **19개** 생성
- 참조 대상 번들 2개: `hospitalInformation*.json`, `practitionerInformation*.json`
- 환자 번들 17개 (entry 수 220 ~ 14,282)

## 3. 적재 결과

| 지표 | 값 |
|------|-----|
| 대상 번들 | 19 |
| 성공(OK) | **7** |
| 실패(ERR) | **12** |
| 소요 시간 | 약 43초 |

### 3.1 리소스 카운트 (before → after)

`GET /{type}?_summary=count` 기준. before는 기능 테스트 시 적재된 1개 환자 데이터를 포함한 상태.

| 리소스 | before | after | 증가 |
|--------|-------:|------:|----:|
| Patient | 1 | 6 | +5 |
| Observation | 62 | 763 | +701 |
| Encounter | 13 | 112 | +99 |
| Condition | 14 | 85 | +71 |
| Immunization | 0 | 121 | +121 |
| Procedure | 0 | 292 | +292 |
| MedicationRequest | 0 | 19 | +19 |
| DiagnosticReport | 0 | 154 | +154 |
| Organization | 0 | 65 | +65 |
| Practitioner | 0 | 65 | +65 |

## 4. 주요 발견

### 4.1 참조 무결성 — 적재 순서 (해결됨)
환자 번들은 `Organization/{id}`, `Practitioner/{id}` 를 참조하며, 이 리소스는
`hospitalInformation*` / `practitionerInformation*` 번들에 정의된다. glob 기본 순서는
대문자 환자 파일을 먼저 처리하여 **참조 미해결 400** 을 유발했다.
→ `load-synthea.sh` 가 참조 대상 번들을 **선적재**하도록 수정하여 해결.

### 4.2 트랜잭션 번들 500-entry 제한 (남은 실패 원인)
Azure FHIR service의 transaction Bundle은 **entry 500개** 제한이 있다. 적재 결과가
이 경계와 정확히 일치한다.

| entry 수 | 결과 |
|---------:|------|
| 130 ~ 485 | OK (9/9) |
| 578 ~ 14,282 | ERR 400 (10/10) |

- ≤485 entry 번들 전부 성공, ≥578 entry 번들 전부 실패 → 원인이 데이터가 아니라 **번들 크기**임을 확증.
- 대규모 적재에는 transaction Bundle 대신 **`$import`(bulk import)** 사용을 권장(로더 주석에 명시).

## 5. Azure 플랫폼 모니터링 지표

적재 구간(`az monitor metrics list`, PT5M) 관측값. 지표는 수집 지연이 있어 적재 직후 수 분 후 반영됨.

| 지표 | 관측값 |
|------|--------|
| TotalRequests | 적재 피크 구간 최대 **~2,096 req/5분** |
| TotalLatency (avg) | **1,311 ~ 3,928 ms** (대형 번들 처리 시 상승) |
| TotalDataSize | 약 **225 MB** |
| Availability | **100%** |
| TotalErrors | 빈 값 (400은 요청 오류로 5xx 서버 오류 지표에 미집계) |

> 참고: 400(client error)은 `TotalErrors`(서버측 오류) 지표에 집계되지 않는다.
> 클라이언트 오류 추적은 진단 로그(Log Analytics, 본 범위 외)로 확인 가능.

## 6. 재현 방법

```bash
# 1) Synthea로 합성 데이터 생성 (예: 15명)
java -jar synthea.jar -p 15

# 2) 참조 대상 선적재 로직이 포함된 로더로 적재
export FHIR_URL="https://{workspace}-{fhir}.fhir.azurehealthcareapis.com"
bash tests/load-synthea.sh ./output/fhir

# 3) 카운트 검증
curl -sS -H "Authorization: Bearer $TOKEN" "$FHIR_URL/Patient?_summary=count"
```

## 7. 결론

- 적재 파이프라인 정상 동작 확인(참조 대상 선적재 후 소형~중형 번들 100% 성공).
- Azure FHIR transaction Bundle **500-entry 제한**을 실측으로 확인, 대규모 적재는 `$import` 권장.
- 서비스 가용성 100%, 지표 수집 정상. 결과는 검증 완료 상태.
