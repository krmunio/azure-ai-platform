# Azure AI Search → 사설 AKS ILB 통신 BP (APIM Standard v2 중개)

AKS GPU 노드에 AI 모델을 배포하고 **내부 LoadBalancer(ILB)** 로 완전 사설망 엔드포인트를 만든 환경에서,
**Azure AI Search** 가 이 사설 ILB와 통신해야 하는 상황의 **권장(BP)** 구성을 재현하는 시나리오다.

- 설계/근거: [`DESIGN.md`](./DESIGN.md)
- 구현 계획: [`PLAN.md`](./PLAN.md)
- 인프라 코드: [`infra/`](./infra/) — `platform/`(중앙 DNS) + `application/`(워크로드)

## 핵심 요약 (왜 APIM 중개인가)

Azure AI Search의 사설 아웃바운드는 **Shared Private Link(SPL)** 로만 가능하다. 그런데
**SPL 지원 group ID에 AKS·Load Balancer·Application Gateway가 없다**(공식 문서: ASE/AKS 미지원).
→ **SPL로 ILB를 직접 잡을 수 없다.**

해결: SPL이 지원하는 **`Microsoft.ApiManagement/service`(group `Gateway`)** 를 중개 게이트웨이로 두고,
APIM 뒤에서 사설 AKS ILB로 라우팅한다.

> ⚠️ 중요: **클래식 APIM(Internal VNet 주입)은 인바운드 Private Endpoint를 지원하지 않아 SPL 대상이 될 수 없다.**
> 인바운드 PE(=SPL 대상) + 아웃바운드 VNet 통합(=ILB 도달)을 한 인스턴스에서 동시 충족하려면
> **APIM Standard v2(또는 Premium v2)** 가 필요하다. (공식 문서로 검증)

```
AI Search ──SPL(Gateway)──▶ APIM Standard v2 (인바운드 PE + 아웃바운드 VNet 통합) ──http://{ilb_ip}──▶ AKS ILB ──▶ 모델 Pod
```

대안 — 호출 로직이 **custom skill** 이면 `Microsoft.Web/sites`(Functions/App Service, group `sites`)를
중개로 두고 VNet 통합으로 ILB를 호출하는 더 가벼운 구성도 가능하다(본 시나리오는 APIM 권장안만 구현).

## 인프라 구성 (`infra/`)

| 레이어 | 폴더 | 책임 |
| --- | --- | --- |
| platform | [`infra/platform/`](./infra/platform/) | 중앙 Private DNS Zone `privatelink.azure-api.net` + VNet Link |
| application | [`infra/application/`](./infra/application/) | VNet + AKS(ILB) + APIM v2 + AI Search + Shared Private Link |

### application 레이어 배포 리소스

| 리소스 | 비고 |
| --- | --- |
| VNet + 서브넷 3종 | `snet-aks` / `snet-apim`(Microsoft.Web/serverFarms 위임) / `snet-pe` |
| AKS | 경량 시스템 노드풀(**GPU 아님**) + Network Contributor 역할 |
| 샘플 워크로드(모델 엔드포인트) | `kubernetes_config_map` + `kubernetes_deployment`(nginx, 모의 추론 JSON `/`, `/healthz` probe) + `kubernetes_service` type LoadBalancer(`azure-load-balancer-internal=true`, 고정 `ilb_ip`) |
| APIM | **StandardV2_1**, 아웃바운드 VNet 통합(`snet-apim`), API `service_url=http://{ilb_ip}` |
| APIM 인바운드 PE | subresource `Gateway` (SPL 연결 대상) |
| Azure AI Search | `basic`, public access OFF |
| Shared Private Link | `subresource_name=Gateway`, target=APIM (연결은 **수동 승인** 필요) |

## 사전 요구사항

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- 인증된 Azure CLI(`az login`) 또는 동등 자격증명
- AKS / APIM Standard v2 / Azure AI Search(basic+)를 만들 수 있는 구독 권한
- (선택) 중앙 DNS zone group 사용 시 해당 zone에 대한 **Private DNS Zone Contributor** 권한

## 배포 절차

배포 순서: **platform → application**.

### 1. platform (중앙 DNS) — 필요 시

```bash
cd scenarios/aisearch-aks-ilb-private-apim/infra/platform
cp terraform.tfvars.example terraform.tfvars   # subscription_id 등 조정
terraform init && terraform apply
```

### 2. application (워크로드)

```bash
cd scenarios/aisearch-aks-ilb-private-apim/infra/application
cp terraform.tfvars.example terraform.tfvars   # 필요 시 값 조정
terraform init
terraform plan
terraform apply
```

> 중앙 zone에 spoke VNet 연결이 필요하면 application의 `vnet_id` 출력을 platform의
> `linked_vnet_ids`에 넣고 platform을 다시 `apply` 한다.

> **샘플 앱(모델 엔드포인트)**: application `apply`는 AKS에 모의 모델 서버(nginx + ConfigMap,
> `GET /`=추론 JSON, `GET /healthz`=헬스)와 내부 LB 서비스를 함께 배포한다. `kubernetes` provider로
> 자동 배포되며, 동일 워크로드를 [`k8s/sample-model-app.yaml`](./k8s/sample-model-app.yaml)로 `kubectl` 배포할 수도 있다.
>
> ```bash
> az aks get-credentials -g "$(terraform output -raw resource_group_name)" -n "$(terraform output -raw aks_name)"
> kubectl apply -f ../../k8s/sample-model-app.yaml   # Terraform 대신 수동 배포 시
> kubectl get svc model-endpoint-ilb -w              # EXTERNAL-IP = ILB 사설 IP(ilb_ip)
> ```


## 배포 후 수동 단계

1. **SPL 연결 승인**: AI Search가 만든 managed private endpoint를 APIM 측에서 승인한다.
   ```bash
   APIM_ID=$(terraform output -raw apim_id)
   # 보류 중 연결 확인
   az network private-endpoint-connection list --id "$APIM_ID" -o table
   # 승인
   az network private-endpoint-connection approve --id "<connection-id>" \
     --description "Approved for AI Search SPL"
   ```
   AI Search 측 SPL 상태가 `Approved`가 되는지 확인한다.
   ```bash
   az search shared-private-link-resource list \
     --service-name "$(terraform output -raw search_service_name)" \
     -g "$(terraform output -raw resource_group_name)" -o table
   ```

2. **APIM 완전 사설화**: PE 승인 후 `apim_public_network_access_enabled = false`로 바꾸고 재apply.

## 검증

### 정적 검증 (이 repo에서 수행됨)

```bash
cd scenarios/aisearch-aks-ilb-private-apim/infra
terraform -chdir=platform init -backend=false && terraform -chdir=platform validate
terraform -chdir=application init -backend=false && terraform -chdir=application validate
terraform fmt -check -recursive
```

| 항목 | 상태 |
| --- | --- |
| `terraform fmt -check` | ✅ 통과 |
| `terraform validate` (platform/application) | ✅ 통과 |
| `terraform apply` (실 Azure) | ⏳ 사용자 구독 필요 — 미수행 |

### 동작 검증 (apply 후, 사용자 환경)

- AKS ILB가 사설 IP(`ilb_ip`)로 생성됐는지: `kubectl get svc model-endpoint-ilb`
- 샘플 앱 응답 확인(클러스터 내부): `kubectl run curl --rm -it --image=mcr.microsoft.com/azure-cli -- curl -s http://<ilb_ip>/` → 모의 추론 JSON
- APIM에서 ILB 백엔드 호출(테스트 콘솔 또는 VNet 내부 클라이언트): `GET https://<apim>/model/`
- AI Search SPL 상태 `Approved` 후, AI Search가 APIM 사설 IP로 연결되는지 확인.

> ⚠️ provider 버전에 따라 **APIM v2 아웃바운드 VNet 통합** 거동이 다를 수 있다.
> apply 결과가 기대와 다르면 DESIGN.md "apply 단계 유의"를 참고해 `azapi`/CLI로 보강한다.

## 실제 GPU·모델로 교체

네트워크 경로는 GPU 유무와 동일하다. 운영 적용 시:

1. GPU 노드풀 추가 + NVIDIA device plugin.
2. 모델 서빙 Pod(Triton/torchserve/vLLM 등) 배포 후 동일한 internal-LB 서비스로 노출.
3. APIM API `service_url`/operation을 실제 모델 경로·포트로 조정.

## 정리(삭제)

application → platform 역순으로 삭제한다. SPL/PE 연결이 남아 삭제가 막히면 먼저 SPL 리소스를 제거한다.

```bash
cd scenarios/aisearch-aks-ilb-private-apim/infra/application
terraform destroy

cd ../platform
terraform destroy
```

> 모든 리소스명/식별자는 변수·placeholder로 일반화되어 있다(실제 리소스명 하드코딩 금지 규칙 준수).
