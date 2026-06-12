output "resource_group_name" {
  description = "리소스 그룹 이름"
  value       = azurerm_resource_group.this.name
}

output "aks_name" {
  description = "AKS 클러스터 이름"
  value       = azurerm_kubernetes_cluster.this.name
}

output "acr_name" {
  description = "ACR 이름"
  value       = azurerm_container_registry.this.name
}

output "acr_login_server" {
  description = "ACR 로그인 서버"
  value       = azurerm_container_registry.this.login_server
}

output "get_credentials_command" {
  description = "kubeconfig 가져오기 명령"
  value       = "az aks get-credentials -g ${azurerm_resource_group.this.name} -n ${azurerm_kubernetes_cluster.this.name}"
}
