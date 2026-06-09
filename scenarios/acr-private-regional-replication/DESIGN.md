# ACR Private + Regional Replication 재현 환경 설계

## 배경 / 목적

고객이 Azure Container Registry(ACR)를 private(public network access 비활성화 + Private Endpoint)으로
구성한 상태에서 **regional replication(geo-replication)** 을 설정할 때 에러가 발생한다고 보고했다.

이 에러를 재현·검증하기 위해, **regional replica 구성 직전까지의 인프라**를 Terraform IaC로 배포한다.
배포 완료 후 별도(수동 또는 후속) 단계에서 replica를 추가하며 에러를 재현하는 것이 목표다.

## 범위

- 포함: RG, VNet/Subnet, ACR(Premium, public access off), Private Endpoint
- 제외: `georeplications` 블록 (← 에러 재현 단계에서 별도 추가)
- 제외: Private DNS Zone(`privatelink.azurecr.io`) — **별도(중앙) 구독에서 중앙 관리**.
  A 레코드 등록은 기본적으로 중앙 Azure Policy(DeployIfNotExists)가 처리한다고 가정.

## 리포지토리 구조

이 repo는 앞으로 Azure 리소스를 **시나리오별 독립 폴더**로 배포·테스트한다.
각 시나리오는 독립된 작은 repo처럼 자체 인프라 배포 폴더를 가진다.

```
scenarios/
  acr-private-regional-replication/
    DESIGN.md               # 이 설계 문서
    infra/
      providers.tf            # azurerm provider + required_version
      variables.tf            # location, prefix, address space 등 입력값
      main.tf                 # 모든 리소스 정의
      outputs.tf              # acr login server/id, PE IP, RG name 등
      terraform.tfvars.example
    README.md                 # 시나리오 설명 + 배포/재현 절차
README.md                     # repo 전체 안내 + 시나리오 인덱스
```

네이밍 컨벤션:
- 최상위: `scenarios/`
- 시나리오 폴더: `<리소스/시나리오>-<핵심키워드>` (kebab-case), 예: `acr-private-regional-replication`
- 인프라 배포 코드: 시나리오 폴더 하위 `infra/`

## Terraform 구성 (접근 방식 A: 단일 디렉토리 평면 구성)

모듈 분리 없이 `infra/` 안에 평면 구성. 단일 시나리오 1회성 재현 테스트이므로 모듈화는 YAGNI.

### 입력 변수 (variables.tf)
- `location` (default `koreacentral`)
- `prefix` / `name_prefix` — 리소스 이름 접두사 (default 예: `acrpriv`)
- `resource_group_name` (default 파생)
- `vnet_address_space` (default `10.50.0.0/16`)
- `pe_subnet_prefix` (default `10.50.1.0/24`)
- `acr_sku` (default `Premium` — geo-replication은 Premium 필수)
- `central_private_dns_zone_id` (default `null`) — 중앙 구독의 privatelink.azurecr.io zone 리소스 ID.
  설정 시에만 Private Endpoint에 zone group 생성, 미설정 시 중앙 Policy가 A 레코드 등록한다고 가정.
- `tags` (map)

### 리소스 (main.tf)
1. `azurerm_resource_group`
2. `azurerm_virtual_network`
3. `azurerm_subnet` (private endpoint용; `private_endpoint_network_policies` 적절히 설정)
4. `azurerm_container_registry`
   - `sku = "Premium"`
   - `public_network_access_enabled = false`
   - `admin_enabled = false`
   - **georeplications 블록 없음**
5. `azurerm_private_endpoint`
   - `subresource_names = ["registry"]`
   - `private_dns_zone_group`는 `central_private_dns_zone_id`가 지정된 경우에만 동적으로 생성
     (중앙 구독 zone 참조). 기본은 미생성 → 중앙 Policy가 레코드 등록.

> Private DNS Zone 및 VNet Link는 이 구성에서 생성하지 않는다 (중앙 구독에서 관리).

### 출력 (outputs.tf)
- `resource_group_name`
- `acr_id`
- `acr_login_server`
- `private_endpoint_ip`

### Provider (providers.tf)
- `azurerm` provider, `features {}`
- `required_version` / `required_providers` 핀

## 에러 재현 절차 (README에 문서화)

1. `cd scenarios/acr-private-regional-replication/infra`
2. `cp terraform.tfvars.example terraform.tfvars` 후 값 조정
3. `terraform init && terraform apply`
4. 배포 완료 = replica 직전 상태
5. 이후 replica 추가로 에러 재현:
   - CLI: `az acr replication create --registry <name> --location <2nd region>`
   - 또는 Terraform: `georeplications` 블록 추가 후 `apply`
6. 발생 에러/메시지 기록

## 검증

- `terraform fmt -check`, `terraform validate` 로 정적 검증 (apply는 실제 Azure 구독 필요하므로 사용자 환경에서 수행)

## 비범위 (YAGNI)

- 로컬 모듈 분리, 멀티 environment/workspace, 원격 state backend
- CI 파이프라인
