variable "subscription_id" {
  type        = string
  default     = null
  description = "워크로드(application)를 배포할 구독 ID. null이면 기본 CLI 컨텍스트 사용."
}

variable "location" {
  type        = string
  default     = "koreacentral"
  description = "기본 리전"
}

variable "name_prefix" {
  type        = string
  default     = "aisaks"
  description = "리소스 이름 접두사 (소문자/숫자만)"
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "Resource Group 이름. 미지정 시 name_prefix 기반 파생"
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.60.0.0/16"]
  description = "VNet 주소 공간"
}

variable "aks_subnet_prefix" {
  type        = list(string)
  default     = ["10.60.0.0/22"]
  description = "AKS 노드 + 내부 LoadBalancer(ILB) 서브넷"
}

variable "apim_subnet_prefix" {
  type        = list(string)
  default     = ["10.60.4.0/24"]
  description = "APIM Standard v2 아웃바운드 VNet 통합용 서브넷 (Microsoft.Web/serverFarms 위임)"
}

variable "pe_subnet_prefix" {
  type        = list(string)
  default     = ["10.60.5.0/24"]
  description = "APIM 인바운드 Private Endpoint 서브넷"
}

variable "ilb_ip" {
  type        = string
  default     = "10.60.0.100"
  description = "AKS 내부 LoadBalancer(ILB)에 고정 할당할 사설 IP (aks_subnet_prefix 범위 내). APIM 백엔드가 이 IP를 호출한다."
}

variable "aks_node_vm_size" {
  type        = string
  default     = "Standard_D2s_v3"
  description = "샘플 워크로드용 경량 시스템 노드 VM 크기 (GPU 아님). 실제 GPU 노드풀은 별도 추가."
}

variable "aks_node_count" {
  type        = number
  default     = 1
  description = "기본 노드풀 노드 수"
}

variable "apim_sku_name" {
  type        = string
  default     = "StandardV2_1"
  description = <<-EOT
    APIM SKU. 인바운드 Private Endpoint + 아웃바운드 VNet 통합을 한 인스턴스에서 동시 지원하려면
    v2 계열(StandardV2/PremiumV2)이 필요하다. 클래식 Internal 주입 모드는 인바운드 PE를 지원하지 않는다.
  EOT
}

variable "apim_publisher_name" {
  type        = string
  default     = "Contoso"
  description = "APIM publisher 이름 (placeholder)"
}

variable "apim_publisher_email" {
  type        = string
  default     = "admin@example.com"
  description = "APIM publisher 이메일 (placeholder)"
}

variable "apim_public_network_access_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    APIM 관리 평면 공중망 접근. 생성 시점에는 true가 요구된다.
    인바운드 Private Endpoint 승인 후 false로 전환해 완전 사설화한다(별도 apply 또는 포털).
  EOT
}

variable "search_sku" {
  type        = string
  default     = "basic"
  description = "Azure AI Search SKU. Shared Private Link은 basic 이상에서 지원."
}

variable "use_central_dns_zone_group" {
  type        = bool
  default     = false
  description = <<-EOT
    중앙 구독의 privatelink.azure-api.net Zone을 data로 조회해 APIM Private Endpoint에 zone group을 생성할지 여부.
    - false(기본): zone group 미생성. A 레코드는 중앙 Azure Policy(DeployIfNotExists)가 등록한다고 가정.
    - true: 아래 central_dns_* 값으로 중앙 zone을 조회해 zone group 생성(cross-subscription 쓰기 권한 필요).
  EOT
}

variable "central_dns_subscription_id" {
  type        = string
  default     = null
  description = "중앙 Private DNS Zone이 위치한 구독 ID (alias provider용). null이면 기본 컨텍스트."
}

variable "central_dns_resource_group_name" {
  type        = string
  default     = "central-dns-rg"
  description = "중앙 Private DNS Zone이 속한 Resource Group 이름 (data 조회용)"
}

variable "central_apim_private_dns_zone_name" {
  type        = string
  default     = "privatelink.azure-api.net"
  description = "중앙에서 관리되는 APIM Private Link DNS Zone 이름 (data 조회용)"
}

variable "tags" {
  type = map(string)
  default = {
    scenario   = "aisearch-aks-ilb-private-apim"
    managed_by = "terraform"
  }
  description = "공통 태그"
}
