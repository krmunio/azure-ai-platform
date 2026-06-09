# ACR Private + Regional Replication 재현 시나리오

Azure Container Registry(ACR)를 **private**(public network access 비활성화 + Private Endpoint)으로
구성한 상태에서 **regional replication(geo-replication)** 을 추가할 때 발생하는 에러를 재현하기 위한
시나리오다.

이 폴더의 Terraform 코드는 **regional replica 구성 직전까지의 환경**만 배포한다.
replica는 배포 완료 후 아래 "에러 재현 절차"에서 별도로 추가한다.

- 설계: [`DESIGN.md`](./DESIGN.md)
- 구현 계획: [`PLAN.md`](./PLAN.md)
- 인프라 코드: [`infra/`](./infra/) — `platform/`(중앙 관리)과 `application/`(워크로드)로 분리

## 인프라 구성 (`infra/`)

| 레이어 | 폴더 | 책임 | 비고 |
| --- | --- | --- | --- |
| platform | [`infra/platform/`](./infra/platform/) | 중앙(connectivity) 구독에서 **Private DNS Zone(`privatelink.azurecr.io`)** 및 VNet Link 관리 | 별도 state/구독 |
| application | [`infra/application/`](./infra/application/) | ACR(Premium, public off) + VNet/Subnet + Private Endpoint 등 **워크로드** | replica 구성 직전 상태 |

두 레이어는 **독립된 Terraform state**로 운영하며, application은 platform이 만든 zone을
**`data` 블록(cross-subscription)으로 조회**한다(원격 state 직접 결합 없음).

## 배포되는 리소스

### platform 레이어
| 리소스 | 비고 |
| --- | --- |
| Resource Group | 중앙 DNS RG (`central-dns-rg` 기본) |
| Private DNS Zone | `privatelink.azurecr.io` |
| VNet Link | `linked_vnet_ids`로 spoke VNet 연결 (선택) |

### application 레이어
| 리소스 | 비고 |
| --- | --- |
| Resource Group | `koreacentral` (기본) |
| Virtual Network + Subnet | Private Endpoint 용 |
| Azure Container Registry | **Premium**, `public_network_access_enabled = false`, `admin_enabled = false` |
| Private Endpoint | ACR `registry` subresource |

> **Private DNS Zone은 application에서 생성하지 않고 platform(중앙)에서 관리한다.**
> Private Endpoint A 레코드 등록은 기본적으로 중앙 **Azure Policy(DeployIfNotExists)** 가 처리한다고 가정한다.
> `use_central_dns_zone_group = true`로 설정하면 application이 중앙 zone을 `data` 블록으로 조회해
> Private Endpoint에 zone group을 생성한다(cross-subscription 쓰기 권한 필요).
>
> `georeplications` 블록은 의도적으로 포함하지 않았다 (replica 구성 직전 상태).

## 사전 요구사항

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- 인증된 Azure CLI (`az login`) 또는 동등한 자격증명
- ACR Premium 및 Private Endpoint를 만들 수 있는 구독 권한

## 배포 절차

배포 순서: **platform → application**.

### 1. platform (중앙 DNS) — 필요 시

중앙 Private DNS Zone이 아직 없다면 먼저 배포한다(이미 중앙 팀이 관리 중이면 생략 가능).

```bash
cd scenarios/acr-private-regional-replication/infra/platform
cp terraform.tfvars.example terraform.tfvars   # subscription_id 등 조정
terraform init && terraform apply
```

### 2. application (워크로드)

```bash
cd scenarios/acr-private-regional-replication/infra/application
cp terraform.tfvars.example terraform.tfvars   # 필요 시 값 조정
terraform init
terraform plan
terraform apply
```

`apply` 완료 시점이 곧 **regional replica 구성 직전 상태**다.
출력값(`acr_name`, `acr_login_server`, `resource_group_name`, `vnet_id` 등)은 다음 단계에서 사용한다.

> 중앙 zone에 spoke VNet 연결이 필요하면, application의 `vnet_id` 출력을 platform의
> `linked_vnet_ids`에 넣고 platform을 다시 `apply`한다.

## 에러 재현 절차 (replica 추가)

배포가 끝난 뒤 다른 리전 replica를 추가하며 에러를 재현한다. 두 방법 중 하나를 사용한다.

### 방법 1: Azure CLI

```bash
cd scenarios/acr-private-regional-replication/infra/application
ACR_NAME=$(terraform output -raw acr_name)

az acr replication create \
  --registry "$ACR_NAME" \
  --location japaneast
```

### 방법 2: Terraform (`georeplications` 블록 추가)

`infra/application/main.tf`의 `azurerm_container_registry.this`에 아래 블록을 추가한 뒤 `terraform apply`:

```hcl
  georeplications {
    location                = "japaneast"
    zone_redundancy_enabled = false
    tags                    = var.tags
  }
```

발생하는 에러 메시지와 상황을 기록한다.

## 정리(삭제)

application → platform 역순으로 삭제한다.

```bash
cd scenarios/acr-private-regional-replication/infra/application
terraform destroy

cd ../platform
terraform destroy
```
