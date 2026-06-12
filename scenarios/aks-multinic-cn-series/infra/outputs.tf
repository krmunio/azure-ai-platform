output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "get_credentials_command" {
  description = "kubeconfig 가져오기"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name}"
}

output "secondary_nic_subnet_id" {
  value = azurerm_subnet.secondary_nic.id
}

output "cn_pod_subnet_id" {
  description = "Approach B(Azure CNI delegate) NAD에서 사용할 서브넷 ID"
  value       = azurerm_subnet.cn_pod.id
}
