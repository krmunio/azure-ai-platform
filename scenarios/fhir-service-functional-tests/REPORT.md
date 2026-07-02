# Azure FHIR Service 기능 검증 결과보고서

> 실제 실행 결과. 엔드포인트·리소스 ID 등 환경 고유 값은 placeholder로 치환했다.

## 1. 개요

| 항목 | 내용 |
|------|------|
| 검증 대상 | Azure Health Data Services — FHIR service (FHIR R4) |
| 엔드포인트 | `https://{workspace명}-{fhir명}.fhir.azurehealthcareapis.com` |
| 실행 일시 | 2026-07-02 10:55 (KST) |
| 인증 방식 | Azure CLI 토큰 (FHIR Data Contributor 롤) |
| 도구 | `tests/run-scenarios.sh` (curl) |
| 배포 방식 | `infra/deploy.sh <prefix>` (Bicep) |

## 2. 목적

FHIR service를 의료정보 플랫폼의 데이터 foundation으로 채택하기에 앞서,
CRUD·검색·버전관리·프로파일 검증·대량반출 등 핵심 표준 기능의 정상 동작을 확인한다.

## 3. 검증 결과 요약

**종합: PASS 10 / FAIL 0 / SKIP 1**  (스크립트 종료코드: 0)

| # | 시나리오 | FHIR 기능 | 기대 | 결과(코드) | 판정 |
|---|---------|----------|------|-----------|------|
| 1 | Patient 등록/조회 | CRUD | 201/200 | 201 / 200 | PASS |
| 2 | 트랜잭션 Bundle | 참조·원자성 | 200 | 200 | PASS |
| 3 | 검색 (`_id`) | 검색 파라미터 | 200 | 200 | PASS |
| 3 | 검색 (`subject`+`_include`) | 검색 파라미터 | 200 | 200 | PASS |
| 4 | PUT + If-Match | 낙관적 동시성 | 200 | 200 | PASS |
| 4 | `_history` | 버전 이력 | 200 | 200 | PASS |
| 5 | `$validate` | 프로파일 검증 | OperationOutcome | OperationOutcome | PASS |
| 6 | `$export` | Bulk Data | 202 | 400 (not enabled) | SKIP |
| 7 | `$everything` | 그래프 조회 | 200 | 200 | PASS |
| 8 | DELETE | 삭제 | 204 | 204 | PASS |

## 4. 세부 결과 / 근거

- **시나리오 1**: Patient 생성 시 `201`, 서버가 리소스 id(`{patient-id}`) 할당. `GET /Patient/{id}` `200`.
- **시나리오 2**: Encounter+Observation+Condition transaction Bundle `200` — 리소스 간 참조(`Patient/{id}`, `urn:uuid` 내부 참조) 정상 해석.
- **시나리오 3**: `_id` 검색, `subject` + `_include:Observation:subject` 모두 `200` searchset 반환.
- **시나리오 4**: `PUT` + `If-Match`(ETag) `200`으로 낙관적 동시성 동작, `_history` 조회 `200`.
- **시나리오 5**: 잘못된 gender/birthDate 리소스에 대해 `$validate`가 `OperationOutcome`(severity=error) 반환.
- **시나리오 6 (SKIP)**: `$export`는 export용 스토리지 계정 연결이 없어 `400 "operation is not enabled"`. 스토리지 구성은 본 시나리오 범위 밖이라 SKIP 처리.
- **시나리오 7**: `Patient/{id}/$everything` `200`으로 연관 리소스 그래프 반환.
- **시나리오 8**: `DELETE` `204`(Azure FHIR는 No Content 반환).

## 5. 발견 사항

| 구분 | 내용 | 조치 |
|------|------|------|
| 서비스 동작 | Azure FHIR `DELETE`는 `200`이 아닌 `204` 반환 | 스크립트 기대값 `204`로 정정 |
| 설정 의존 | `$export`는 스토리지 미구성 시 `400 not enabled` | SKIP 처리, export 검증 필요 시 스토리지+롤 별도 구성 |

## 6. 결론 및 권고

- 핵심 FHIR 기능(CRUD, 트랜잭션, 검색/`_include`, 버전·낙관적 동시성, `$validate`, `$everything`)은
  규격대로 정상 동작 → **foundation 채택 가능**.
- `$export`(대량 반출) 사용 시 export 스토리지 계정 연결과 서비스 identity 롤 부여가 선행돼야 한다.
- 프로파일 강제(US Core 등)는 서비스 기본이 아니므로 별도 정책/검증 파이프라인으로 관리 권고.

## 7. 실행 로그 (sanitized)

```text
== Azure FHIR 기능 검증 ==
endpoint: https://{workspace명}-{fhir명}.fhir.azurehealthcareapis.com
started:  2026-07-02T10:55:34+09:00

[1] Patient 등록/조회
  PASS [201] POST Patient 생성
  patient id: {patient-id}
  PASS [200] GET Patient/{id} 조회
[2] Encounter+Observation+Condition 트랜잭션 Bundle
  PASS [200] transaction Bundle 처리
[3] 검색
  PASS [200] search Patient?_id
  PASS [200] search Observation + _include
[4] 버전/이력
  PASS [200] PUT + If-Match (낙관적 동시성)
  PASS [200] GET _history
[5] $validate (규격 위반 감지)
  PASS [200] $validate가 OperationOutcome 반환
[6] Bulk $export
  SKIP [400] $export 미활성(스토리지 미구성) — 범위 밖
[7] Patient/{id}/$everything
  PASS [200] $everything
[8] 정리
  PASS [204] DELETE Patient

== 결과: PASS=10 FAIL=0 SKIP=1 ==
```
