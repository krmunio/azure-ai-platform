# CDW (Clinical Data Warehouse, 임상 데이터 웨어하우스)

의료기관의 **여러 원천 시스템(EMR·처방·검사·영상·병리 등)의 데이터를 한곳에 통합·저장해
분석/연구에 쓰는 데이터 웨어하우스**. 의료데이터 "연구(2차 활용) 영역"의 핵심 기반.

## 개념

- 흩어진 진료 데이터를 **추출 → 정제 → 표준화 → 적재(ETL)**해 통합 저장소로 구성.
- 목적: **2차 활용** — 임상연구, 통계, 질 관리, AI 학습, 코호트 발굴.
- 운영계(진료 실시간)와 분리된 **분석 전용** 저장소.

## 원천 → CDW

```
EMR / OCS(처방) / LIS(검사) / PACS(영상) / 병리
        │  ETL (추출·정제·표준화·가명처리)
        ▼
     [ CDW ]  ──▶ 연구·통계·AI·BI
```

## 국내 의료데이터 맥락 (중요)

CDW는 **연구(2차 활용)** 목적 → 국내법상 다음 규칙이 그대로 적용된다
([korea-medical-data-cloud 가이드](../compliance/korea-medical-data-cloud/) 참고):

- 적재 시 **가명처리** (실명 그대로 넣지 않음, 개인정보보호법 §28-2).
- **데이터심의위원회(DRB) 심의·승인** 후 활용.
- **재식별 금지**(§28-5), 매핑키 격리.
- 진료계(운영)와 **단방향** 연계.

즉 **CDW = "연구영역"의 데이터 저장·통합 계층**.

## Azure 구현 매핑

| CDW 구성요소 | Azure 서비스 |
| --- | --- |
| 원천 연계·ETL | Data Factory / Synapse Pipeline |
| 데이터 레이크 | ADLS Gen2 |
| 웨어하우스/분석 | Synapse Analytics · Databricks · Microsoft Fabric |
| 의료 표준화(FHIR) | Azure Health Data Services |
| 거버넌스 | Microsoft Purview |
| BI/시각화 | Power BI |

## 관련 개념 구분

- **CDW**: 임상데이터 통합·분석 저장소 (기관 단위).
- **CDM (Common Data Model, 예: OMOP)**: 여러 기관 데이터를 **공통 스키마**로 표준화 →
  다기관 공동연구·분산연구망(예: 국내 FEEDER-NET)에서 사용.
- CDW를 CDM 형태로 변환해 표준 연구에 활용하는 경우가 많음.
