locals {
  rg_name      = coalesce(var.resource_group_name, "${var.name_prefix}-rg")
  name_suffix  = random_string.suffix.result
  apim_name    = "${var.name_prefix}-apim-${local.name_suffix}"
  search_name  = "${var.name_prefix}-search-${local.name_suffix}"
  aks_name     = "${var.name_prefix}-aks-${local.name_suffix}"
  ilb_base_url = "http://${var.ilb_ip}"
}

resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

resource "azurerm_resource_group" "this" {
  name     = local.rg_name
  location = var.location
  tags     = var.tags
}

# ---------------------------------------------------------------------------
# 네트워크: 단일 VNet + 3개 서브넷 (aks / apim / private-endpoint)
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network" "this" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.aks_subnet_prefix
}

# APIM Standard v2 아웃바운드 VNet 통합용 서브넷.
# v2의 VNet 통합은 App Service 계열과 동일하게 Microsoft.Web/serverFarms 위임을 사용한다.
resource "azurerm_subnet" "apim" {
  name                 = "snet-apim"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.apim_subnet_prefix

  delegation {
    name = "apim-v2-vnet-integration"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                 = "snet-pe"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = var.pe_subnet_prefix
}

# ---------------------------------------------------------------------------
# AKS (경량, 시스템 노드풀만) — 사설 모델 엔드포인트의 스탠드인
# 실제 GPU 노드풀/모델 서빙은 README의 "실제 GPU·모델로 교체" 절차 참고.
# ---------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "this" {
  name                = local.aks_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = var.name_prefix

  default_node_pool {
    name           = "system"
    node_count     = var.aks_node_count
    vm_size        = var.aks_node_vm_size
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "172.16.0.0/16"
    dns_service_ip    = "172.16.0.10"
  }

  tags = var.tags
}

# AKS 노드(kubelet identity)가 ILB를 aks 서브넷에 만들 수 있도록 네트워크 권한 부여.
resource "azurerm_role_assignment" "aks_network" {
  scope                = azurerm_virtual_network.this.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.this.identity[0].principal_id
}

# ---------------------------------------------------------------------------
# AKS 위 샘플 워크로드: 내부 LoadBalancer(ILB) 서비스
# annotation azure-load-balancer-internal=true → 사설 IP만 노출.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# AKS 위 샘플 워크로드: "모델 엔드포인트" 모의 서버 (nginx + ConfigMap)
#   GET /        → 모의 추론 JSON 응답
#   GET /healthz → readiness/liveness 헬스 체크
# 실제 GPU 모델 서빙(Triton/torchserve/vLLM)으로 교체 시 동일한 ILB 서비스로 노출한다.
# ---------------------------------------------------------------------------
resource "kubernetes_config_map" "sample" {
  metadata {
    name   = "model-endpoint-content"
    labels = { app = "model-endpoint" }
  }

  data = {
    "index.json" = jsonencode({
      service = "model-endpoint"
      status  = "ok"
      message = "mock inference response from AKS internal LB"
    })
    "healthz"      = "healthy"
    "default.conf" = <<-EOT
      server {
        listen 80;
        default_type application/json;
        location = /        { root /usr/share/nginx/html; try_files /index.json =404; }
        location = /healthz { default_type text/plain; root /usr/share/nginx/html; try_files /healthz =404; }
      }
    EOT
  }
}

resource "kubernetes_deployment" "sample" {
  metadata {
    name   = "model-endpoint"
    labels = { app = "model-endpoint" }
  }

  spec {
    replicas = var.sample_app_replicas
    selector {
      match_labels = { app = "model-endpoint" }
    }
    template {
      metadata {
        labels = { app = "model-endpoint" }
      }
      spec {
        container {
          name  = "model-endpoint"
          image = var.sample_app_image
          port {
            container_port = 80
          }

          volume_mount {
            name       = "content"
            mount_path = "/usr/share/nginx/html"
          }
          volume_mount {
            name       = "nginx-conf"
            mount_path = "/etc/nginx/conf.d"
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
          liveness_probe {
            http_get {
              path = "/healthz"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 20
          }
        }

        volume {
          name = "content"
          config_map {
            name = kubernetes_config_map.sample.metadata[0].name
            items {
              key  = "index.json"
              path = "index.json"
            }
            items {
              key  = "healthz"
              path = "healthz"
            }
          }
        }
        volume {
          name = "nginx-conf"
          config_map {
            name = kubernetes_config_map.sample.metadata[0].name
            items {
              key  = "default.conf"
              path = "default.conf"
            }
          }
        }
      }
    }
  }

  depends_on = [azurerm_kubernetes_cluster.this]
}

resource "kubernetes_service" "ilb" {
  metadata {
    name = "model-endpoint-ilb"
    annotations = {
      "service.beta.kubernetes.io/azure-load-balancer-internal" = "true"
    }
  }

  spec {
    selector         = { app = "model-endpoint" }
    load_balancer_ip = var.ilb_ip
    type             = "LoadBalancer"
    port {
      port        = 80
      target_port = 80
    }
  }

  depends_on = [azurerm_role_assignment.aks_network]
}

# ---------------------------------------------------------------------------
# APIM Standard v2 — SPL의 중개 게이트웨이
#   인바운드: Private Endpoint(groupId=Gateway) ← AI Search SPL 대상
#   아웃바운드: VNet 통합(snet-apim) → AKS ILB 사설 IP 호출
# ---------------------------------------------------------------------------
resource "azurerm_api_management" "this" {
  name                = local.apim_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email
  sku_name            = var.apim_sku_name

  public_network_access_enabled = var.apim_public_network_access_enabled

  virtual_network_type = "External"
  virtual_network_configuration {
    subnet_id = azurerm_subnet.apim.id
  }

  tags = var.tags
}

# APIM이 AKS ILB로 프록시할 샘플 API (service_url = ILB 사설 IP).
resource "azurerm_api_management_api" "model" {
  name                  = "model-api"
  resource_group_name   = azurerm_resource_group.this.name
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Model Endpoint API"
  path                  = "model"
  protocols             = ["https"]
  service_url           = local.ilb_base_url
  subscription_required = false
}

resource "azurerm_api_management_api_operation" "get" {
  operation_id        = "invoke"
  api_name            = azurerm_api_management_api.model.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  display_name        = "Invoke model"
  method              = "GET"
  url_template        = "/"
  description         = "AKS ILB 뒤의 모델 엔드포인트 호출"
}

# ---------------------------------------------------------------------------
# APIM 인바운드 Private Endpoint (groupId=Gateway) — AI Search SPL 연결 대상
# ---------------------------------------------------------------------------
data "azurerm_private_dns_zone" "apim_central" {
  count               = var.use_central_dns_zone_group ? 1 : 0
  provider            = azurerm.central
  name                = var.central_apim_private_dns_zone_name
  resource_group_name = var.central_dns_resource_group_name
}

resource "azurerm_private_endpoint" "apim" {
  name                = "${var.name_prefix}-apim-pe"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = var.tags

  private_service_connection {
    name                           = "apim-gateway"
    private_connection_resource_id = azurerm_api_management.this.id
    subresource_names              = ["Gateway"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = var.use_central_dns_zone_group ? [1] : []
    content {
      name                 = "apim-zone-group"
      private_dns_zone_ids = [data.azurerm_private_dns_zone.apim_central[0].id]
    }
  }
}

# ---------------------------------------------------------------------------
# Azure AI Search + Shared Private Link → APIM (groupId=Gateway)
#   SPL은 AI Search의 MS 관리 네트워크에서 APIM Private Endpoint로 managed PE를 만든다.
#   연결은 APIM 측에서 수동 승인이 필요하다(README 참고).
# ---------------------------------------------------------------------------
resource "azurerm_search_service" "this" {
  name                          = local.search_name
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  sku                           = var.search_sku
  public_network_access_enabled = false
  tags                          = var.tags
}

resource "azurerm_search_shared_private_link_service" "apim" {
  name               = "spl-to-apim"
  search_service_id  = azurerm_search_service.this.id
  subresource_name   = "Gateway"
  target_resource_id = azurerm_api_management.this.id
  request_message    = "AI Search -> APIM(Gateway) shared private link for private AKS ILB access"
}
