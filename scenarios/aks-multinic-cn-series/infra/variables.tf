variable "subscription_id" {
  description = "배포 대상 Azure 구독 ID (미지정 시 ARM_SUBSCRIPTION_ID 사용)"
  type        = string
  default     = null
}

variable "location" {
  description = "Azure 리전"
  type        = string
  default     = "australiaeast"
}

variable "prefix" {
  description = "리소스 이름 접두사"
  type        = string
  default     = "aksmnic"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes 버전 (null이면 기본값)"
  type        = string
  default     = null
}

# --- 네트워크: 고객 운영 모델 재현 ---
variable "vnet_cidr" {
  description = "VNet 주소 공간"
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_subnet_cidr" {
  description = "노드 서브넷(routable) 10.x.x.x/22"
  type        = string
  default     = "10.0.0.0/22"
}

variable "secondary_nic_subnet_cidr" {
  description = "2nd NIC routable 서브넷 (Approach A: macvlan/ipvlan용 호스트 보조 NIC 위치)"
  type        = string
  default     = "10.0.8.0/24"
}

variable "cn_pod_subnet_cidr" {
  description = "Approach B(Azure CNI delegate)용 전용 pod 서브넷(routable)"
  type        = string
  default     = "10.0.9.0/24"
}

variable "pod_cidr_overlay" {
  description = "Azure CNI Overlay 파드 CIDR(non-routable, CGNAT)"
  type        = string
  default     = "100.64.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes 서비스 CIDR"
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "kube-dns 서비스 IP (service_cidr 내)"
  type        = string
  default     = "172.16.0.10"
}

variable "node_count" {
  description = "노드 수"
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "노드 VM 크기 (2nd NIC 지원 필요)"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "enable_managed_multus" {
  description = "관리형 Multus 애드온 활성화 여부 (false면 수동 DaemonSet 경로 사용)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "공통 태그"
  type        = map(string)
  default = {
    scenario = "aks-multinic-cn-series"
    purpose  = "poc"
  }
}
