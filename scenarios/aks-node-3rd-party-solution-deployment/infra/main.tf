resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = var.tags
}

# 3rd party 솔루션 이미지/설치 패키지 반입용 사설 레지스트리
resource "azurerm_container_registry" "this" {
  name                = replace("${var.name_prefix}acr${random_string.suffix.result}", "-", "")
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Premium"
  admin_enabled       = false
  tags                = var.tags
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = "${var.name_prefix}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = "${var.name_prefix}-aks"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name       = "system"
    node_count = var.system_node_count
    vm_size    = var.system_node_vm_size
    os_sku     = "Ubuntu"
    type       = "VirtualMachineScaleSets"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
  }

  tags = var.tags
}

# 3rd party 솔루션 검증 대상 워커 노드풀
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = var.user_node_vm_size
  node_count            = var.user_node_count
  os_type               = "Linux"
  os_sku                = var.user_node_os_sku
  mode                  = "User"
  tags                  = var.tags
}

# AKS의 kubelet 아이덴티티가 ACR에서 이미지를 pull할 수 있도록 권한 부여
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
