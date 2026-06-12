# AKS Multi-NIC (Multus) for CN-Series — PoC

AKS(**Azure CNI Overlay**)에 **Multus**를 배포하고 샘플 파드에 **routable 2nd NIC**를 부착하는
배포 가능한 PoC. CN-Series / Panorama / Prisma는 **설계만**(실배포 제외) 다룬다.

- 설계/배경/AWS 비교: [`DESIGN.md`](./DESIGN.md)
- 구현 계획: [`PLAN.md`](./PLAN.md)

## 무엇을 실증하나

- 고객 운영 모델 재현: 파드 primary `100.64.0.0/16`(non-routable), 노드 `10.x.x.x/22`(routable).
- 파드에 2nd NIC(`net1`) 부착 — 두 가지 데이터플레인:
  - **Approach A** macvlan/ipvlan (static IPAM) — 검사/tap 모드 적합.
  - **Approach B** Azure CNI delegate (전용 routable pod 서브넷) — 파드 단위 추적/태그 정책.
- Multus 설치 두 경로: **관리형 애드온** vs **수동 DaemonSet**.

## 사전 요건

- `az` CLI(로그인 완료), `kubectl`, `terraform >= 1.5.0`
- 대상 구독에 RG/VNet/AKS 생성 권한 및 노드 VM 쿼터(`Standard_D4s_v5` 등)

## 1. 인프라 배포

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars   # subscription_id 등 수정
terraform init
terraform plan
terraform apply

# kubeconfig
$(terraform output -raw get_credentials_command)
```

## 2. Multus 설치 (경로 택1)

**수동 DaemonSet (기본, `enable_managed_multus=false`):**

```bash
kubectl apply -f ../k8s/multus-daemonset/multus-daemonset.yaml
kubectl -n kube-system get pod -l app=multus
```

**관리형 애드온 (preview, `enable_managed_multus=true`):**

관리형 Multus는 **preview**이며 기본 `az` CLI에 활성화 플래그가 없다. `terraform apply`는
자동 활성화 대신 **필요 절차를 안내만** 한다(`aks-preview` 확장 + `EnableManagedMultus` 기능 등록 +
`--enable-managed-multus`, 그리고 `--network-plugin none` 요구로 Overlay와 충돌 가능). 자세한 내용은
[`DESIGN.md` §5/§8](./DESIGN.md). **실제 테스트 가능한 경로는 수동 DaemonSet**이다.

## 3. NetworkAttachmentDefinition + 검증 파드 적용

**Approach A (macvlan):**

```bash
kubectl apply -f ../k8s/nad-macvlan.yaml
kubectl apply -f ../k8s/sample-pod-dualnic.yaml
```

**Approach B (Azure CNI delegate, routable):**

```bash
SUBNET_ID=$(terraform output -raw cn_pod_subnet_id)
sed "s#<SUBNET_ID>#${SUBNET_ID}#" ../k8s/nad-azure-delegate.yaml | kubectl apply -f -
# sample-pod-dualnic.yaml의 어노테이션을 azure-routable-secondary 로 바꿔 적용
```

## 4. 검증

```bash
../scripts/verify-dualnic.sh dualnic-demo default
```

`net1` 인터페이스 존재와 IP 대역을 확인하고, egress 소스 IP가 파드별로 구분되는지 데모한다.

## 검증 상태 (Verification Status)

이 시나리오는 **로컬에서 검증 가능한 부분**과 **라이브 Azure 구독이 있어야 확정되는 부분**을 구분한다.

**로컬에서 검증됨 (이 repo에서 확인 완료):**

- `terraform fmt -check` + `terraform init -backend=false` + `terraform validate` → 통과(provider 스키마 기준 인자 유효).
- 모든 K8s 매니페스트 YAML 문법 + 내장 CNI config JSON 파싱 통과.
- `scripts/verify-dualnic.sh` bash 문법(`bash -n`) 통과.
- 수동 Multus 이미지 태그 `ghcr.io/k8snetworkplumbingwg/multus-cni:v4.1.0-thick` 레지스트리 존재(HTTP 200).

**라이브 Azure에서 직접 확인 필요 (실제 구현/테스트 시):**

- `terraform apply` 성공 및 Overlay 노드풀 정상 기동(구독/쿼터 필요).
- 수동 Multus DaemonSet 정상 동작 + 샘플 파드 `net1` 생성(**Approach A: macvlan over eth0** — 가장 가능성 높은 testable 경로).
- **Approach B(Azure CNI delegate)** 는 실험적/설계 참조이며 그대로 동작 보장 안 됨 — 라이브 검증 필요.
- 관리형 Multus(preview) 활성화 경로 및 Overlay 호환성.
- 자세한 검증 항목: [`DESIGN.md` §8](./DESIGN.md).

> 요약: **Approach A(macvlan/eth0) + 수동 DaemonSet** 경로는 stock AKS에서 `net1` 부착을
> 실제로 테스트할 수 있는 상태다. 단, "routable 2nd NIC"(Approach B)와 관리형 Multus는
> 라이브 검증/설계 검토가 남아 있는 항목이다.

## 제약 / 검증 항목

배포 시점에 현재 공식 문서/실측으로 확인이 필요한 항목은 [`DESIGN.md` §8](./DESIGN.md)에 정리되어 있다:

- Azure CNI Overlay + Multus(관리형/수동) 호환성·지원 매트릭스
- Overlay primary + macvlan/ipvlan(보조 호스트 NIC) 실제 동작
- Azure 패브릭 anti-spoofing으로 인한 Approach A의 라우팅 한계
- Overlay primary + Azure CNI delegate(Approach B) 지원/ preview 상태
- 관리형 Multus 애드온의 지원 리전·k8s 버전·preview 상태

## 5. 정리

```bash
cd infra
terraform destroy
```
