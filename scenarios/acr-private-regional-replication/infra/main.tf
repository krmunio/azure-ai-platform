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

  # NOTE: georeplications 블록은 의도적으로 미포함.
  # 이 환경은 "regional replica 구성 직전" 상태이며,
  # replica는 배포 후 별도 단계(README 참고)에서 추가하며 에러를 재현한다.
}

# NOTE: Private DNS Zone(privatelink.azurecr.io)은 이 구독에서 생성하지 않는다.
# 별도(중앙/connectivity) 구독에서 중앙 관리되며, A 레코드 등록은 기본적으로
# Azure Policy(DeployIfNotExists)로 자동 처리된다.
#
# - var.central_private_dns_zone_id 가 null  : zone group 미생성 (Policy 기반 등록).
# - var.central_private_dns_zone_id 가 설정됨 : 해당 중앙 zone을 참조해 zone group 생성
#                                               (cross-subscription 쓰기 권한 필요).

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

  dynamic "private_dns_zone_group" {
    for_each = var.central_private_dns_zone_id == null ? [] : [var.central_private_dns_zone_id]
    content {
      name                 = "acr-dns-zone-group"
      private_dns_zone_ids = [private_dns_zone_group.value]
    }
  }
}
