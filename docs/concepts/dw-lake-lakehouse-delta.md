# DW vs Data Lake vs Lakehouse vs Delta Lake

혼동되는 이유: **DW/Data Lake/Lakehouse는 "아키텍처(저장·분석 방식)"**,
**Delta Lake는 그걸 가능하게 하는 "저장 포맷/기술"** — 층위가 다르다.

## 한눈에

| | Data Warehouse (DW) | Data Lake | Lakehouse | Delta Lake |
| --- | --- | --- | --- | --- |
| **정체** | 아키텍처 | 아키텍처 | 아키텍처 | **스토리지 포맷/레이어** |
| **데이터** | 정형(가공됨) | 정형+비정형(원본) | 정형+비정형 통합 | (테이블 저장 방식) |
| **스키마** | Schema-on-write | Schema-on-read | 둘 다 | — |
| **트랜잭션(ACID)** | ✅ | ❌ | ✅ | ✅ (핵심 제공) |
| **주 용도** | BI·리포팅 | 원본 적재·ML | BI + ML 통합 | Lake에 신뢰성 부여 |
| **비용/유연성** | 비쌈/경직 | 저렴/무질서 위험 | 중간/균형 | — |

## 각각 한 줄

- **Data Warehouse**: **정형 데이터를 미리 정제·스키마화**해 저장하는 BI 전용 저장소.
  빠른 쿼리·신뢰성, 단 비정형·ML엔 약함. (예: Synapse Dedicated SQL, Snowflake, Redshift)
- **Data Lake**: **원본 그대로(정형+비정형)** 싸게 대량 적재. 유연하지만 통제 없으면
  **"Data Swamp(늪)"**. (예: ADLS Gen2, S3)
- **Lakehouse**: Data Lake 위에 **DW의 신뢰성(ACID·거버넌스)을 얹은** 통합 아키텍처.
  한 저장소에서 **BI + ML 둘 다**. (예: Databricks, Microsoft Fabric)
- **Delta Lake**: Data Lake(Parquet 파일) 위에 **트랜잭션 로그를 더해 ACID·버전관리·타임트래블**을
  주는 **오픈 스토리지 포맷**. → **Lakehouse를 실현하는 핵심 엔진**.

## 관계도

```
Data Lake (원본 파일 저장, ADLS/S3)
      │  + Delta Lake (ACID·버전·스키마 강제)
      ▼
  Lakehouse (BI + ML 통합 아키텍처)   ← Data Warehouse의 신뢰성 흡수
```

→ **"Data Lake + Delta Lake = Lakehouse"**, Lakehouse는 DW와 Lake의 장점을 합친 것.

## 관련 오픈 테이블 포맷 (Delta 계열 "vs")

- **Delta Lake** (Databricks 주도) · **Apache Iceberg** (Netflix 발) · **Apache Hudi** (Uber 발)
- 셋 다 "Lake에 ACID·버전·스키마"를 주는 **오픈 테이블 포맷** — 목적 동일, 생태계 차이.

## 언제 뭘

- 정형 BI만, 성능 최우선 → **DW**
- 원본·로그·비정형 대량 적재 → **Data Lake**
- BI+ML 통합, 한 플랫폼 → **Lakehouse (+ Delta/Iceberg)**

## 의료데이터 맥락 매핑

- **CDW(임상 데이터 웨어하우스)** → 정형 진료·통계 중심의 **DW** 성격
  ([clinical-data-warehouse](./clinical-data-warehouse.md) 참고).
- **연구·AI 영역** → 비정형(임상노트·영상) + ML 필요 → **Lakehouse**(ADLS Gen2 + Delta,
  Databricks/Fabric)가 적합.
- 국내법 관점: 어느 계층이든 **연구용은 가명처리 후 적재·재식별 금지**가 전제
  ([korea-medical-data-cloud 가이드](../compliance/korea-medical-data-cloud/) 참고).
