# Azure FHIR Service 기능 검증 결과보고서

> `tests/run-scenarios.sh` 실행 후 이 템플릿의 `{...}` 를 채워 제출한다.
> 실제 리소스명·구독 ID·엔드포인트 전체 경로는 기입하지 않는다(placeholder 유지).

## 1. 개요

| 항목 | 내용 |
|------|------|
| 검증 대상 | Azure Health Data Services — FHIR service (FHIR R4) |
| 엔드포인트 | `https://{workspace명}-{fhir명}.fhir.azurehealthcareapis.com` |
| 실행 일시 | {YYYY-MM-DD HH:MM} |
| 실행자 | {이름/역할} |
| 인증 방식 | Azure CLI 토큰 (FHIR Data Contributor 롤) |
| 도구 | curl / run-scenarios.sh |

## 2. 목적

{예: FHIR service를 신규 의료정보 플랫폼의 데이터 foundation으로 채택하기에 앞서,
CRUD·검색·버전관리·프로파일 검증·대량반출 등 핵심 표준 기능의 정상 동작을 확인한다.}

## 3. 검증 결과 요약

| # | 시나리오 | FHIR 기능 | 기대 | 결과(코드) | 판정 |
|---|---------|----------|------|-----------|------|
| 1 | Patient 등록/조회 | CRUD | 201/200 | {} | {PASS/FAIL} |
| 2 | 트랜잭션 Bundle | 참조·원자성 | 200 | {} | {} |
| 3 | 검색·_include | 검색 파라미터 | 200 | {} | {} |
| 4 | 버전/이력·ETag | 낙관적 동시성 | 200 | {} | {} |
| 5 | $validate | 프로파일 검증 | OperationOutcome | {} | {} |
| 6 | $export | Bulk Data | 202 | {} | {} |
| 7 | $everything | 그래프 조회 | 200 | {} | {} |
| 8 | DELETE | 삭제 | 200 | {} | {} |

**종합: PASS {n} / FAIL {m}**  (스크립트 종료코드: {0/1})

## 4. 세부 결과 / 근거

시나리오별 요청·응답 요약과 특이사항. 원문 로그는 §7에 첨부.

- **시나리오 1**: {서버 할당 id, meta.versionId, ETag 관찰값}
- **시나리오 2**: {transaction-response 각 entry 상태, 참조 무결성 확인}
- **시나리오 4**: {If-Match 성공 및 versionId 증가, 잘못된 ETag 시 412 여부}
- **시나리오 5**: {OperationOutcome issue severity/diagnostics 요약}
- **시나리오 6**: {202 Content-Location, 폴링 결과·NDJSON 출력 위치}
- ...

## 5. 발견 사항 / 이슈

| 구분 | 내용 | 영향 | 조치/후속 |
|------|------|------|----------|
| {버그/제약/설정} | {설명} | {상/중/하} | {대응} |

## 6. 결론 및 권고

{예: 핵심 FHIR 기능은 규격대로 동작. foundation 채택 가능.
단, $export는 스토리지 연결·롤 구성이 선행되어야 하며 프로파일 강제(US Core)는
별도 정책으로 관리 권고.}

## 7. 첨부

- 실행 로그: `fhir-test-{timestamp}.log`
- 사용 테스트 데이터: `data/*.json`
- 환경 정보: FHIR 버전(`GET /metadata` capability statement의 `fhirVersion`), 서비스 SKU 등
