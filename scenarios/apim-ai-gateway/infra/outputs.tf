output "resource_group_name" {
  value       = azurerm_resource_group.this.name
  description = "생성된 Resource Group 이름"
}

output "apim_name" {
  value       = azurerm_api_management.this.name
  description = "API Management 인스턴스 이름"
}

output "apim_gateway_url" {
  value       = azurerm_api_management.this.gateway_url
  description = "APIM 게이트웨이 base URL (OpenAI 프록시 = <gateway_url>/openai)"
}

output "openai_proxy_base_url" {
  value       = "${azurerm_api_management.this.gateway_url}/openai"
  description = "테스트에서 사용할 OpenAI 프록시 base URL (AZURE_OPENAI_ENDPOINT 대체)"
}

output "apim_identity_principal_id" {
  value       = azurerm_api_management.this.identity[0].principal_id
  description = "APIM system-assigned MI principal ID (keyless 롤 부여 대상)"
}

output "primary_openai_name" {
  value       = azurerm_cognitive_account.primary.name
  description = "primary Azure OpenAI 계정 이름"
}

output "secondary_openai_name" {
  value       = var.enable_load_balancing ? azurerm_cognitive_account.secondary[0].name : null
  description = "secondary Azure OpenAI 계정 이름 (load balancing 활성화 시)"
}

output "chat_deployment_name" {
  value       = var.chat_model_name
  description = "채팅 배포 이름 (테스트 요청 경로 /deployments/<이름>/chat/completions)"
}

output "openai_api_version" {
  value       = var.openai_api_version
  description = "테스트에 사용할 Azure OpenAI data-plane API 버전"
}

output "load_balancing_enabled" {
  value       = var.enable_load_balancing
  description = "load-balanced Pool + circuit breaker 활성화 여부"
}

output "semantic_cache_enabled" {
  value       = var.enable_semantic_cache
  description = "semantic cache(Redis) 활성화 여부"
}

output "observability_enabled" {
  value       = var.enable_observability
  description = "App Insights 토큰 메트릭/로깅 활성화 여부"
}
