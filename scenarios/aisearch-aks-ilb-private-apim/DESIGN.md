# Azure AI Search → 사설 AKS ILB 연결 (APIM 중개) 설계

## 배경 / 문제

AKS의 GPU 노드에 AI 모델을 배포하고 **내부 LoadBalancer(ILB)** 를 부착해 완전 사설망
엔드포인트를 구성한 상태에서, **Azure AI Search** 가 이 사설 ILB와 통신해야 한다.

Azure AI Search의 사설 아웃바운드 연결 수단은 **Shared Private Link(SPL)** 이다. 그러나
SPL은 **지원되는 리소스 타입(group ID)에 대해서만** managed private endpoint를 만든다.

> 공식 문서 기준 SPL 지원 group ID에 **AKS·Load Balancer·Application Gateway는 없다.**
> 문서는 *"App Service Environment(ASE)와 **Azure Kubernetes Service(AKS)는 현재 미지원**"* 이라고 명시한다.
> ([Connect through a shared private link](https://learn.microsoft.com/azure/search/search-indexer-howto-access-private))

즉 **SPL로 ILB를 직접 대상으로 잡을 수 없다.** 그래서 SPL이 **지원하는 중개 리소스**를 두고
그 뒤에서 사설 ILB로 라우팅하는 우회 설계가 필요하다.

## SPL 지원 group ID (요약)

| 리소스 타입 | group ID |
| --- | --- |
| Microsoft.Storage/storageAccounts | `blob`,`table`,`dfs`,`file` |
| Microsoft.DocumentDB/databaseAccounts | `Sql` |
| Microsoft.Sql/servers | `sqlServer` |
| Microsoft.KeyVault/vaults | `vault` |
| Microsoft.Web/sites (App Service / Functions) | `sites` |
| **Microsoft.ApiManagement/service** | **`Gateway`** |
| Microsoft.CognitiveServices/accounts | `openai_account` 등 |

사설 AKS ILB로 라우팅 가능한 현실적 중개 후보는 **APIM(`Gateway`)** 과
**App Service/Functions(`sites`)** 두 가지다. 본 시나리오는 엔터프라이즈 게이트웨이 BP인
**APIM**을 권장안으로 구현한다.

## 핵심 제약과 올바른 선택 (검증됨)

중개를 APIM으로 둘 때, APIM은 동시에 두 가지를 충족해야 한다.

1. **인바운드**: AI Search SPL(`Gateway`)이 연결할 **Private Endpoint** 대상이 되어야 함.
2. **아웃바운드**: 사설 AKS ILB(사설 IP)에 도달하기 위한 **VNet 연결**이 있어야 함.

여기서 결정적 제약이 있다.

> **클래식 APIM(Internal/External VNet 주입)** 은 *인바운드 Private Endpoint를 지원하지 않는다.*
> 공식 문서: *"In the classic API Management tiers, private endpoints aren't supported in
> instances injected in an internal or external virtual network."*

반면,

> **APIM Standard v2** 는 *"inbound private endpoint + outbound virtual network integration을
> 결합해 end-to-end 네트워크 격리"* 를 공식 지원한다.
> ([Set up inbound private endpoint for APIM](https://learn.microsoft.com/azure/api-management/private-endpoint))

따라서 **APIM은 반드시 v2 SKU(StandardV2/PremiumV2)** 로 구성하고,
**인바운드 Private Endpoint(SPL 대상) + 아웃바운드 VNet 통합(ILB 도달)** 을 함께 둔다.
클래식 Internal 모드는 이 조합이 성립하지 않으므로 사용하지 않는다.

## 아키텍처 / 데이터 흐름

```
┌──────────────────────┐   Shared Private Link (groupId = Gateway)
│   Azure AI Search     │ ───────── managed PE (MS 관리 네트워크) ──────────┐
│ (public access OFF)   │                                                    │
└──────────────────────┘                                                    ▼
                                                       ┌───────────────────────────────┐
                                                       │  APIM Standard v2              │
                                                       │  · 인바운드 Private Endpoint   │  (snet-pe)
                                                       │  · 아웃바운드 VNet 통합        │  (snet-apim, Microsoft.Web/serverFarms 위임)
                                                       │  · API service_url = ILB 사설IP│
                                                       └──────────────┬────────────────┘
                                                                      │ http://{ilb_ip}
                                                                      ▼
                                                       ┌───────────────────────────────┐
                                                       │  AKS 내부 LoadBalancer(ILB)    │  (snet-aks)
                                                       │  azure-load-balancer-internal  │
                                                       └──────────────┬────────────────┘
                                                                      ▼
                                                       ┌───────────────────────────────┐
                                                       │  GPU 노드의 AI 모델 Pod        │
                                                       │  (샘플은 경량 HTTP 서비스)     │
                                                       └───────────────────────────────┘
```

흐름:
1. AI Search가 SPL(`Gateway`)로 APIM에 **managed private endpoint**를 만든다 → APIM 측 **수동 승인**.
2. AI Search는 공중망이 아닌 **APIM의 사설 IP**로 호출한다.
3. APIM은 정책/인증/쓰로틀링 적용 후, **아웃바운드 VNet 통합**을 통해 **AKS ILB 사설 IP**로 프록시.
4. ILB → GPU 노드의 모델 Pod로 전달.

## 범위

- 포함: VNet/3개 서브넷, 경량 AKS + 내부 LB 샘플 서비스, APIM Standard v2(인바운드 PE + 아웃바운드 VNet 통합),
  AI Search + Shared Private Link(`Gateway`), 중앙 DNS(privatelink.azure-api.net) 레이어.
- 제외(YAGNI): 실제 GPU 노드풀/모델 서빙, 멀티리전, 원격 state backend, CI, 상세 APIM 정책.

## 리포지토리 구조 / 레이어

ACR 시나리오와 동일하게 **platform(중앙 DNS) / application(워크로드)** 두 독립 state 레이어로 나눈다.

```
scenarios/aisearch-aks-ilb-private-apim/
  DESIGN.md  PLAN.md  README.md
  k8s/           # 샘플 모델 엔드포인트 매니페스트(kubectl 대안)
  infra/
    platform/      # 중앙 Private DNS Zone(privatelink.azure-api.net) + VNet Link
    application/   # VNet + AKS(ILB) + APIM v2 + AI Search + SPL
```

## Terraform 구성

### platform 레이어
- `azurerm_resource_group` (중앙 DNS RG)
- `azurerm_private_dns_zone` — `privatelink.azure-api.net` (APIM 인바운드 PE 이름 해석용)
- `azurerm_private_dns_zone_virtual_network_link` (for_each `linked_vnet_ids`)

### application 레이어
- 네트워크: `azurerm_virtual_network` + `snet-aks` / `snet-apim`(Microsoft.Web/serverFarms 위임) / `snet-pe`
- AKS: `azurerm_kubernetes_cluster`(시스템 노드풀, GPU 아님) + `azurerm_role_assignment`(Network Contributor, ILB 생성 권한)
- 샘플 워크로드(모델 엔드포인트 모의): `kubernetes_config_map`(추론 JSON + nginx conf) + `kubernetes_deployment`(nginx, `/healthz` probe) + `kubernetes_service`(type LoadBalancer, `azure-load-balancer-internal=true`, 고정 `ilb_ip`). 동일 매니페스트를 `k8s/sample-model-app.yaml`로 kubectl 배포 가능.
- APIM: `azurerm_api_management`(sku=StandardV2_1, `virtual_network_type=External` + `virtual_network_configuration.subnet_id`=snet-apim)
  + `azurerm_api_management_api`(service_url=`http://{ilb_ip}`) + operation
- 인바운드 PE: `azurerm_private_endpoint`(subresource `Gateway`) + 선택적 중앙 zone group
- AI Search: `azurerm_search_service`(basic, public off)
  + `azurerm_search_shared_private_link_service`(subresource_name=`Gateway`, target=APIM id)

## 검증 상태 (repo 규칙)

| 항목 | 상태 |
| --- | --- |
| `terraform fmt -check` (platform/application) | ✅ 통과 |
| `terraform validate` (platform/application) | ✅ 통과 |
| `terraform apply` (실 Azure) | ⏳ 사용자 구독 필요 — 미수행 |
| SPL `Gateway` group ID, AKS 미지원 사실 | ✅ 공식 문서 확인 |
| v2의 인바운드 PE + 아웃바운드 통합 동시 지원 | ✅ 공식 문서 확인 |

### apply 단계 유의 (provider 버전 민감)

- azurerm `azurerm_api_management`는 `virtual_network_type`/`virtual_network_configuration`로
  VNet 연결을 표현한다. **APIM v2의 아웃바운드 VNet 통합**은 provider 버전에 따라 거동이 다를 수 있다.
  apply 시 동작이 기대와 다르면 해당 부분을 `azapi_resource`(또는 포털/CLI 보강)로 대체한다.
- `public_network_access_enabled`는 **생성 시 true가 요구**된다. PE 승인 후 `false`로 전환해 완전 사설화한다.
- SPL 연결은 APIM 측 **수동 승인**이 필요하다(README 절차 참고).

## 실제 GPU·모델로 교체 (운영 적용)

본 시나리오의 네트워크 경로(AI Search→SPL→APIM→ILB)는 GPU 유무와 무관하게 동일하다.
운영에서는 샘플 워크로드 대신:
1. GPU 노드풀 추가: `az aks nodepool add ... --node-vm-size Standard_NC* --labels ...` (+ NVIDIA device plugin).
2. 모델 서빙 Pod 배포(예: Triton/torchserve/vLLM) 후 동일한 internal-LB 서비스로 노출.
3. APIM API `service_url`/operation을 실제 모델 경로·포트에 맞게 조정.
