# ACR Private + Regional Replication 재현 환경 구현 계획

> **For agentic workers:** 본 계획은 Terraform IaC 작성 작업이다. 단위 테스트 프레임워크 대신
> `terraform fmt -check`와 `terraform validate`를 검증 단계로 사용한다. 체크박스로 진행을 추적한다.

**Goal:** ACR을 private(public access off + Private Endpoint)으로 배포하는, regional replica 구성 직전까지의 Terraform 인프라를 작성한다.

**Architecture:** 접근 방식 A — `scenarios/acr-private-regional-replication/infra/`에 모듈 분리 없는 평면 Terraform 구성. azurerm provider 사용.

**Tech Stack:** Terraform, azurerm provider, Azure(ACR Premium, VNet, Private Endpoint, Private DNS Zone).

---

## File Structure

```
scenarios/acr-private-regional-replication/
  DESIGN.md                 # (작성됨)
  PLAN.md                   # (이 파일)
  README.md                 # 시나리오 안내 + 배포/재현 절차
  infra/
    providers.tf            # terraform/azurerm 버전 핀 + provider
    variables.tf            # 입력 변수
    main.tf                 # 리소스 정의
    outputs.tf              # 출력값
    terraform.tfvars.example
    .gitignore              # state/.terraform 등 제외
repo 루트 README.md         # 전체 안내 + 시나리오 인덱스
```

---

### Task 1: providers.tf

**Files:**
- Create: `scenarios/acr-private-regional-replication/infra/providers.tf`

- [ ] **Step 1: 작성**

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
}
```

---

### Task 2: variables.tf

**Files:**
- Create: `scenarios/acr-private-regional-replication/infra/variables.tf`

- [ ] **Step 1: 작성**

```hcl
variable "location" {
  type        = string
  default     = "koreacentral"
  description = "기본(primary) 리전"
}

variable "name_prefix" {
  type        = string
  default     = "acrpriv"
  description = "리소스 이름 접두사 (소문자/숫자)"
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "RG 이름 (미지정 시 name_prefix 기반 파생)"
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.50.0.0/16"]
}

variable "pe_subnet_prefix" {
  type        = list(string)
  default     = ["10.50.1.0/24"]
}

variable "acr_sku" {
  type        = string
  default     = "Premium"
  description = "geo-replication은 Premium 필수"
}

variable "tags" {
  type    = map(string)
  default = {
    scenario = "acr-private-regional-replication"
    managed_by = "terraform"
  }
}
```

---

### Task 3: main.tf

**Files:**
- Create: `scenarios/acr-private-regional-replication/infra/main.tf`

- [ ] **Step 1: 작성** (locals + RG + VNet/Subnet + ACR + Private DNS + Private Endpoint, georeplications 미포함)

```hcl
locals {
  rg_name  = coalesce(var.resource_group_name, "${var.name_prefix}-rg")
  acr_name = "${var.name_prefix}${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = local.rg_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "pe" {
  name                 = "${var.name_prefix}-pe-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.pe_subnet_prefix
}

resource "azurerm_container_registry" "this" {
  name                          = local.acr_name
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  sku                           = var.acr_sku
  admin_enabled                 = false
  public_network_access_enabled = false
  tags                          = var.tags
  # NOTE: georeplications 블록은 의도적으로 미포함 (replica 구성 직전 상태)
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  name                  = "${var.name_prefix}-acr-dns-link"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "acr" {
  name                = "${var.name_prefix}-acr-pe"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.name_prefix}-acr-psc"
    private_connection_resource_id = azurerm_container_registry.this.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr.id]
  }
}
```

- [ ] **Step 2: random provider를 providers.tf required_providers에 추가**

```hcl
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
```

---

### Task 4: outputs.tf

**Files:**
- Create: `scenarios/acr-private-regional-replication/infra/outputs.tf`

- [ ] **Step 1: 작성**

```hcl
output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "acr_id" {
  value = azurerm_container_registry.this.id
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "private_endpoint_ip" {
  value = azurerm_private_endpoint.acr.private_service_connection[0].private_ip_address
}
```

---

### Task 5: terraform.tfvars.example + .gitignore

**Files:**
- Create: `scenarios/acr-private-regional-replication/infra/terraform.tfvars.example`
- Create: `scenarios/acr-private-regional-replication/infra/.gitignore`

- [ ] **Step 1: tfvars.example 작성**

```hcl
location            = "koreacentral"
name_prefix         = "acrpriv"
# resource_group_name = "my-acr-rg"
# vnet_address_space  = ["10.50.0.0/16"]
# pe_subnet_prefix    = ["10.50.1.0/24"]
```

- [ ] **Step 2: .gitignore 작성**

```
.terraform/
*.tfstate
*.tfstate.*
crash.log
*.tfvars
!*.tfvars.example
.terraform.lock.hcl
```

---

### Task 6: README (시나리오 + repo 루트)

**Files:**
- Create: `scenarios/acr-private-regional-replication/README.md`
- Create: `README.md` (repo 루트)

- [ ] **Step 1: 시나리오 README** — 배경, 배포 절차, 에러 재현 절차(az acr replication create / georeplications 추가) 명시
- [ ] **Step 2: 루트 README** — repo 목적(시나리오별 독립 배포/테스트), 디렉토리 컨벤션, 시나리오 인덱스

---

### Task 7: 정적 검증 + 커밋

- [ ] **Step 1: fmt**

Run: `terraform -chdir=scenarios/acr-private-regional-replication/infra fmt -check -recursive`
Expected: 변경 없음(0 exit). 필요시 `fmt`로 정렬.

- [ ] **Step 2: validate** (terraform 설치 가능 시)

Run: `terraform -chdir=.../infra init -backend=false && terraform -chdir=.../infra validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: 커밋**

```bash
git add scenarios README.md
git commit -m "feat: ACR private + regional replica 직전 환경 Terraform IaC"
```

---

## Self-Review

- Spec 커버리지: RG/VNet/Subnet/ACR(Premium,public off)/Private DNS/Private Endpoint 모두 Task 3에 포함, georeplications 제외 확인. outputs 4종 Task 4. README 재현절차 Task 6. ✅
- Placeholder: 없음(모든 코드 블록 구체화). ✅
- 타입 일관성: `azurerm_container_registry.this`, `local.acr_name`, output 참조 일치. ✅
