# ACR Private + Regional Replication 재현 시나리오

Azure Container Registry(ACR)를 **private**(public network access 비활성화 + Private Endpoint)으로
구성한 상태에서 **regional replication(geo-replication)** 을 추가할 때 발생하는 에러를 재현하기 위한
시나리오다.

이 폴더의 Terraform 코드는 **regional replica 구성 직전까지의 환경**만 배포한다.
replica는 배포 완료 후 아래 "에러 재현 절차"에서 별도로 추가한다.

- 설계: [`DESIGN.md`](./DESIGN.md)
- 구현 계획: [`PLAN.md`](./PLAN.md)
- 인프라 코드: [`infra/`](./infra/)

## 배포되는 리소스

| 리소스 | 비고 |
| --- | --- |
| Resource Group | `koreacentral` (기본) |
| Virtual Network + Subnet | Private Endpoint 용 |
| Azure Container Registry | **Premium**, `public_network_access_enabled = false`, `admin_enabled = false` |
| Private DNS Zone | `privatelink.azurecr.io` + VNet Link |
| Private Endpoint | ACR `registry` subresource + DNS Zone Group |

> `georeplications` 블록은 의도적으로 포함하지 않았다 (replica 구성 직전 상태).

## 사전 요구사항

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- 인증된 Azure CLI (`az login`) 또는 동등한 자격증명
- ACR Premium 및 Private Endpoint를 만들 수 있는 구독 권한

## 배포 절차

```bash
cd scenarios/acr-private-regional-replication/infra

cp terraform.tfvars.example terraform.tfvars
# 필요 시 terraform.tfvars 값 조정 (location, name_prefix 등)

terraform init
terraform plan
terraform apply
```

`apply` 완료 시점이 곧 **regional replica 구성 직전 상태**다.
출력값(`acr_name`, `acr_login_server`, `resource_group_name` 등)은 다음 단계에서 사용한다.

## 에러 재현 절차 (replica 추가)

배포가 끝난 뒤 다른 리전 replica를 추가하며 에러를 재현한다. 두 방법 중 하나를 사용한다.

### 방법 1: Azure CLI

```bash
ACR_NAME=$(terraform -chdir=infra output -raw acr_name)

az acr replication create \
  --registry "$ACR_NAME" \
  --location japaneast
```

### 방법 2: Terraform (`georeplications` 블록 추가)

`infra/main.tf`의 `azurerm_container_registry.this`에 아래 블록을 추가한 뒤 `terraform apply`:

```hcl
  georeplications {
    location                = "japaneast"
    zone_redundancy_enabled = false
    tags                    = var.tags
  }
```

발생하는 에러 메시지와 상황을 기록한다.

## 정리(삭제)

```bash
cd scenarios/acr-private-regional-replication/infra
terraform destroy
```
