variable "location" {
  type        = string
  default     = "koreacentral"
  description = "기본(primary) 리전"
}

variable "name_prefix" {
  type        = string
  default     = "acrpriv"
  description = "리소스 이름 접두사 (소문자/숫자만; ACR 이름 규칙)"
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "Resource Group 이름. 미지정 시 name_prefix 기반으로 파생"
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.50.0.0/16"]
  description = "VNet 주소 공간"
}

variable "pe_subnet_prefix" {
  type        = list(string)
  default     = ["10.50.1.0/24"]
  description = "Private Endpoint 서브넷 주소 범위"
}

variable "acr_sku" {
  type        = string
  default     = "Premium"
  description = "ACR SKU. geo-replication 및 Private Endpoint는 Premium 필수"
}

variable "central_private_dns_zone_id" {
  type        = string
  default     = null
  description = <<-EOT
    중앙(별도 구독)에서 관리되는 privatelink.azurecr.io Private DNS Zone의 리소스 ID.
    - null(기본): zone group을 만들지 않음. A 레코드는 중앙 Azure Policy(DeployIfNotExists)로 등록된다고 가정.
    - 값 지정 시: 해당 중앙 zone을 참조해 Private Endpoint에 zone group을 생성(cross-subscription 쓰기 권한 필요).
    예: /subscriptions/<central-sub-id>/resourceGroups/<rg>/providers/Microsoft.Network/privateDnsZones/privatelink.azurecr.io
  EOT
}

variable "tags" {
  type = map(string)
  default = {
    scenario   = "acr-private-regional-replication"
    managed_by = "terraform"
  }
  description = "공통 태그"
}
