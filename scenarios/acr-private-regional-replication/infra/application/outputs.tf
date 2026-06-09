output "resource_group_name" {
  value       = azurerm_resource_group.this.name
  description = "생성된 Resource Group 이름"
}

output "acr_id" {
  value       = azurerm_container_registry.this.id
  description = "ACR 리소스 ID"
}

output "acr_name" {
  value       = azurerm_container_registry.this.name
  description = "ACR 이름 (replica 추가 시 사용)"
}

output "acr_login_server" {
  value       = azurerm_container_registry.this.login_server
  description = "ACR 로그인 서버 FQDN"
}

output "private_endpoint_ip" {
  value       = azurerm_private_endpoint.acr.private_service_connection[0].private_ip_address
  description = "ACR Private Endpoint의 사설 IP"
}

output "vnet_id" {
  value       = azurerm_virtual_network.this.id
  description = "spoke VNet ID. platform의 linked_vnet_ids에 넣어 중앙 zone에 연결할 때 사용."
}
