variable "subscription_id" {
  description = "배포 대상 Azure 구독 ID"
  type        = string
}

variable "location" {
  description = "리소스를 배포할 리전"
  type        = string
  default     = "koreacentral"
}

variable "name_prefix" {
  description = "리소스 이름 접두사 (kebab/소문자)"
  type        = string
  default     = "aks-node-3p"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes 버전 (null이면 리전 기본값)"
  type        = string
  default     = null
}

variable "system_node_count" {
  description = "시스템 노드풀 노드 수"
  type        = number
  default     = 1
}

variable "system_node_vm_size" {
  description = "시스템 노드풀 VM 크기"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "user_node_count" {
  description = "사용자(워크로드) 노드풀 노드 수 — 3rd party 솔루션 검증 대상"
  type        = number
  default     = 2
}

variable "user_node_vm_size" {
  description = "사용자 노드풀 VM 크기"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "user_node_os_sku" {
  description = "사용자 노드풀 OS SKU (예: Ubuntu, AzureLinux). 패키지 포맷과 일치해야 함"
  type        = string
  default     = "Ubuntu"
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default = {
    scenario = "aks-node-3rd-party-solution-deployment"
  }
}
