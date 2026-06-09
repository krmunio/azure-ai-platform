variable "subscription_id" {
  type        = string
  default     = null
  description = "중앙 DNS를 배포할 구독 ID. null이면 환경변수/기본 CLI 컨텍스트를 사용."
}

variable "location" {
  type        = string
  default     = "koreacentral"
  description = "중앙 DNS 리소스 그룹 리전 (Private DNS Zone은 global 리소스)"
}

variable "resource_group_name" {
  type        = string
  default     = "central-dns-rg"
  description = "Private DNS Zone을 담는 중앙 Resource Group 이름"
}

variable "private_dns_zone_name" {
  type        = string
  default     = "privatelink.azurecr.io"
  description = "중앙 관리되는 ACR Private Link DNS Zone 이름"
}

variable "linked_vnet_ids" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    이 중앙 DNS Zone에 연결(VNet Link)할 VNet 목록. key=링크 이름, value=VNet 리소스 ID.
    spoke(application)의 VNet에서 사설 이름 해석이 되도록 중앙에서 링크를 관리한다.
    예: { "acr-spoke" = "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>" }
  EOT
}

variable "tags" {
  type = map(string)
  default = {
    scenario   = "acr-private-regional-replication"
    layer      = "platform"
    managed_by = "terraform"
  }
  description = "공통 태그"
}
