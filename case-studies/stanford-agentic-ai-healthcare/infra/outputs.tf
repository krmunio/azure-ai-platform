output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "fhir_service_url" {
  description = "합성 FHIR 로드 / 기능 테스트 대상 엔드포인트"
  value       = "https://${local.prefix}hdw-${local.prefix}fhir.fhir.azurehealthcareapis.com"
}

output "ai_services_endpoint" {
  value = azurerm_cognitive_account.aiservices.endpoint
}

output "search_endpoint" {
  value = "https://${azurerm_search_service.this.name}.search.windows.net"
}

output "key_vault_uri" {
  value = azurerm_key_vault.this.vault_uri
}
