# azure-ai-platform

Azure 리소스 배포 및 검증을 위한 **시나리오 기반** 리포지토리.
각 시나리오는 독립된 작은 repo처럼, 자체 인프라 배포 코드와 문서를 가진다.

## 디렉토리 컨벤션

```
scenarios/
  <리소스-시나리오-키워드>/        # kebab-case, 예: acr-private-regional-replication
    DESIGN.md                       # 설계 문서
    PLAN.md                         # 구현 계획
    README.md                       # 시나리오 설명 + 배포/재현 절차
    infra/                          # 독립 배포용 IaC (Terraform)
      providers.tf
      variables.tf
      main.tf
      outputs.tf
      terraform.tfvars.example
      .gitignore
```

- 최상위는 `scenarios/` 아래에 시나리오별 폴더를 둔다.
- 시나리오 폴더는 다른 시나리오에 의존하지 않는다(독립 배포/삭제 가능).
- IaC 코드는 시나리오 폴더 하위 `infra/`에 둔다.

## 시나리오 인덱스

| 시나리오 | 설명 |
| --- | --- |
| [`acr-private-regional-replication`](./scenarios/acr-private-regional-replication/) | Private ACR + regional replication 에러 재현 (replica 구성 직전 환경까지 배포) |
| [`acr-pe-ip-switch-downtime`](./scenarios/acr-pe-ip-switch-downtime/) | ACR Private Endpoint IP 유형(Static↔Dynamic) 전환 시 트래픽 중단 시간 측정 (probe + 전환 + 분석) |
| [`aks-multinic-cn-series`](./scenarios/aks-multinic-cn-series/) | AKS(Azure CNI Overlay)에 Multus로 2nd NIC 부착 PoC + CN-Series 설계/EKS 비교 |

## 새 시나리오 추가

1. `scenarios/<이름>/` 폴더 생성 (kebab-case)
2. `infra/`에 IaC 작성, `README.md`에 배포/검증 절차 문서화
3. 위 인덱스 표에 한 줄 추가
