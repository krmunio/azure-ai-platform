variable "subscription_id" {
  type        = string
  default     = null
  description = "배포할 구독 ID. null이면 환경변수/기본 CLI 컨텍스트를 사용."
}

variable "location" {
  type        = string
  default     = "koreacentral"
  description = "기본(primary) 리전 — APIM/App Insights 및 primary Azure OpenAI 배포 위치"
}

variable "secondary_location" {
  type        = string
  default     = "japaneast"
  description = "secondary Azure OpenAI 리전 (load balancing 활성화 시 사용)"
}

variable "name_prefix" {
  type        = string
  default     = "aigw"
  description = "리소스 이름 접두사 (소문자/숫자, 3-10자 권장)"
}

variable "resource_group_name" {
  type        = string
  default     = null
  description = "Resource Group 이름. 미지정 시 name_prefix 기반으로 파생"
}

variable "publisher_name" {
  type        = string
  default     = "AI Platform Team"
  description = "APIM publisher 표시 이름 (실제 개인정보 대신 팀/조직 일반명 사용)"
}

variable "publisher_email" {
  type        = string
  default     = "apim-admin@example.com"
  description = "APIM publisher 이메일 (실제 주소 대신 example.com placeholder 권장)"
}

variable "apim_sku_name" {
  type        = string
  default     = "StandardV2_1"
  description = <<-EOT
    APIM SKU (`<tier>_<capacity>`). AI Gateway policy(token-limit/semantic-cache 등)는
    Consumption을 제외한 모든 tier에서 지원. 예: StandardV2_1, BasicV2_1, Premium_1.
  EOT
}

variable "openai_sku_name" {
  type        = string
  default     = "S0"
  description = "Azure OpenAI(Cognitive Services) SKU"
}

variable "chat_model_name" {
  type        = string
  default     = "gpt-4o-mini"
  description = "채팅 completion 모델 이름"
}

variable "chat_model_version" {
  type        = string
  default     = "2024-07-18"
  description = "채팅 모델 버전"
}

variable "chat_capacity" {
  type        = number
  default     = 10
  description = "채팅 배포 용량(1000 TPM 단위). load balancing 검증을 위해 의도적으로 작게 둘 수 있음"
}

variable "chat_deployment_sku" {
  type        = string
  default     = "GlobalStandard"
  description = <<-EOT
    채팅 모델 배포 SKU. GlobalStandard가 리전 지원이 가장 넓다.
    특정 리전에서 지역(regional) 쿼터만 있으면 "Standard"로, PTU 검증이면 "ProvisionedManaged"로 변경.
  EOT
}

variable "embeddings_deployment_sku" {
  type        = string
  default     = "GlobalStandard"
  description = "임베딩 모델 배포 SKU (semantic cache 활성화 시). 리전 미지원이면 Standard로 변경"
}

variable "embeddings_model_name" {
  type        = string
  default     = "text-embedding-3-small"
  description = "semantic cache용 임베딩 모델 이름 (enable_semantic_cache=true 시 사용)"
}

variable "embeddings_model_version" {
  type        = string
  default     = "1"
  description = "임베딩 모델 버전"
}

variable "enable_load_balancing" {
  type        = bool
  default     = true
  description = <<-EOT
    true면 secondary 리전에 두 번째 Azure OpenAI를 배포하고, 두 backend를
    load-balanced Pool(가중치/우선순위 + circuit breaker)로 묶는다.
    false면 primary 단일 backend만 사용한다.
  EOT
}

variable "primary_backend_weight" {
  type        = number
  default     = 50
  description = "load balancing 시 primary backend 가중치"
}

variable "secondary_backend_weight" {
  type        = number
  default     = 50
  description = "load balancing 시 secondary backend 가중치"
}

variable "primary_backend_priority" {
  type        = number
  default     = 1
  description = "primary backend 우선순위(작을수록 우선). PTU-우선 라우팅 모사에 사용"
}

variable "secondary_backend_priority" {
  type        = number
  default     = 1
  description = "secondary backend 우선순위"
}

variable "tokens_per_minute" {
  type        = number
  default     = 500
  description = <<-EOT
    azure-openai-token-limit policy의 분당 토큰(TPM) 한도.
    스로틀링(429) 이점을 쉽게 재현하도록 기본값을 의도적으로 낮게 둔다.
  EOT
}

variable "enable_semantic_cache" {
  type        = bool
  default     = false
  description = <<-EOT
    true면 Azure Managed Redis + APIM cache 연결 + 임베딩 배포를 프로비저닝하고
    semantic-cache lookup/store policy를 활성화한다.
    (Redis 프로비저닝으로 배포 시간/비용이 증가하므로 기본 false.)
  EOT
}

variable "semantic_cache_score_threshold" {
  type        = number
  default     = 0.05
  description = "semantic cache 유사도 점수 임계값 (작을수록 엄격)"
}

variable "redis_sku" {
  type        = string
  default     = "Balanced_B0"
  description = <<-EOT
    semantic cache용 Azure Managed Redis SKU (Microsoft.Cache/redisEnterprise).
    RediSearch 모듈이 포함된 최소 SKU. 예: Balanced_B0, MemoryOptimized_M10.
    (구형 Enterprise_E* SKU는 신규 생성이 중단되어 사용하지 않는다.)
  EOT
}

variable "enable_observability" {
  type        = bool
  default     = true
  description = <<-EOT
    true면 Application Insights + APIM logger를 배포하고 emit-token-metric policy를
    활성화한다(소비자별 토큰 카운팅/관측성).
  EOT
}

variable "openai_api_version" {
  type        = string
  default     = "2024-10-21"
  description = "backend로 전달되는 Azure OpenAI data-plane API 버전 (문서/테스트용 기본값)"
}

variable "tags" {
  type = map(string)
  default = {
    scenario   = "apim-ai-gateway"
    managed_by = "terraform"
  }
  description = "공통 태그"
}
