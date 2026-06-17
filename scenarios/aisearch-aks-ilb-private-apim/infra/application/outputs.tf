output "resource_group_name" {
  value       = azurerm_resource_group.this.name
  description = "Resource Group 이름"
}

output "vnet_id" {
  value       = azurerm_virtual_network.this.id
  description = "VNet ID (platform 레이어 linked_vnet_ids에 사용)"
}

output "aks_name" {
  value       = azurerm_kubernetes_cluster.this.name
  description = "AKS 클러스터 이름"
}

output "ilb_ip" {
  value       = var.ilb_ip
  description = "AKS 내부 LoadBalancer(ILB) 사설 IP"
}

output "apim_name" {
  value       = azurerm_api_management.this.name
  description = "APIM 인스턴스 이름"
}

output "apim_id" {
  value       = azurerm_api_management.this.id
  description = "APIM 리소스 ID (SPL target)"
}

output "apim_private_endpoint_ip" {
  value       = azurerm_private_endpoint.apim.private_service_connection[0].private_ip_address
  description = "APIM 인바운드 Private Endpoint 사설 IP"
}

output "search_service_name" {
  value       = azurerm_search_service.this.name
  description = "Azure AI Search 서비스 이름"
}

output "shared_private_link_status" {
  value       = azurerm_search_shared_private_link_service.apim.status
  description = "AI Search Shared Private Link 연결 상태 (수동 승인 전에는 Pending)"
}
