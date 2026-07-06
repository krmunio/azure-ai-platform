# Tumor Board Agentic AI — PoC 인프라 스캐폴딩
#
# 이것은 스캐폴딩(뼈대)이다. P0~P2 계층의 핵심 리소스만 실제 선언하고,
# provider 커버리지가 얇거나 느린/비싼 리소스는 ponytail 주석으로 지점만 표시한다.
# 실제 리소스명은 name_prefix + random suffix로 파생 (하드코딩 금지, AGENTS.md 규칙).

locals {
  prefix = "${var.name_prefix}${random_string.suffix.result}"
}

resource "random_string" "suffix" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name_prefix}-poc-rg"
  location = var.location
  tags     = var.tags
}

# ── 네트워크 (Hub-Spoke는 단일 VNet + 서브넷으로 축소; PoC엔 충분) ──────────────
# ponytail: 단일 VNet+서브넷. 진짜 hub-spoke 분리(피어링)는 멀티팀/멀티구독 될 때.
resource "azurerm_virtual_network" "this" {
  name                = "${local.prefix}-vnet"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_prefixes.app]
}

resource "azurerm_subnet" "ai" {
  name                 = "snet-ai"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_prefixes.ai]
}

resource "azurerm_subnet" "data" {
  name                 = "snet-data"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_prefixes.data]
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.subnet_prefixes.pe]
}

# ── 관찰성 (P5에서 Foundry Tracing 연결) ───────────────────────────────────────
resource "azurerm_log_analytics_workspace" "this" {
  name                = "${local.prefix}-law"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_application_insights" "this" {
  name                = "${local.prefix}-appi"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.this.id
  tags                = var.tags
}

# ── 시크릿/ID (무암호 인증) ────────────────────────────────────────────────────
data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "this" {
  name                       = "${local.prefix}-kv"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = var.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = true
  rbac_authorization_enabled = true
  # ponytail: PoC는 서브넷 허용. 실 PHI 전 public_network_access_enabled=false + PE로 잠글 것.
  tags = var.tags
}

# ── 데이터 (P1) ────────────────────────────────────────────────────────────────
resource "azurerm_storage_account" "this" {
  name                            = "${local.prefix}st"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "ZRS" # 고가용성 요건
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
  tags                            = var.tags
}

resource "azurerm_cosmosdb_account" "this" {
  name                = "${local.prefix}-cosmos"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  consistency_policy {
    consistency_level = "Session"
  }
  geo_location {
    location          = var.location
    failover_priority = 0
  }
  tags = var.tags
}

# Azure Health Data Services — FHIR (합성 FHIR 로드 대상)
resource "azurerm_healthcare_workspace" "this" {
  name                = "${local.prefix}hdw"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = var.tags
}

resource "azurerm_healthcare_fhir_service" "this" {
  name                = "${local.prefix}fhir"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  workspace_id        = azurerm_healthcare_workspace.this.id
  kind                = "fhir-R4"

  authentication {
    authority = "https://login.microsoftonline.com/${data.azurerm_client_config.current.tenant_id}"
    audience  = "https://${local.prefix}hdw-${local.prefix}fhir.fhir.azurehealthcareapis.com"
  }
  identity {
    type = "SystemAssigned"
  }
  tags = var.tags
}

# ponytail: DICOM service는 영상분석 에이전트(2차 범위)까지 미룸. 필요 시 아래 블록 활성화.
# resource "azurerm_healthcare_dicom_service" "this" {
#   name         = "${local.prefix}dicom"
#   workspace_id = azurerm_healthcare_workspace.this.id
#   location     = var.location
# }

# ── 지식/RAG (P2) ──────────────────────────────────────────────────────────────
resource "azurerm_search_service" "this" {
  name                = "${local.prefix}-search"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  sku                 = "standard" # 벡터/시맨틱 검색
  tags                = var.tags
}

# ── AI 서비스 (P3): Foundry/OpenAI 모델 + Content Safety ───────────────────────
resource "azurerm_cognitive_account" "aiservices" {
  name                  = "${local.prefix}-aisvc"
  resource_group_name   = azurerm_resource_group.this.name
  location              = var.location
  kind                  = "AIServices" # Foundry 모델 배포 호스트
  sku_name              = "S0"
  custom_subdomain_name = "${local.prefix}-aisvc"
  tags                  = var.tags
}

resource "azurerm_cognitive_deployment" "models" {
  for_each             = { for d in var.model_deployments : d.name => d }
  name                 = each.value.name
  cognitive_account_id = azurerm_cognitive_account.aiservices.id

  model {
    format  = "OpenAI"
    name    = each.value.model
    version = each.value.version
  }
  sku {
    name     = "Standard"
    capacity = each.value.capacity
  }
}

resource "azurerm_cognitive_account" "content_safety" {
  name                = "${local.prefix}-safety"
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  kind                = "ContentSafety" # 환각/유해/jailbreak 완화
  sku_name            = "S0"
  tags                = var.tags
}

# ── 앱/호스팅 (P4) ─────────────────────────────────────────────────────────────
resource "azurerm_container_app_environment" "this" {
  name                       = "${local.prefix}-cae"
  resource_group_name        = azurerm_resource_group.this.name
  location                   = var.location
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id
  infrastructure_subnet_id   = azurerm_subnet.app.id
  tags                       = var.tags
}

# ══════════════════════════════════════════════════════════════════════════════
# 스캐폴딩에서 의도적으로 제외 (활성화 시점을 주석으로 명시)
# ══════════════════════════════════════════════════════════════════════════════
#
# ponytail: AI Foundry Hub/Project + Agent Service(Orchestrator/전문 에이전트)는
#   azurerm 지원이 얇다. azapi provider 또는 배포 후 az CLI/포털/SDK로 구성한다.
#   → POC-PLAN.md P3 참조. Agent 정의는 코드(매니페스트)로 버전관리.
#
# ponytail: Private Endpoint는 서비스마다 반복이라 여기선 미배선. 실 PHI 전(게이트)
#   각 PaaS(kv/st/cosmos/search/aisvc/fhir)에 azurerm_private_endpoint + DNS zone group
#   추가하고 public_network_access_enabled=false로 잠근다.
#
# ponytail: APIM(AI Gateway)은 생성 느리고(수십 분) 비싸다 → PoC 제외. P4 이후 필요 시.
# ponytail: Front Door + WAF, Purview, Defender, 멀티리전 DR도 프로덕션 단계에서.
