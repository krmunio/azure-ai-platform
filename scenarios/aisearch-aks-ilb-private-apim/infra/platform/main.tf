resource "azurerm_resource_group" "dns" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# APIM 인바운드 Private Endpoint 이름 해석을 위한 중앙 Private DNS Zone.
# AI Search의 Shared Private Link(managed PE)는 자체 DNS를 관리하지만,
# VNet 내부 클라이언트가 APIM private endpoint를 해석하려면 이 zone이 필요하다.
resource "azurerm_private_dns_zone" "apim" {
  name                = var.apim_private_dns_zone_name
  resource_group_name = azurerm_resource_group.dns.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each = var.linked_vnet_ids

  name                  = each.key
  resource_group_name   = azurerm_resource_group.dns.name
  private_dns_zone_name = azurerm_private_dns_zone.apim.name
  virtual_network_id    = each.value
  registration_enabled  = false
  tags                  = var.tags
}
