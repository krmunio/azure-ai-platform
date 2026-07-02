# Azure FHIR Service 기능 검증 시나리오

Azure Health Data Services의 **FHIR service**를 의료 시스템의 foundation으로 채택하기 전,
핵심 FHIR 기능이 규격대로 동작하는지 재현 가능하게 검증하고 **결과보고서**로 남기기 위한 시나리오다.

- 실행: [`tests/run-scenarios.sh`](./tests/run-scenarios.sh) — curl 기반, 8개 시나리오를 순차 실행하고 PASS/FAIL 로그 생성
- 테스트 데이터: [`data/`](./data/) — 합성(synthetic) 리소스만 사용 (실제 환자/PII 없음)
- 보고서: [`REPORT-TEMPLATE.md`](./REPORT-TEMPLATE.md) — 실행 로그를 붙여 제출용으로 채우는 템플릿

> **리소스명 규칙**: 스크립트/문서 어디에도 실제 리소스명·구독 ID를 넣지 않는다.
> FHIR 엔드포인트는 `FHIR_URL` 환경변수로만 주입한다.

## 검증 시나리오

| # | 시나리오 | 검증하는 FHIR 기능 | 기대 결과 |
|---|---------|------------------|----------|
| 1 | Patient 등록 → 조회 | 리소스 CRUD, 서버 ID 할당 | `201` 생성, `200` 조회 |
| 2 | 진료기록 트랜잭션 Bundle (Encounter+Observation+Condition) | 리소스 간 참조, `transaction` Bundle 원자성 | `200` (`transaction-response`) |
| 3 | 검색·필터 | `_id`, `subject`, `_include` 검색 파라미터 | `200` (`searchset` Bundle) |
| 4 | 버전/이력·낙관적 동시성 | `PUT`+`If-Match`(ETag), `_history` | `200`, 버전 증가 |
| 5 | 프로파일 검증 | `$validate` → `OperationOutcome` | 위반 시 `OperationOutcome(error)` |
| 6 | 대량 반출 | Bulk Data `$export` 비동기 kick-off | `202` + `Content-Location` |
| 7 | 그래프 조회 | `Patient/{id}/$everything` | `200` (연관 리소스 Bundle) |
| 8 | 정리 | 리소스 `DELETE` | `200` |

## 사전 요구사항

- **Azure FHIR service** 인스턴스 (Azure Health Data Services workspace 하위)
- 인증된 **Azure CLI** (`az login`) — 실행 계정에 FHIR 데이터 롤 필요
  (`FHIR Data Contributor` 이상; export 검증 시 `$export` 권한/스토리지 연결 구성)
- `curl`, `python3`(JSON 검증용, 선택)

> FHIR service 프로비저닝 자체(IaC)는 이 시나리오 범위 밖이다. 기존 인스턴스 또는
> `az healthcareapis` / Bicep으로 별도 배포한 인스턴스를 대상으로 한다.

## 실행 절차

```bash
cd scenarios/fhir-service-functional-tests

# 1) 대상 FHIR 엔드포인트 지정 (실제 값은 커밋하지 말 것)
export FHIR_URL="https://{workspace명}-{fhir명}.fhir.azurehealthcareapis.com"

# 2) 로그인 (한 번)
az login

# 3) 실행 — 결과는 콘솔 + fhir-test-<timestamp>.log 에 기록
./tests/run-scenarios.sh
```

종료코드 `0` = 전부 PASS. 생성된 `.log` 파일을 보고서에 첨부한다.

### 테스트 데이터 확장 (선택)

실전에 가까운 대량 데이터가 필요하면 [Synthea](https://github.com/synthetichealth/synthea)로
합성 FHIR Bundle을 생성해 `$import` 또는 transaction Bundle로 적재한다. **실제 환자 데이터는 사용 금지.**

## 검증 상태

- [x] 스크립트 bash 문법 검사 (`bash -n`) 통과
- [x] 테스트 데이터 JSON 유효성 통과
- [x] Mock FHIR 서버 대상 end-to-end 스모크 테스트 통과 (11/11) — req/check/ETag/토큰 플러밍 검증
- [ ] **실제 Azure FHIR service 대상 실행** — 유효한 `FHIR_URL` + 데이터 롤 부여된 계정 필요 (환경 의존, 미수행)

> 스크립트 로직은 mock으로 검증했으나, `$export` 권한·프로파일 검증 세부 응답 등
> 서비스별 동작은 실제 인스턴스에서 최종 확인이 필요하다.
