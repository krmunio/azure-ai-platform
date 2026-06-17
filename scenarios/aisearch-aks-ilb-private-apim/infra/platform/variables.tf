variable "subscription_id" {
  type        = string
  default     = null
  description = "중앙(connectivity) Private DNS Zone을 배포할 구독 ID. null이면 기본 CLI 컨텍스트 사용."
}

variable "location" {
  type        = string
  default     = "koreacentral"
  description = "중앙 DNS RG 리전"
}

variable "resource_group_name" {
  type        = string
  default     = "central-dns-rg"
  description = "중앙 Private DNS Zone이 속한 Resource Group 이름"
}

variable "apim_private_dns_zone_name" {
  type        = string
  default     = "privatelink.azure-api.net"
  description = "APIM 인바운드 Private Endpoint용 Private Link DNS Zone 이름"
}

variable "linked_vnet_ids" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    이 zone에 연결(VNet Link)할 spoke VNet ID 맵.
    key는 link 이름(임의), value는 VNet의 전체 리소스 ID.
    application 레이어의 vnet_id 출력을 넣고 다시 apply 한다.
  EOT
}

variable "tags" {
  type = map(string)
  default = {
    scenario   = "aisearch-aks-ilb-private-apim"
    managed_by = "terraform"
  }
  description = "공통 태그"
}
