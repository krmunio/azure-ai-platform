# 구현 계획 — aisearch-aks-ilb-private-apim

## 목표

Azure AI Search가 사설 AKS ILB와 통신하는 BP를, **APIM Standard v2 중개**(인바운드 Private
Endpoint + 아웃바운드 VNet 통합)로 end-to-end Terraform으로 배포·검증 가능하게 한다.

## 단계

1. **platform 레이어** — 중앙 Private DNS Zone(`privatelink.azure-api.net`) + VNet Link.
2. **application 레이어**
   - VNet + 서브넷 3종(aks / apim[위임] / pe)
   - 경량 AKS + Network Contributor 역할
   - kubernetes provider로 내부 LB 샘플 서비스(고정 `ilb_ip`)
   - APIM Standard v2(VNet 통합) + API(service_url=ILB) + operation
   - APIM 인바운드 Private Endpoint(`Gateway`) + 선택적 중앙 zone group
   - Azure AI Search(basic, public off) + Shared Private Link(`Gateway` → APIM)
3. **정적 검증** — `terraform fmt -check`, `terraform validate` (양 레이어).
4. **문서** — DESIGN/README에 BP 근거(공식 문서), 배포·승인·검증 절차, 검증 상태, GPU 교체 가이드.

## 배포 순서

platform → application. application 배포 후 `vnet_id`를 platform `linked_vnet_ids`에 넣고 재apply.

## 수동/후속 단계 (apply 시)

- APIM에서 AI Search SPL **연결 승인**.
- `public_network_access_enabled = false` 전환으로 APIM 완전 사설화.
- 실제 GPU 노드풀/모델로 샘플 워크로드 교체.

## 비범위 (YAGNI)

- 실제 GPU/모델 서빙, 멀티리전, 원격 state, CI, 상세 APIM 정책/인증.

## 위험 / 검증 포인트

- azurerm의 **APIM v2 아웃바운드 VNet 통합** 거동(provider 버전 민감) → 필요 시 `azapi` 보강.
- v2 SKU 생성 시 `public_network_access_enabled=true` 요구 → 사후 전환.
