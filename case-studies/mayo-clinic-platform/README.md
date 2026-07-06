# Mayo Clinic Platform 케이스 스터디 & Azure 구현 아키텍처

> 출처: [Understanding Mayo Clinic Platform: A Strategic Overview for Health IT Leaders (Healthcare IT Today, 2025-06-16)](https://www.healthcareittoday.com/2025/06/16/understanding-mayo-clinic-platform-a-strategic-overview-for-health-it-leaders/)
> 보조 출처: Mayo Clinic Platform_Connect, [Mayo Clinic + Microsoft frontier AI model 협업 발표(2026-06)](https://newsnetwork.mayoclinic.org/discussion/mayo-clinic-and-microsoft-collaborate-to-develop-a-frontier-ai-model-for-healthcare/)

**이 폴더**: [ARCHITECTURE.md](./ARCHITECTURE.md) (Mermaid 다이어그램)

> ⚠️ 상태: **초안(draft)**. 케이스 스터디 정리 + Azure 매핑 논리/물리 아키텍처. Terraform 스캐폴딩·영문판은 미포함(요청 시 추가).

---

## 1. Mayo Clinic Platform 케이스 스터디 상세

### 배경과 목적
Mayo Clinic Platform은 Mayo Clinic의 임상 데이터·전문성을 활용해 전 세계 의료기관·개발사가 **AI 기반 디지털 헬스 솔루션**을 개발·검증·배포하도록 지원하는 이니셔티브입니다. 의료 AI는 **데이터의 품질만큼만 우수**하다는 전제 위에, 고품질·종단(longitudinal)·비식별(de-identified) 임상 데이터를 근간으로 삼습니다.

핵심 프로그램은 **Solutions Studio**로, 디지털 헬스 앱을 개발→배포까지 가속합니다. (초기 단계 스타트업은 `Accelerate`, 후기 단계는 `Solutions Studio`.)

### 차별점 — 분산 데이터 네트워크 "Data Behind Glass"
Mayo Clinic Platform_Connect는 3개 대륙의 주요 의료 시스템을 연결하는 **연합(federated)·분산 데이터 네트워크**입니다.

- 각 파트너 기관은 **자체 "데이터 노드"** 를 보유하고, **데이터는 조직 밖으로 나가지 않습니다.**
- 데이터를 옮기는 대신 **알고리즘을 데이터로 가져가는(bring the model to the data)** 프라이버시 강화 방식 — 이를 **"Data Behind Glass"** 라고 부릅니다.
- 모든 데이터는 **비식별화**되고, 노드 간 통신은 **암호화·블라인드** 처리됩니다. 각 파트너가 자신의 데이터에 대한 완전한 통제권을 유지합니다.

### 3대 역량 (Solutions Studio)

| 단계 | 하는 일 |
|---|---|
| **Discover** | 비식별 임상 데이터 저장소 접근. 환자 1,360만+, 이미지(CT/MRI/PET) 58억+, 검사 결과 27.2억+ (2025.5 기준). 정형(인구통계·진단·투약) + 비정형(임상노트·판독·병리) 포함. 인사이트 도출·검증·AI 모델 학습에 사용. |
| **Validate** | AI 모델·디지털 헬스 솔루션을 **독립적으로** 평가. 도시·농촌 등 다양한 인구집단의 비식별 데이터로 성능을 측정해 **편향·한계**를 임상 도입 전에 식별. 제3자 평가 리포트로 투명성·신뢰 확보. |
| **Deploy** | AI 솔루션을 임상 워크플로우에 통합. 기술·운영 프레임워크 + 전담 전문가 팀으로 파트너 의료기관 네트워크에 신속 배포, 모델 개발→실사용 전환을 가속. |

### 헬스 IT 리더 관점의 전략적 이점 (기사 요약)
- **혁신 가속**: 방대한 임상 데이터 + AI 도구로 빠른 프로토타이핑, 출시 시간·비용 절감.
- **엄격한 검증**: 성능·신뢰성·공정성 자격 심사로 도입 신뢰 확보.
- **매끄러운 통합**: 상호운용성·기술 복잡성 해소로 개발→구현 전환 원활.
- **협업 생태계**: 의료기관·개발사·연구자 간 지식·리소스 공유.

### 주의점 (도입 시 고려)
- **거버넌스·규제**: 데이터 레지던시, 감사가능성, FDA/유럽 규제 프레임워크 대응.
- **편향·일반화**: 특정 기관 데이터 과적합 방지 — Validate의 다인구집단 평가가 이를 겨냥.
- **프라이버시·보안**: 연합 구조의 노드 간 통신·비식별 파이프라인 검증 필수.

---

## 2. Azure 논리 아키텍처 (Logical Architecture)

Mayo Clinic Platform의 **분산 데이터 네트워크 + Discover/Validate/Deploy** 구조를 Azure로 구현하는 논리 구성입니다. 핵심은 **데이터를 이동시키지 않고(federated)** 각 파트너 노드 안에서 모델을 학습·검증하는 것입니다.

```
┌───────────────────────────────────────────────────────────────────────┐
│                      개발자 / 파트너 포털 계층                            │
│   Solutions Studio 포털  ·  데이터 카탈로그 UI  ·  검증 리포트 뷰어        │
└───────────────────────────────────┬───────────────────────────────────┘
                                     │ (Entra ID B2B, RBAC, 조건부 접근)
┌───────────────────────────────────▼───────────────────────────────────┐
│               연합 제어 평면 (Federated Control Plane)                    │
│   작업 오케스트레이션 · 모델/쿼리 배포 · 결과 취합 · 거버넌스 정책 강제     │
│   (데이터는 이동 안 함 — "모델을 데이터로" 전달, 감사 추적)                │
└───┬───────────────────────┬────────────────────────┬───────────────────┘
    │ (암호화·블라인드 채널)  │                        │
┌───▼──────────────┐  ┌──────▼───────────┐   ┌────────▼──────────────────┐
│ 파트너 노드 A     │  │ 파트너 노드 B     │   │ 파트너 노드 N              │
│ ("Data Behind    │  │                   │   │  (기관별 독립 구독/테넌트) │
│  Glass" 경계)     │  │                   │   │                            │
│ ┌──────────────┐ │  │  … 동일 구조 …    │   │        … 동일 구조 …       │
│ │ Discover     │ │  │                   │   │                            │
│ │ 비식별 데이터 │ │  └───────────────────┘   └────────────────────────────┘
│ │ (FHIR/DICOM) │ │
│ ├──────────────┤ │      각 노드 내부에서만 raw 데이터 접근.
│ │ Validate     │ │      외부로는 비식별 집계·지표·모델 가중치만 반출.
│ │ 모델 평가·편향 │ │
│ ├──────────────┤ │
│ │ Deploy       │ │
│ │ 추론 엔드포인트│ │
│ └──────────────┘ │
└──────────────────┘

가로 관통(모든 계층):  비식별/De-ID  ·  거버넌스/트러스트  ·  관찰성  ·  보안
   Azure Health De-identification service · Purview(계보/분류)
   · Monitor/App Insights · Defender · Key Vault · HIPAA/GDPR/지역 의료법 준수
```

**핵심 논리 컴포넌트**
- **연합 제어 평면**: 파트너 노드에 학습/검증/추론 작업을 배포하고 **비식별 결과만** 취합. raw 데이터는 노드 밖으로 나가지 않음.
- **파트너 노드("Data Behind Glass")**: 기관별 독립 경계 안에서 Discover(데이터)→Validate(평가)→Deploy(추론) 수행.
- **비식별 파이프라인**: 노드 반입 데이터는 De-ID 처리, 반출물은 집계 지표·모델 가중치로 제한.
- **가로 관통 관심사**: 비식별·거버넌스·관찰성·보안은 제어 평면과 모든 노드 공통.

---

## 3. Azure 물리 아키텍처 (Physical Architecture)

파트너 노드 **한 곳**을 Azure 리소스로 매핑한 예시입니다. 각 노드는 독립 구독/테넌트로 동일 패턴을 복제하며, 제어 평면과는 **프라이빗·암호화 채널**로만 연결됩니다. (리소스명은 조직 규칙에 따라 지정 — placeholder 사용)

```
   개발자/파트너 ──▶  Entra ID (B2B, 조건부 접근)  ──▶  Front Door + WAF
                                                            │ Private
        ┌───────────────────────────────────────────────────▼──────────┐
        │              파트너 노드 VNet (Private, Hub-Spoke)             │
        │                                                               │
        │  ┌── Spoke: 제어/게이트웨이 ──────────────────────────────┐   │
        │  │  APIM (연합 작업 수신·정책 강제)  ·  작업 오케스트레이터  │   │
        │  └────────────────────────┬───────────────────────────────┘   │
        │                           │ Private Endpoint                   │
        │  ┌── Spoke: AI (Validate/Deploy) ─▼──────────────────────┐    │
        │  │  Azure AI Foundry (Hub/Project)                        │    │
        │  │   ├ 모델 학습·평가 잡 (편향/성능 리포트)                │    │
        │  │   ├ Foundry Models (의료특화/frontier via Foundry API) │    │
        │  │   └ 추론 엔드포인트 (Deploy) · Content Safety           │    │
        │  │  Azure ML / AI Search (실험·인덱스)                    │    │
        │  └────────────────────────┬───────────────────────────────┘   │
        │                           │ Private Endpoint                   │
        │  ┌── Spoke: Data (Discover) ─▼───────────────────────────┐    │
        │  │  Azure Health Data Services (FHIR + DICOM)             │    │
        │  │  De-identification service (비식별화)                  │    │
        │  │  Blob/ADLS Gen2 (영상·문서, ZRS)                       │    │
        │  └────────────────────────────────────────────────────────┘   │
        │                                                               │
        │  공통: Key Vault · Managed Identity · Private DNS · Bastion   │
        └───────────────────────────────────────────────────────────────┘

  ⇅ 노드 ↔ 제어 평면: 비식별 지표·모델 가중치만, 암호화·블라인드 채널 (raw PHI 반출 금지)

  관찰성/거버넌스/보안 (구독 전역):
   Azure Monitor · App Insights · Log Analytics · Foundry Tracing
   Microsoft Purview(데이터 분류/계보) · Defender for Cloud · Azure Policy
```

### 리소스 매핑 요약

| 계층 | Azure 서비스 | 역할 |
|---|---|---|
| 진입/보안 | Entra ID (B2B), Front Door + WAF, Private Endpoint | 파트너 인증·조건부 접근, 엣지 보호, 프라이빗 연결 |
| 제어/게이트웨이 | API Management, 작업 오케스트레이터 | 연합 작업 수신·라우팅, 거버넌스 정책 강제 |
| 데이터 (Discover) | Azure Health Data Services (FHIR+DICOM), De-identification service, ADLS Gen2 | 비식별 임상 데이터 저장·조회, 노드 로컬 유지 |
| AI (Validate) | Azure AI Foundry, Azure ML, AI Search | 모델 학습·독립 평가, 편향/성능 리포트 |
| AI (Deploy) | Foundry 추론 엔드포인트, Content Safety | 검증된 모델의 임상 워크플로 추론, 안전 필터 |
| 모델 | Foundry Models (의료특화 / frontier via Foundry API) | 추론·요약·생성 |
| 시크릿/ID | Key Vault, Managed Identity | 무암호 인증, 키 관리 |
| 관찰성 | Azure Monitor, App Insights, Log Analytics, Foundry Tracing | 노드별 추적·감사 |
| 거버넌스 | Purview, Defender for Cloud, Azure Policy | 데이터 계보·분류, 위협 탐지, 정책 강제 |

---

## 4. 주요 고려사항 (Key Considerations)

### 연합·데이터 레지던시 ("Data Behind Glass" 핵심)
- **데이터 비이동 원칙**: raw PHI는 파트너 노드 밖으로 반출 금지. 반출물은 비식별 집계 지표·모델 가중치로 제한.
- **데이터 레지던시**: 각 노드는 해당 지역 리전에 고정(예: Korea Central), 크로스 리전 전송 통제.
- **테넌트 격리**: 파트너별 독립 구독/테넌트 + Entra B2B로 최소 권한 접근.

### 규정 준수 & 프라이버시
- **HIPAA / GDPR / 국내 의료법(개인정보보호법·의료법)** 준수, Microsoft와 **BAA** 체결.
- **비식별화 강제**: Azure Health De-identification service로 노드 반입 데이터 처리, 프롬프트·로그 PHI 최소화.
- **데이터 계보**: Purview로 어떤 데이터가 어느 모델·잡에 입력됐는지 추적.

### 보안
- **프라이빗 네트워킹**: 모든 PaaS를 Private Endpoint로, 퍼블릭 액세스 차단.
- **무암호 인증**: Managed Identity + Key Vault, 시크릿 하드코딩 금지.
- **채널 검증**: 노드↔제어 평면 통신 암호화·블라인드, 반출 게이트에서 비식별 검증.

### 검증 & 신뢰 (Validate 프로그램 대응)
- **편향·일반화 평가**: 다인구집단 데이터로 성능 드리프트·형평성 지표 측정, 단일 기관 과적합 방지.
- **평가 파이프라인**: 정확도·안전성·편향 정기 벤치마킹, 회귀 방지.
- **설명가능성**: 검증 리포트로 성능·한계 투명 공개, 임상 도입 신뢰 확보.

### 배포 & 운영 (Deploy 프로그램 대응)
- **Human-in-the-loop**: AI는 의사결정 지원, 임상의 승인 게이트 유지.
- **모델 버전 관리**: 모델·프롬프트 변경 이력(GitHub), 롤백 가능.
- **비용**: gpt 계열은 `max_completion_tokens` 사용, 단순 작업은 소형 모델 라우팅.
- **고가용성**: Zone-redundant(ZRS, 존 중복 배포), 노드별 DR.

---

## 다음 단계 (선택)
- `infra/` Terraform 스캐폴딩(단일 파트너 노드) — 요청 시 추가.
- 영문판(`README.en.md`, `ARCHITECTURE.en.md`) — 요청 시 추가.
