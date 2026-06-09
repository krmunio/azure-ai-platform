terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# 중앙(connectivity) 구독을 대상으로 한다.
# 별도 구독에 배포하려면 subscription_id를 지정하거나 ARM_SUBSCRIPTION_ID 환경변수를 사용한다.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
