# PoC 구현 계획 (Tumor Board Agentic AI)

> 목표: Stanford 케이스의 **일부**를 Azure로 실제 배포·검증 가능한 최소 PoC로 좁힌다.
> 전체 5-에이전트 프로덕션이 아니라, ROI가 명확한 **단일 유스케이스부터** 시작한다.

> English version: [POC-PLAN.en.md](./POC-PLAN.en.md)

## 0. PoC 범위 (의도적 축소)

- **In**: Orchestrator + 에이전트 2종(**타임라인 생성**, **임상시험 매칭**) + RAG(AI Search) + HITL 승인.
- **Out (2차로 미룸)**: 영상분석(DICOM), 멀티리전 DR, APIM 시맨틱캐시, Purview 데이터 계보.
- **데이터**: 실제 PHI 대신 **합성 FHIR 샘플**(Synthea 등)로 시작. 실 PHI는 컴플라이언스 게이트 통과 후.

> 왜 축소: 5-에이전트·DICOM·멀티리전을 한 번에 세우면 검증 불가한 데모가 된다. 두 에이전트로 파이프라인이 도는 걸 먼저 증명한다.

## 1. 단계별 계획

| 단계 | 내용 | 산출물 / 완료 기준 |
|---|---|---|
| **P0 · 기반** | RG, Hub-Spoke VNet, Private DNS, Log Analytics, App Insights, Key Vault, Managed Identity | `terraform apply` 성공, `terraform validate` 통과 |
| **P1 · 데이터** | Storage(ZRS), Cosmos(세션), Health Data Services(FHIR), 합성 FHIR 로드 | FHIR `$validate`/CRUD 성공 (기존 `scenarios/fhir-service-functional-tests` 재사용) |
| **P2 · 지식/RAG** | AI Search 인덱스(가이드라인·임상시험 문서), 하이브리드 검색 | 샘플 질의 top-k 그라운딩 반환 |
| **P3 · 에이전트** | AI Foundry Project, 모델 배포(gpt 계열), Agent Service에 Orchestrator + 2 에이전트 | 오케스트레이터가 두 에이전트 호출 후 종합 응답 |
| **P4 · 앱/HITL** | Container Apps 웹앱 + API, 임상의 승인 게이트, 인용 표시 | 데모 시나리오 1건 end-to-end, 각 추천에 출처 인용 |
| **P5 · 관찰성/평가** | Foundry Tracing + App Insights, 정확도/그라운딩 평가 스크립트 | 에이전트별 트레이스 확인, 평가 리포트 1회 |

## 2. 검증 게이트 (완료 선언 전 필수)

- [ ] `terraform validate` + `plan` 무오류 (`infra/`)
- [ ] 모든 PaaS는 Private Endpoint, 퍼블릭 액세스 차단
- [ ] 시크릿 하드코딩 0 (Managed Identity + Key Vault), 실제 리소스명/ID 하드코딩 0 (AGENTS.md 규칙)
- [ ] gpt 계열 호출은 `max_completion_tokens` 사용, 토큰 한도 800+ (빈 응답 방지)
- [ ] HITL 승인 없이는 최종 추천이 임상의에게 확정 노출되지 않음
- [ ] 각 추천에 출처 인용 존재 (환각 완화)

## 3. 리스크 & 선결 조건

- **컴플라이언스**: 실 PHI 전 BAA 체결·PHI 최소화·리전 고정(예: koreacentral). PoC는 합성 데이터로 우회.
- **provider 커버리지**: AI Foundry **Agent Service**는 Terraform azurerm 지원이 얇음 → 해당 부분은 `azapi` 또는 배포 후 스크립트/포털로 구성(`infra/` 주석에 표시).
- **비용/시간**: APIM 생성은 느림(수십 분)·비용 큼 → PoC에서 제외, 필요 시 P4 이후 추가.
- **모델 티어링**: 단순 매칭은 소형 모델, 종합/타임라인만 대형 모델로 라우팅해 토큰 비용 관리.

## 4. 다음 단계 (PoC 이후)

영상분석 에이전트(DICOM) → 실 PHI 전환 → APIM AI Gateway → Purview 계보 → 멀티리전 DR → 편향/드리프트 모니터링.

---

*이 PoC가 검증되면 `case-studies/`에서 배포 가능한 완결 단위로 성장했다는 뜻 →
그때 `scenarios/tumor-board-agentic-poc/`로 승격(graduate)하는 것을 고려한다.*
