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

variable "use_central_dns_zone_group" {
  type        = bool
  default     = false
  description = <<-EOT
    중앙 구독의 Private DNS Zone을 data 블록으로 조회해 Private Endpoint에 zone group을 생성할지 여부.
    - false(기본): zone group 미생성. A 레코드는 중앙 Azure Policy(DeployIfNotExists)가 등록한다고 가정.
    - true: 아래 central_dns_* 값으로 중앙 zone을 조회해 zone group 생성(cross-subscription 쓰기 권한 필요).
  EOT
}

variable "central_dns_subscription_id" {
  type        = string
  default     = null
  description = "중앙 Private DNS Zone이 위치한 구독 ID (alias provider용). null이면 기본 컨텍스트 사용."
}

variable "central_dns_resource_group_name" {
  type        = string
  default     = "central-dns-rg"
  description = "중앙 Private DNS Zone이 속한 Resource Group 이름 (data 조회용)"
}

variable "central_private_dns_zone_name" {
  type        = string
  default     = "privatelink.azurecr.io"
  description = "중앙에서 관리되는 ACR Private Link DNS Zone 이름 (data 조회용)"
}

variable "tags" {
  type = map(string)
  default = {
    scenario   = "acr-private-regional-replication"
    managed_by = "terraform"
  }
  description = "공통 태그"
}
