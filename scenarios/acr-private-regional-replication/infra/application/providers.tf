terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# 중앙(connectivity) 구독의 Private DNS Zone을 data 블록으로 조회하기 위한 alias provider.
# application과 다른 구독에 zone이 있을 때 cross-subscription 읽기에 사용한다.
provider "azurerm" {
  alias = "central"
  features {}
  subscription_id = var.central_dns_subscription_id
}
