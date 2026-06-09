output "resource_group_name" {
  value       = azurerm_resource_group.dns.name
  description = "중앙 DNS Resource Group 이름"
}

output "private_dns_zone_id" {
  value       = azurerm_private_dns_zone.acr.id
  description = "중앙 Private DNS Zone 리소스 ID"
}

output "private_dns_zone_name" {
  value       = azurerm_private_dns_zone.acr.name
  description = "중앙 Private DNS Zone 이름 (application data 조회 시 사용)"
}
