locals {
  rg_name       = coalesce(var.resource_group_name, "${var.name_prefix}-rg")
  primary_oai   = "${var.name_prefix}-oai-pri-${random_string.suffix.result}"
  secondary_oai = "${var.name_prefix}-oai-sec-${random_string.suffix.result}"
  apim_name     = "${var.name_prefix}-apim-${random_string.suffix.result}"

  # policy의 set-backend-service가 참조할 backend 이름.
  # load balancing 시 Pool, 아니면 primary 단일 backend.
  effective_backend_id = var.enable_load_balancing ? azapi_resource.backend_pool[0].name : azapi_resource.backend_primary.name

  # API policy(XML) 조립 — templatefile로 토글별 조각을 주입
  api_policy_xml = templatefile("${path.module}/policies/ai-gateway.xml.tftpl", {
    backend_id             = local.effective_backend_id
    tokens_per_minute      = var.tokens_per_minute
    enable_observability   = var.enable_observability
    enable_semantic_cache  = var.enable_semantic_cache
    semantic_score         = var.semantic_cache_score_threshold
    embeddings_backend_id  = var.enable_semantic_cache ? azapi_resource.backend_embeddings[0].name : ""
    cognitive_services_aud = "https://cognitiveservices.azure.com"
  })
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

########################################
# Azure OpenAI (Foundry) — primary/secondary
########################################
resource "azurerm_cognitive_account" "primary" {
  name                  = local.primary_oai
  location              = var.location
  resource_group_name   = azurerm_resource_group.this.name
  kind                  = "OpenAI"
  sku_name              = var.openai_sku_name
  custom_subdomain_name = local.primary_oai
  tags                  = var.tags
}

resource "azurerm_cognitive_deployment" "chat_primary" {
  name                 = var.chat_model_name
  cognitive_account_id = azurerm_cognitive_account.primary.id

  model {
    format  = "OpenAI"
    name    = var.chat_model_name
    version = var.chat_model_version
  }

  sku {
    name     = var.chat_deployment_sku
    capacity = var.chat_capacity
  }
}

resource "azurerm_cognitive_account" "secondary" {
  count                 = var.enable_load_balancing ? 1 : 0
  name                  = local.secondary_oai
  location              = var.secondary_location
  resource_group_name   = azurerm_resource_group.this.name
  kind                  = "OpenAI"
  sku_name              = var.openai_sku_name
  custom_subdomain_name = local.secondary_oai
  tags                  = var.tags
}

resource "azurerm_cognitive_deployment" "chat_secondary" {
  count                = var.enable_load_balancing ? 1 : 0
  name                 = var.chat_model_name
  cognitive_account_id = azurerm_cognitive_account.secondary[0].id

  model {
    format  = "OpenAI"
    name    = var.chat_model_name
    version = var.chat_model_version
  }

  sku {
    name     = var.chat_deployment_sku
    capacity = var.chat_capacity
  }
}

# semantic cache용 임베딩 배포 (primary 계정)
resource "azurerm_cognitive_deployment" "embeddings" {
  count                = var.enable_semantic_cache ? 1 : 0
  name                 = var.embeddings_model_name
  cognitive_account_id = azurerm_cognitive_account.primary.id

  model {
    format  = "OpenAI"
    name    = var.embeddings_model_name
    version = var.embeddings_model_version
  }

  sku {
    name     = var.embeddings_deployment_sku
    capacity = var.chat_capacity
  }
}

########################################
# API Management (system-assigned MI)
########################################
resource "azurerm_api_management" "this" {
  name                = local.apim_name
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  publisher_name      = var.publisher_name
  publisher_email     = var.publisher_email
  sku_name            = var.apim_sku_name
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

# Keyless: APIM MI에 Cognitive Services OpenAI User 롤 부여 (PDF: Keyless managed identities)
resource "azurerm_role_assignment" "apim_openai_primary" {
  scope                = azurerm_cognitive_account.primary.id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "apim_openai_secondary" {
  count                = var.enable_load_balancing ? 1 : 0
  scope                = azurerm_cognitive_account.secondary[0].id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}

########################################
# Observability — App Insights + logger (emit-token-metric)
########################################
resource "azurerm_application_insights" "this" {
  count               = var.enable_observability ? 1 : 0
  name                = "${var.name_prefix}-appi-${random_string.suffix.result}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  application_type    = "web"
  tags                = var.tags
}

resource "azurerm_api_management_logger" "appi" {
  count               = var.enable_observability ? 1 : 0
  name                = "appinsights"
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name

  application_insights {
    instrumentation_key = azurerm_application_insights.this[0].instrumentation_key
  }
}

resource "azurerm_api_management_diagnostic" "appi" {
  count                    = var.enable_observability ? 1 : 0
  identifier               = "applicationinsights"
  resource_group_name      = azurerm_resource_group.this.name
  api_management_name      = azurerm_api_management.this.name
  api_management_logger_id = azurerm_api_management_logger.appi[0].id
  sampling_percentage      = 100
  always_log_errors        = true
  log_client_ip            = true
  verbosity                = "information"
}

########################################
# Semantic cache 외부 캐시 — Azure Managed Redis (RediSearch) + APIM 연결
# (구형 Redis Enterprise는 신규 생성 중단 → Managed Redis SKU 사용, azapi로 관리)
########################################
resource "azapi_resource" "redis" {
  count     = var.enable_semantic_cache ? 1 : 0
  type      = "Microsoft.Cache/redisEnterprise@2024-10-01"
  name      = "${var.name_prefix}-redis-${random_string.suffix.result}"
  parent_id = azurerm_resource_group.this.id
  location  = var.location
  tags      = var.tags

  body = {
    sku = { name = var.redis_sku }
  }

  response_export_values = ["properties.hostName"]
}

resource "azapi_resource" "redis_db" {
  count     = var.enable_semantic_cache ? 1 : 0
  type      = "Microsoft.Cache/redisEnterprise/databases@2024-10-01"
  name      = "default"
  parent_id = azapi_resource.redis[0].id

  body = {
    properties = {
      clientProtocol   = "Encrypted"
      clusteringPolicy = "EnterpriseCluster"
      evictionPolicy   = "NoEviction"
      modules          = [{ name = "RediSearch" }]
    }
  }
}

# Managed Redis 데이터베이스 접근 키 조회 (연결 문자열 구성용)
resource "azapi_resource_action" "redis_keys" {
  count       = var.enable_semantic_cache ? 1 : 0
  type        = "Microsoft.Cache/redisEnterprise/databases@2024-10-01"
  resource_id = azapi_resource.redis_db[0].id
  action      = "listKeys"
  method      = "POST"

  response_export_values = ["primaryKey"]
}

resource "azurerm_api_management_redis_cache" "this" {
  count             = var.enable_semantic_cache ? 1 : 0
  name              = "semantic-cache"
  api_management_id = azurerm_api_management.this.id
  connection_string = format(
    "%s:10000,password=%s,ssl=True,abortConnect=False",
    azapi_resource.redis[0].output.properties.hostName,
    azapi_resource_action.redis_keys[0].output.primaryKey
  )
  redis_cache_id = azapi_resource.redis_db[0].id
}

########################################
# Backends (azapi) — circuit breaker + load-balanced Pool
########################################
resource "azapi_resource" "backend_primary" {
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "openai-primary"
  parent_id = azurerm_api_management.this.id

  body = {
    properties = {
      url      = "${azurerm_cognitive_account.primary.endpoint}openai"
      protocol = "http"
      circuitBreaker = {
        rules = [{
          name = "openai-breaker"
          failureCondition = {
            count            = 3
            interval         = "PT30S"
            statusCodeRanges = [{ min = 429, max = 429 }, { min = 500, max = 599 }]
          }
          tripDuration     = "PT1M"
          acceptRetryAfter = true
        }]
      }
    }
  }
}

resource "azapi_resource" "backend_secondary" {
  count     = var.enable_load_balancing ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "openai-secondary"
  parent_id = azurerm_api_management.this.id

  body = {
    properties = {
      url      = "${azurerm_cognitive_account.secondary[0].endpoint}openai"
      protocol = "http"
      circuitBreaker = {
        rules = [{
          name = "openai-breaker"
          failureCondition = {
            count            = 3
            interval         = "PT30S"
            statusCodeRanges = [{ min = 429, max = 429 }, { min = 500, max = 599 }]
          }
          tripDuration     = "PT1M"
          acceptRetryAfter = true
        }]
      }
    }
  }
}

# 임베딩 전용 backend (semantic cache lookup/store가 참조)
resource "azapi_resource" "backend_embeddings" {
  count     = var.enable_semantic_cache ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "openai-embeddings"
  parent_id = azurerm_api_management.this.id

  body = {
    properties = {
      url      = "${azurerm_cognitive_account.primary.endpoint}openai"
      protocol = "http"
    }
  }
}

# Load-balanced Pool — 가중치/우선순위로 여러 backend 분산 (PDF 예시2)
resource "azapi_resource" "backend_pool" {
  count     = var.enable_load_balancing ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "openai-pool"
  parent_id = azurerm_api_management.this.id

  body = {
    properties = {
      type = "Pool"
      pool = {
        services = [
          {
            id       = azapi_resource.backend_primary.id
            weight   = var.primary_backend_weight
            priority = var.primary_backend_priority
          },
          {
            id       = azapi_resource.backend_secondary[0].id
            weight   = var.secondary_backend_weight
            priority = var.secondary_backend_priority
          }
        ]
      }
    }
  }
}

########################################
# API + 단일 catch-all 오퍼레이션 + policy
########################################
resource "azurerm_api_management_api" "openai" {
  name                  = "openai"
  resource_group_name   = azurerm_resource_group.this.name
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Azure OpenAI (AI Gateway)"
  path                  = "openai"
  protocols             = ["https"]
  subscription_required = true
}

resource "azurerm_api_management_api_operation" "post" {
  operation_id        = "openai-post"
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  display_name        = "OpenAI POST proxy"
  method              = "POST"
  url_template        = "/{*path}"
  description         = "chat/completions·embeddings 등 모든 OpenAI data-plane 경로를 프록시"

  template_parameter {
    name     = "path"
    required = true
    type     = "string"
  }

  response {
    status_code = 200
  }
}

resource "azurerm_api_management_api_policy" "openai" {
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = azurerm_resource_group.this.name
  xml_content         = local.api_policy_xml

  depends_on = [
    azapi_resource.backend_primary,
    azapi_resource.backend_pool,
    azapi_resource.backend_embeddings,
    azurerm_api_management_redis_cache.this,
  ]
}
