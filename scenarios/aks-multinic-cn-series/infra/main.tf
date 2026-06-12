resource "azurerm_resource_group" "this" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "node" {
  name                 = "node-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.node_subnet_cidr]
}

# 2nd NIC(routable) 서브넷 — macvlan/ipvlan(Approach A)용 호스트 보조 NIC가 위치
resource "azurerm_subnet" "secondary_nic" {
  name                 = "secondary-nic-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.secondary_nic_subnet_cidr]
}

# Approach B(Azure CNI delegate)용 전용 pod 서브넷(routable)
resource "azurerm_subnet" "cn_pod" {
  name                 = "cn-pod-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.cn_pod_subnet_cidr]
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = "${var.prefix}-aks"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = azurerm_subnet.node.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.pod_cidr_overlay
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
  }

  tags = var.tags
}

# 관리형 Multus 애드온 (preview) — 기본 az CLI에는 활성화 플래그가 없다.
# 활성화에는 `aks-preview` 확장 + 기능 등록(EnableManagedMultus) + `--enable-managed-multus`가
# 필요하며, `--network-plugin none`을 요구할 수 있어 본 시나리오의 Azure CNI Overlay와 충돌할 수 있다.
# 따라서 자동 실행하지 않고, enable_managed_multus=true일 때 수동 절차를 안내만 한다(DESIGN.md §5/§8, README 참조).
# 실제로 테스트 가능한 경로는 수동 DaemonSet(k8s/multus-daemonset/)이다.
resource "null_resource" "managed_multus_guidance" {
  count = var.enable_managed_multus ? 1 : 0

  triggers = {
    cluster_id = azurerm_kubernetes_cluster.this.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "[INFO] 관리형 Multus는 preview이며 자동 활성화하지 않습니다. 다음 절차를 직접 검증/실행하세요:"
      echo "  1) az extension add --name aks-preview (또는 update)"
      echo "  2) az feature register --namespace Microsoft.ContainerService --name EnableManagedMultus"
      echo "  3) az provider register --namespace Microsoft.ContainerService"
      echo "  4) 클러스터 생성 시 --enable-managed-multus (Overlay 호환성/--network-plugin 요구사항은 최신 문서 확인)"
      echo "  대안(권장, 테스트 가능): kubectl apply -f ../k8s/multus-daemonset/multus-daemonset.yaml"
    EOT
  }
}
