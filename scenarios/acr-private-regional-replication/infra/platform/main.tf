resource "azurerm_resource_group" "dns" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_private_dns_zone" "acr" {
  name                = var.private_dns_zone_name
  resource_group_name = azurerm_resource_group.dns.name
  tags                = var.tags
}

# 중앙에서 spoke VNet들을 이 zone에 연결(VNet Link)한다.
resource "azurerm_private_dns_zone_virtual_network_link" "spoke" {
  for_each = var.linked_vnet_ids

  name                  = each.key
  resource_group_name   = azurerm_resource_group.dns.name
  private_dns_zone_name = azurerm_private_dns_zone.acr.name
  virtual_network_id    = each.value
  registration_enabled  = false
  tags                  = var.tags
}
