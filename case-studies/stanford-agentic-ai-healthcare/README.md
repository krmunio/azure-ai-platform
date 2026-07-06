# Stanford Medicine Agentic AI 케이스 스터디 & Azure 구현 아키텍처

> 출처: [Transforming Healthcare with Agentic AI: Stanford and Microsoft Lead the Future (WindowsForum, 2025-05-23)](https://windowsforum.com/threads/transforming-healthcare-with-agentic-ai-stanford-and-microsoft-lead-the-future.367652/)

**이 폴더**: [ARCHITECTURE.md](./ARCHITECTURE.md) (Mermaid 다이어그램) · [POC-PLAN.md](./POC-PLAN.md) (구현 계획) · [infra/](./infra/) (Terraform 스캐폴딩)

> English version: [README.en.md](./README.en.md)

---

## 1. Stanford Medicine 케이스 스터디 상세

### 배경과 문제
Stanford Medicine은 매년 **4,000명 이상의 Tumor Board(종양 위원회) 환자**를 다룹니다. 개인화된 치료 타임라인(personalized care timeline)은 종양학적 예후를 유의미하게 개선하지만, 지금까지는 **환자의 약 1%만** 이 수준의 개인화 혜택을 받았습니다. 이유는 데이터 취합·종합 과정이 전적으로 **수작업**이기 때문입니다. 의사가 EHR, 영상 판독, 병리 리포트, 치료 이력, 최신 임상 가이드라인, 임상시험 DB를 일일이 뒤져 종합해야 했습니다.

### Azure AI Foundry 기반 에이전트 오케스트레이션 도입
Microsoft와 협력해 **다중 에이전트(multi-agent) 오케스트레이션 시스템**을 구축했습니다. 핵심은 하나의 거대 모델이 아니라, **세부 작업별 전문 에이전트**를 조율하는 구조입니다.

| 에이전트 역할 | 하는 일 |
|---|---|
| **Medical Imaging Analysis** | 진단 영상을 검토하고 과거 데이터셋·최신 의료 가이드라인과 교차 참조 |
| **Clinical Trial Matching** | 임상시험 DB를 탐색해 환자의 참여 적격성 판별 |
| **Personalized Timeline Generation** | EHR, 진단 리포트, 치료 이력, 외부 가이드라인을 종합해 동적 개인 치료 계획 생성 |

### 효과 (보고된 내용)
- **시간 절감**: 케이스당 데이터 추출·종합·정리에 드는 수 시간의 임상의 시간 절감 → 더 빠른 치료 결정.
- **실행 가능한 인사이트**: 미묘한 환자 시나리오, 가용 임상시험, 최신 베스트 프랙티스를 신속 식별.
- **확장 가능한 개인화**: 1% 소수에서 훨씬 넓은 환자층으로 개인화 확대 가능성.
- **연구 가속**: EHR·환자 데이터의 접근성·활용성 향상으로 실세계 근거(RWE) 도출 속도 증가.
- Stanford CIO **Dr. Mike Pfeffer**는 실제 Tumor Board 회의에서 임상의가 생성형 AI 요약을 이미 활용 중이라고 언급.

### 강점과 주의점 (기사의 균형 잡힌 시각)
**강점**: 모듈성/확장성(에이전트 단위 교체·튜닝), 협업 강화, 컴플라이언스·거버넌스(감사 추적·관찰성), 이전엔 접근 어려웠던 데이터 활용.

**주의점**:
- **투명성/설명가능성**: 아키텍처는 투명하나 개별 에이전트의 심층 판단 로직은 여전히 블랙박스 → 임상의 저항 가능.
- **일반화/편향**: Stanford 데이터에 과적합되면 다른 환자군의 소규모 병원에서 성능 저하·형평성 문제.
- **규제 장벽**: FDA·유럽 규제 프레임워크가 형성 중, 데이터 레지던시·감사가능성 요구.
- **보안/프라이버시**: 에이전트마다 공격 표면 증가, 에이전트 간 통신·클라우드 인프라 모두 검증 필요.
- **비용/복잡성**: 라이선싱, 컴플라이언스, 모델 개발, 워크플로 통합에 상당한 선투자.

---

## 2. Azure 논리 아키텍처 (Logical Architecture)

종양 위원회 시나리오를 Azure로 구현하는 논리 구성입니다.

```
┌───────────────────────────────────────────────────────────────────────┐
│                         프레젠테이션 / 협업 계층                          │
│   Tumor Board 대시보드(웹앱)  ·  Teams/Copilot 통합  ·  임상의 리뷰 UI    │
└───────────────────────────────────┬───────────────────────────────────┘
                                     │ (Entra ID 인증, RBAC)
┌───────────────────────────────────▼───────────────────────────────────┐
│                     오케스트레이션 계층 (Orchestrator Agent)              │
│   Azure AI Foundry Agent Service · 워크플로/플래너 · 상태·세션 관리       │
│   (Semantic Kernel / MAF 기반 멀티에이전트 조율, Human-in-the-loop 게이트)│
└───┬───────────────────┬────────────────────┬─────────────────────┬─────┘
    │                   │                    │                     │
┌───▼──────┐   ┌────────▼────────┐   ┌───────▼────────┐   ┌────────▼───────┐
│ 영상분석  │   │ 임상시험 매칭    │   │ 타임라인 생성   │   │ 가이드라인/근거 │
│ 에이전트  │   │ 에이전트         │   │ 에이전트        │   │ 검색 에이전트   │
└───┬──────┘   └────────┬────────┘   └───────┬────────┘   └────────┬───────┘
    │                   │                    │                     │
┌───▼───────────────────▼────────────────────▼─────────────────────▼─────┐
│                       도구 / 지식 검색 계층 (Tools & RAG)                 │
│  Agentic Retrieval · AI Search(벡터/하이브리드) · Grounding · MCP 툴콜   │
└───┬───────────────────┬────────────────────┬─────────────────────┬─────┘
    │                   │                    │                     │
┌───▼──────┐   ┌────────▼────────┐   ┌───────▼────────┐   ┌────────▼───────┐
│ 모델계층  │   │ EHR / FHIR      │   │ 임상시험 DB     │   │ 영상 저장소     │
│ Foundry  │   │ (Healthcare     │   │ (내부/ClinTrial │   │ (DICOM/PACS,   │
│ 모델카탈로그│  │  Data Services) │   │  .gov 커넥터)   │   │  Blob)         │
└──────────┘   └─────────────────┘   └────────────────┘   └────────────────┘

가로 관통(모든 계층):  관찰성(Observability)  ·  거버넌스/트러스트  ·  보안
   Azure Monitor/App Insights · Foundry Tracing · Content Safety
   · Purview(데이터 계보/분류) · Defender · Key Vault · HIPAA/GDPR 준수
```

**핵심 논리 컴포넌트**
- **Orchestrator Agent**: 사용자 요청을 하위 전문 에이전트로 분해·라우팅하고, 결과를 종합. Human-in-the-loop 승인 게이트 포함.
- **전문 에이전트 4종**: 영상분석 / 임상시험 매칭 / 타임라인 생성 / 근거 검색.
- **Agentic Retrieval + RAG**: 단일 검색이 아닌 에이전트별 관점으로 반복 질의 후 종합. AI Search 벡터·하이브리드 검색으로 그라운딩.
- **데이터 소스**: FHIR 기반 EHR, DICOM 영상(PACS/Blob), 임상시험 DB, 가이드라인 문서.
- **가로 관통 관심사**: 관찰성, 거버넌스/트러스트, 보안·컴플라이언스는 전 계층 공통.

---

## 3. Azure 물리 아키텍처 (Physical Architecture)

실제 Azure 리소스 매핑입니다. (리소스명은 조직 규칙에 따라 지정 — placeholder 사용)

```
                          ┌─────────────────────────┐
   임상의/연구자  ──────▶  │  Entra ID (인증/조건부접근) │
                          │  Front Door + WAF        │
                          └────────────┬────────────┘
                                       │ Private
        ┌──────────────────────────────▼──────────────────────────────┐
        │                    Hub-Spoke VNet (Private)                   │
        │                                                               │
        │  ┌── Spoke: App ──────────────────────────────────────────┐  │
        │  │  App Service / Container Apps  (Tumor Board 웹앱 + API)  │  │
        │  │  APIM (AI Gateway: 토큰제한·라우팅·시맨틱캐시)            │  │
        │  └────────────────────────┬───────────────────────────────┘  │
        │                           │ Private Endpoint                  │
        │  ┌── Spoke: AI ───────────▼───────────────────────────────┐  │
        │  │  Azure AI Foundry (Hub/Project)                         │  │
        │  │   ├ Agent Service (Orchestrator + 전문 에이전트)         │  │
        │  │   ├ Foundry Models (GPT-4o/o-series, 의료특화 모델)     │  │
        │  │   └ Content Safety                                     │  │
        │  │  Azure AI Search (벡터/하이브리드 인덱스)                │  │
        │  └────────────────────────┬───────────────────────────────┘  │
        │                           │ Private Endpoint                  │
        │  ┌── Spoke: Data ─────────▼───────────────────────────────┐  │
        │  │  Azure Health Data Services (FHIR + DICOM service)      │  │
        │  │  Blob Storage(영상/문서, ZRS)  ·  Cosmos DB(세션/상태)   │  │
        │  │  임상시험 DB (SQL/커넥터)                                │  │
        │  └────────────────────────────────────────────────────────┘  │
        │                                                               │
        │  공통: Key Vault · Managed Identity · Private DNS · Bastion   │
        └───────────────────────────────────────────────────────────────┘

  관찰성/거버넌스/보안 (구독 전역):
   Azure Monitor · Application Insights · Log Analytics · Foundry Tracing
   Microsoft Purview(데이터 분류/계보) · Defender for Cloud · Azure Policy
```

### 리소스 매핑 요약

| 계층 | Azure 서비스 | 역할 |
|---|---|---|
| 진입/보안 | Entra ID, Front Door + WAF, Private Endpoint | 인증·조건부 접근, 엣지 보호, 프라이빗 연결 |
| API 게이트웨이 | API Management (AI Gateway) | 토큰 제한, 로드밸런싱, 시맨틱 캐싱, 콘텐츠 안전 정책 |
| 앱/호스팅 | App Service 또는 Container Apps | 대시보드 웹앱, 백엔드 API |
| 에이전트/오케스트레이션 | Azure AI Foundry Agent Service | 오케스트레이터 + 전문 에이전트 실행 |
| 모델 | Foundry Models (GPT-4o/o-series 등) | 추론·요약·생성 |
| 검색/RAG | Azure AI Search | 벡터·하이브리드 검색, 그라운딩 |
| 안전 | Azure AI Content Safety | 유해·환각 완화, jailbreak 탐지 |
| 임상 데이터 | Azure Health Data Services (FHIR + DICOM) | EHR·의료영상 표준 저장/조회 |
| 저장/상태 | Blob Storage(ZRS), Cosmos DB | 영상·문서, 세션·에이전트 상태 |
| 시크릿/ID | Key Vault, Managed Identity | 자격 증명·키 관리, 무암호 인증 |
| 관찰성 | Azure Monitor, App Insights, Log Analytics, Foundry Tracing | 에이전트별 추적·성능·감사 |
| 거버넌스 | Purview, Defender for Cloud, Azure Policy | 데이터 계보·분류, 위협 탐지, 정책 강제 |

---

## 4. 주요 고려사항 (Key Considerations)

### 규정 준수 & 프라이버시
- **HIPAA / GDPR / 국내 의료법(개인정보보호법·의료법)** 준수. Microsoft와 **BAA(Business Associate Agreement)** 체결 필요.
- **PHI 최소화·비식별화**: 프롬프트·로그에 PHI 노출 최소화, 필요 시 토큰화/마스킹.
- **데이터 레지던시**: 국내 데이터라면 Korea Central 등 리전 고정, 크로스 리전 전송 통제.
- **데이터 계보**: Purview로 어떤 데이터가 어느 에이전트·모델에 입력됐는지 추적.

### 보안 (다중 에이전트 = 넓은 공격 표면)
- **프라이빗 네트워킹**: 모든 PaaS를 Private Endpoint로, 퍼블릭 액세스 차단.
- **무암호 인증**: Managed Identity + Key Vault, 시크릿 하드코딩 금지.
- **에이전트 간 통신 검증**, 프롬프트 인젝션 방어(Content Safety, 입력 검증).
- **최소 권한 RBAC**: 에이전트·데이터 소스별 세분화 권한.

### 신뢰성 & 임상 안전
- **Human-in-the-loop 필수**: AI는 의사결정 지원이지 대체가 아님. 임상의 승인 게이트 배치.
- **설명가능성**: 각 추천의 근거(출처 문서, 인용) 제시 → 블랙박스 저항 완화.
- **환각 완화**: RAG 그라운딩, 인용 강제, Content Safety groundedness 검출.
- **고가용성**: Zone-redundant(ZRS 스토리지, 존 중복 배포), 멀티리전 DR.

### 관찰성 & 거버넌스
- **에이전트별 트레이싱**: Foundry Tracing + App Insights로 각 에이전트 결정·성능·상호작용 추적, 감사 추적 확보.
- **평가(Evaluation) 파이프라인**: 정확도·안전성·편향 정기 벤치마킹, 회귀 방지.
- **모델 버전 관리**: 모델·프롬프트 변경 이력 관리(GitHub), 롤백 가능.

### 편향 & 일반화
- **데이터 편향 검증**: 단일 기관 데이터 과적합 방지, 다양한 환자군 검증.
- **모니터링**: 배포 후 성능 드리프트·형평성 지표 지속 추적.

### 비용 & 운영
- **토큰 비용 관리**: APIM AI Gateway로 토큰 한도·시맨틱 캐싱, gpt 계열은 `max_completion_tokens` 사용.
- **모델 티어링**: 단순 작업은 소형 모델, 복잡 추론만 대형 모델 라우팅.
- **점진적 파일럿**: 명확한 ROI 측정 가능한 단일 유스케이스(예: 임상시험 매칭)부터 시작 후 확장.
- **변화 관리**: 임상의 교육·워크플로 통합, 조직 buy-in 확보.
