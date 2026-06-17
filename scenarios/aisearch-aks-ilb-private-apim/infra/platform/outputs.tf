output "resource_group_name" {
  value       = azurerm_resource_group.dns.name
  description = "중앙 DNS Resource Group 이름"
}

output "apim_private_dns_zone_id" {
  value       = azurerm_private_dns_zone.apim.id
  description = "APIM Private Link DNS Zone ID (application 레이어 zone group에서 사용)"
}

output "apim_private_dns_zone_name" {
  value       = azurerm_private_dns_zone.apim.name
  description = "APIM Private Link DNS Zone 이름"
}
