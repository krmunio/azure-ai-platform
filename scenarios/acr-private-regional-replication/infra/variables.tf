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

variable "tags" {
  type = map(string)
  default = {
    scenario   = "acr-private-regional-replication"
    managed_by = "terraform"
  }
  description = "공통 태그"
}
