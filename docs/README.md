# docs — 지식 베이스 (Knowledge Base)

`scenarios/`(배포·재현 IaC), `case-studies/`(실제 사례 문헌)와 별개로,
**개념 정리·컴플라이언스 가이드 등 범용 참조 문서**를 모아두는 곳.

특정 시나리오나 실제 사례에 묶이지 않는, 재사용 가능한 지식을 축적한다.

## 구조

```
docs/
  concepts/                      # 개념/패턴 정리 (1주제 = 1 markdown)
    facade-pattern.md
    clinical-data-warehouse.md
  compliance/                    # 규정·거버넌스 가이드
    korea-medical-data-cloud/
      README.md                  # 본문 (요약·체크리스트)
      *.pptx                      # 브리핑 자료
```

## 인덱스

### 개념 (`concepts/`)

| 문서 | 설명 |
| --- | --- |
| [`facade-pattern`](./concepts/facade-pattern.md) | 파사드 디자인 패턴 — 복잡한 서브시스템을 단일 인터페이스로 단순화 |
| [`clinical-data-warehouse`](./concepts/clinical-data-warehouse.md) | CDW — 임상 데이터 웨어하우스, 2차 활용(연구·AI) 기반 |
| [`dw-lake-lakehouse-delta`](./concepts/dw-lake-lakehouse-delta.md) | Data Warehouse · Data Lake · Lakehouse · Delta Lake 비교 + 의료 매핑 |

### 컴플라이언스 (`compliance/`)

| 가이드 | 설명 |
| --- | --- |
| [`korea-medical-data-cloud`](./compliance/korea-medical-data-cloud/) | 국내 의료데이터 Azure 이관 시 법령·용도별(진료/연구) 고려사항·체크리스트 + 브리핑 덱 |

## 새 문서 추가

1. 개념이면 `docs/concepts/<주제-kebab>.md`, 가이드면 `docs/compliance/<주제-kebab>/`에 작성.
2. 위 인덱스 표에 한 줄 추가.
3. 문서 하나 = 한 주제. 짧고 검색 가능하게.
