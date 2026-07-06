variable "subscription_id" {
  type        = string
  default     = null
  description = "배포할 구독 ID. null이면 환경변수/기본 CLI 컨텍스트 사용."
}

variable "location" {
  type        = string
  default     = "koreacentral"
  description = "리전. 의료 데이터 레지던시 요건에 맞춰 고정."
}

variable "name_prefix" {
  type        = string
  default     = "tbagent"
  description = "리소스 이름 접두사 (소문자/숫자). 실제 리소스명 하드코딩 금지 — 이 변수로 파생."
}

variable "vnet_address_space" {
  type        = list(string)
  default     = ["10.60.0.0/16"]
  description = "Hub-Spoke VNet 주소 공간"
}

variable "subnet_prefixes" {
  type = object({
    app  = string
    ai   = string
    data = string
    pe   = string
  })
  default = {
    app  = "10.60.1.0/24"
    ai   = "10.60.2.0/24"
    data = "10.60.3.0/24"
    pe   = "10.60.9.0/24"
  }
  description = "스포크별 + Private Endpoint 서브넷 범위"
}

variable "model_deployments" {
  type = list(object({
    name     = string
    model    = string
    version  = string
    capacity = number
  }))
  default = [
    { name = "reasoning", model = "gpt-4o", version = "2024-11-20", capacity = 20 }
  ]
  description = "Foundry/OpenAI 모델 배포 목록. gpt 계열 호출은 max_completion_tokens 사용."
}

variable "tags" {
  type = map(string)
  default = {
    case_study = "stanford-agentic-ai-healthcare"
    managed_by = "terraform"
    env        = "poc"
  }
  description = "공통 태그"
}
