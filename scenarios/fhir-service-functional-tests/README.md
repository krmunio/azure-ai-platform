# Azure FHIR Service 기능 검증 시나리오

Azure Health Data Services의 **FHIR service**를 의료 시스템의 foundation으로 채택하기 전,
핵심 FHIR 기능이 규격대로 동작하는지 재현 가능하게 검증하고 **결과보고서**로 남기기 위한 시나리오다.

- 실행: [`tests/run-scenarios.sh`](./tests/run-scenarios.sh) — curl 기반, 8개 시나리오를 순차 실행하고 PASS/FAIL 로그 생성
- 인프라: [`infra/`](./infra/) — FHIR service를 배포하는 Bicep + `deploy.sh`
- 테스트 데이터: [`data/`](./data/) — 합성(synthetic) 리소스만 사용 (실제 환자/PII 없음)
- 대량 데이터: [`tests/load-synthea.sh`](./tests/load-synthea.sh) — Synthea 합성 Bundle 적재
- 보고서: [`REPORT-TEMPLATE.md`](./REPORT-TEMPLATE.md) — 실행 로그를 붙여 제출용으로 채우는 템플릿
- 실행 결과: [`REPORT.md`](./REPORT.md) — 실제 인스턴스 실행 결과보고서 (10 PASS / 0 FAIL / 1 SKIP)

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

> FHIR service가 없다면 [`infra/`](./infra/)로 배포한 뒤 대상으로 삼는다(아래 "인프라 배포").

## 인프라 배포 (`infra/`)

FHIR service 인스턴스가 없으면 Bicep으로 배포한다. Azure Health Data Services
**workspace + FHIR service(R4)** 를 생성하고, 실행 계정에 `FHIR Data Contributor` 롤을 부여한다.

```bash
cd scenarios/fhir-service-functional-tests/infra
az login

./deploy.sh <prefix>            # prefix를 인자로 전달 (또는 인자 없이 실행하면 프롬프트)
# LOCATION=eastus ./deploy.sh <prefix>   # 위치 변경 시
```

- **prefix는 실행 시 입력**받아 모든 리소스명을 파생한다 — `rg-<prefix>-fhir`,
  `<prefix>hdsws`(workspace), `<prefix>fhir`(FHIR service). 저장소에 실제 prefix를 커밋하지 않는다.
- prefix 형식: 소문자로 시작하는 영숫자 3-11자.
- FHIR service는 **system-assigned identity**를 가지며, `principalId`가 출력된다
  (`$export`용 스토리지 롤 부여 시 사용).
- 배포 후 출력된 `FHIR_URL`을 export 하면 시나리오를 실행할 수 있다.
- `$export`용 스토리지 계정·롤은 범위에서 제외했다. 필요하면 별도 구성한다.

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

### 테스트 데이터 확장 — Synthea (선택)

**Synthea**(Synthetic Patient Population Simulator, MITRE 오픈소스)는 실제 사람이 아닌
통계·질병 모델 기반으로 **합성 환자의 일대기**(출생→질병→진료→처방→사망)를 시뮬레이션해
현실적인 의료 데이터를 생성하는 도구다. **PII가 전혀 없어** 개발·데모·부하 테스트에 자유롭게 쓸 수 있다.

- FHIR(R4 등) 출력을 지원 → `output/fhir/*.json` 에 Patient/Encounter/Observation/Condition 등을
  담은 **transaction Bundle**을 생성한다.
- 생성된 Bundle을 FHIR 서버에 POST하면 그대로 적재된다(대량 검색·`$export` 검증용 데이터 확보).

```bash
# 1) 합성 데이터 생성 (Java 11+ 필요)
git clone https://github.com/synthetichealth/synthea && cd synthea
./run_synthea -p 100          # 환자 100명 분량 FHIR Bundle 생성 → output/fhir/

# 2) Azure FHIR service 에 적재 (엔드포인트는 환경변수로만)
export FHIR_URL="https://{workspace명}-{fhir명}.fhir.azurehealthcareapis.com"
/path/to/scenarios/fhir-service-functional-tests/tests/load-synthea.sh ./output/fhir
```

> **실제 환자 데이터는 사용 금지** — Synthea 합성 데이터만 사용한다.
> 대량 적재는 transaction Bundle POST 대신 `$import`(비동기 대량 반입)로도 가능하다.

## 검증 상태

- [x] 스크립트 bash 문법 검사 (`bash -n`) 통과 — `run-scenarios.sh`, `load-synthea.sh`, `deploy.sh`
- [x] 테스트 데이터 JSON 유효성 통과
- [x] Bicep 컴파일(`az bicep build`) 통과 — `infra/main.bicep`
- [x] Mock FHIR 서버 대상 end-to-end 스모크 테스트 통과 — req/check/ETag/토큰 플러밍 검증
- [x] **실제 Azure FHIR service 배포·실행 완료** — `deploy.sh <prefix>`로 배포, 시나리오 **10 PASS / 0 FAIL / 1 SKIP**
- [ ] **Synthea 대량 적재 실행** — Java+Synthea 및 배포된 FHIR service 필요 (미수행)

> 실 인스턴스 확인 사항: Azure FHIR는 `DELETE` 시 `204`, `$export`는 export용 스토리지가
> 구성돼야 하며 미구성 시 `400 "not enabled"`(스크립트는 SKIP 처리)를 반환한다.
