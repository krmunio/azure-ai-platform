# AKS Multi-NIC (Multus) CN-Series PoC — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** AKS(Azure CNI Overlay)에 Multus를 배포하고 샘플 파드에 routable 2nd NIC를 부착하는 배포 가능한 PoC와 문서를 구현한다.

**Architecture:** Terraform로 VNet(노드/2nd-NIC 서브넷)·AKS(Overlay)·2nd NIC 노드풀·관리형 Multus 토글을 배포. K8s 매니페스트로 수동 Multus 경로와 NAD(Approach A: macvlan/ipvlan, B: Azure CNI delegate) 및 검증용 dual-NIC 파드를 제공. 검증 스크립트로 `net1` 부착·라우터블성을 실증.

**Tech Stack:** Terraform(`azurerm ~> 4.0`), Azure CNI Overlay, Multus CNI(관리형 + upstream DaemonSet), kubectl/Helm, bash.

> 인프라 PoC 특성상 TDD의 "failing test"는 `terraform fmt -check`/`terraform validate`/`terraform plan` 및 매니페스트 `kubectl --dry-run` 검증으로 대체한다. 실제 `apply`는 Azure 구독이 필요하므로 사용자 실행 단계로 둔다.

---

## File Structure

```
scenarios/aks-multinic-cn-series/
  DESIGN.md                      # (완료)
  PLAN.md                        # 본 문서
  README.md                      # 배포/재현/정리 절차
  infra/
    providers.tf                 # terraform/azurerm provider, subscription_id
    variables.tf                 # 위치/이름/CIDR/multus 토글 변수
    main.tf                      # RG, VNet, 서브넷(node/2nd-nic/cn-pod), AKS(Overlay), 2nd NIC 노드풀
    outputs.tf                   # 클러스터명/kubeconfig 명령/서브넷 ID
    terraform.tfvars.example     # 예시 변수
    .gitignore                   # state/tfvars 제외
  k8s/
    multus-daemonset/multus-daemonset.yaml   # upstream 수동 설치(버전 고정)
    nad-macvlan.yaml             # Approach A
    nad-azure-delegate.yaml      # Approach B
    sample-pod-dualnic.yaml      # 검증 파드(net1 어노테이션)
    cn-series/cn-series-sketch.yaml          # 설계 스케치(apply 비대상, 주석)
  scripts/
    verify-dualnic.sh            # net1/IP/추적성 데모
```

- 각 파일은 단일 책임. Terraform은 단일 레이어(PoC라 platform/application 분리 불필요).
- 기존 ACR 시나리오 컨벤션 준수: `azurerm ~> 4.0`, `terraform >= 1.5.0`, `var.subscription_id`, state/tfvars gitignore.

---

## Task 1: 시나리오 골격 + .gitignore

**Files:**
- Create: `scenarios/aks-multinic-cn-series/infra/.gitignore`

- [ ] **Step 1: .gitignore 작성**

```gitignore
.terraform/
*.tfstate
*.tfstate.*
crash.log
crash.*.log
*.tfvars
!*.tfvars.example
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
```

- [ ] **Step 2: 커밋**

```bash
git add scenarios/aks-multinic-cn-series/infra/.gitignore
git commit -m "chore(aks-multinic-cn-series): infra .gitignore 추가"
```

---

## Task 2: Terraform providers + variables

**Files:**
- Create: `scenarios/aks-multinic-cn-series/infra/providers.tf`
- Create: `scenarios/aks-multinic-cn-series/infra/variables.tf`

- [ ] **Step 1: providers.tf 작성**

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
```

- [ ] **Step 2: variables.tf 작성**

```hcl
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
  description = "2nd NIC routable 서브넷"
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
  description = "노드 VM 크기(2nd NIC 지원 필요)"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "enable_managed_multus" {
  description = "관리형 Multus 애드온 활성화 여부(false면 수동 DaemonSet 경로 사용)"
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
```

- [ ] **Step 3: 검증**

Run: `cd scenarios/aks-multinic-cn-series/infra && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: validate 시점에 main.tf가 없으면 변수만으로는 통과하지 않을 수 있음 → Task 3 이후 재검증. 최소 `terraform fmt -check` PASS.

- [ ] **Step 4: 커밋**

```bash
git add scenarios/aks-multinic-cn-series/infra/providers.tf scenarios/aks-multinic-cn-series/infra/variables.tf
git commit -m "feat(aks-multinic-cn-series): terraform providers/variables 추가"
```

---

## Task 3: Terraform main.tf (VNet/서브넷/AKS Overlay/2nd NIC 노드풀)

**Files:**
- Create: `scenarios/aks-multinic-cn-series/infra/main.tf`

- [ ] **Step 1: main.tf 작성**

```hcl
resource "azurerm_resource_group" "this" {
  name     = "${var.prefix}-rg"
  location = var.location
  tags     = var.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "${var.prefix}-vnet"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "node" {
  name                 = "node-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.node_subnet_cidr]
}

# 2nd NIC(routable) 서브넷 — macvlan/ipvlan(Approach A)용 호스트 보조 NIC가 위치
resource "azurerm_subnet" "secondary_nic" {
  name                 = "secondary-nic-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.secondary_nic_subnet_cidr]
}

# Approach B(Azure CNI delegate)용 전용 pod 서브넷(routable)
resource "azurerm_subnet" "cn_pod" {
  name                 = "cn-pod-subnet"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.cn_pod_subnet_cidr]
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  dns_prefix          = "${var.prefix}-aks"
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = azurerm_subnet.node.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.pod_cidr_overlay
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
  }

  tags = var.tags
}

# 관리형 Multus 애드온 — provider 직접 지원이 없을 수 있어 azapi 또는 az CLI로 토글.
# 본 PoC에서는 enable_managed_multus=true일 때 local-exec로 활성화(검증 항목, README 참조).
resource "null_resource" "managed_multus" {
  count = var.enable_managed_multus ? 1 : 0

  triggers = {
    cluster_id = azurerm_kubernetes_cluster.this.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      az aks update \
        --resource-group ${azurerm_resource_group.this.name} \
        --name ${azurerm_kubernetes_cluster.this.name} \
        --enable-multus || \
      echo "[WARN] 관리형 Multus 활성화 실패 — preview 확장/기능 등록 필요할 수 있음(DESIGN.md §8 참조)"
    EOT
  }
}
```

> 주: `null_resource`는 `hashicorp/null` provider가 필요. providers.tf의 `required_providers`에 추가한다(아래 Step 2).

- [ ] **Step 2: providers.tf에 null provider 추가**

`providers.tf`의 `required_providers` 블록을 다음으로 교체:

```hcl
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
```

- [ ] **Step 3: 검증**

Run: `cd scenarios/aks-multinic-cn-series/infra && terraform fmt && terraform init -backend=false && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: 커밋**

```bash
git add scenarios/aks-multinic-cn-series/infra/main.tf scenarios/aks-multinic-cn-series/infra/providers.tf
git commit -m "feat(aks-multinic-cn-series): VNet/AKS(Overlay)/2nd NIC 서브넷 + 관리형 Multus 토글"
```

---

## Task 4: Terraform outputs + tfvars 예시

**Files:**
- Create: `scenarios/aks-multinic-cn-series/infra/outputs.tf`
- Create: `scenarios/aks-multinic-cn-series/infra/terraform.tfvars.example`

- [ ] **Step 1: outputs.tf 작성**

```hcl
output "resource_group" {
  value = azurerm_resource_group.this.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "get_credentials_command" {
  description = "kubeconfig 가져오기"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name}"
}

output "secondary_nic_subnet_id" {
  value = azurerm_subnet.secondary_nic.id
}

output "cn_pod_subnet_id" {
  description = "Approach B(Azure CNI delegate) NAD에서 사용할 서브넷 ID"
  value       = azurerm_subnet.cn_pod.id
}
```

- [ ] **Step 2: terraform.tfvars.example 작성**

```hcl
# 복사: cp terraform.tfvars.example terraform.tfvars
subscription_id       = "00000000-0000-0000-0000-000000000000"
location              = "australiaeast"
prefix                = "aksmnic"
node_count            = 2
node_vm_size          = "Standard_D4s_v5"
enable_managed_multus = false # true면 az CLI로 관리형 Multus 활성화 시도
```

- [ ] **Step 3: 검증**

Run: `cd scenarios/aks-multinic-cn-series/infra && terraform fmt -check && terraform validate`
Expected: PASS / `configuration is valid`.

- [ ] **Step 4: 커밋**

```bash
git add scenarios/aks-multinic-cn-series/infra/outputs.tf scenarios/aks-multinic-cn-series/infra/terraform.tfvars.example
git commit -m "feat(aks-multinic-cn-series): outputs 및 tfvars 예시 추가"
```

---

## Task 5: 수동 Multus DaemonSet 매니페스트

**Files:**
- Create: `scenarios/aks-multinic-cn-series/k8s/multus-daemonset/multus-daemonset.yaml`

- [ ] **Step 1: 매니페스트 작성**

upstream `k8snetworkplumbingwg/multus-cni`의 thick plugin daemonset(버전 고정)을 기반으로 작성한다. 이미지 태그를 명시적으로 고정한다(예: `ghcr.io/k8snetworkplumbingwg/multus-cni:v4.1.0`). 파일 상단 주석에 출처/적용 명령을 기록:

```yaml
# 출처: https://github.com/k8snetworkplumbingwg/multus-cni (thick plugin)
# 적용: kubectl apply -f multus-daemonset.yaml
# 관리형 애드온 대신 수동 설치 경로(이식성/버전제어 목적). 버전 고정 필수.
# enable_managed_multus=false 일 때 사용.
# 전체 매니페스트는 아래 upstream 릴리스의 deployments/multus-daemonset-thick.yml 을
# v4.1.0 태그로 고정하여 포함한다.
```

> 구현 시: `curl -sSL https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v4.1.0/deployments/multus-daemonset-thick.yml` 내용을 그대로 저장하고, 이미지 태그가 `:stable`/`:snapshot`이면 `:v4.1.0`으로 고정한다.

- [ ] **Step 2: 검증**

Run: `kubectl apply --dry-run=client -f scenarios/aks-multinic-cn-series/k8s/multus-daemonset/multus-daemonset.yaml`
Expected: 모든 리소스 `(dry run)` 출력, 에러 없음. (kubectl 미설치 시: `kubectl`을 설치하거나 YAML 문법 검사 `python -c "import yaml,sys; list(yaml.safe_load_all(open(sys.argv[1])))" <file>` 로 대체.)

- [ ] **Step 3: 커밋**

```bash
git add scenarios/aks-multinic-cn-series/k8s/multus-daemonset/multus-daemonset.yaml
git commit -m "feat(aks-multinic-cn-series): 수동 Multus DaemonSet 매니페스트(v4.1.0 고정)"
```

---

## Task 6: NetworkAttachmentDefinition — Approach A (macvlan/ipvlan)

**Files:**
- Create: `scenarios/aks-multinic-cn-series/k8s/nad-macvlan.yaml`

- [ ] **Step 1: NAD 작성**

```yaml
# Approach A: 노드 보조 NIC(eth1) 위 macvlan, static IPAM.
# 한계: Azure 패브릭 anti-spoofing으로 VNet-routable 보장 안 됨(검사/tap 모드 적합). DESIGN.md §6/§8.
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: macvlan-secondary
  namespace: default
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "macvlan",
      "master": "eth1",
      "mode": "bridge",
      "ipam": {
        "type": "static",
        "addresses": [
          { "address": "10.0.8.10/24", "gateway": "10.0.8.1" }
        ]
      }
    }
```

- [ ] **Step 2: 검증**

Run: `kubectl apply --dry-run=client -f scenarios/aks-multinic-cn-series/k8s/nad-macvlan.yaml` (또는 YAML 문법 검사)
Expected: 에러 없음.

- [ ] **Step 3: 커밋**

```bash
git add scenarios/aks-multinic-cn-series/k8s/nad-macvlan.yaml
git commit -m "feat(aks-multinic-cn-series): NAD macvlan(Approach A) 추가"
```

---

## Task 7: NetworkAttachmentDefinition — Approach B (Azure CNI delegate)

**Files:**
- Create: `scenarios/aks-multinic-cn-series/k8s/nad-azure-delegate.yaml`

- [ ] **Step 1: NAD 작성**

```yaml
# Approach B: Azure CNI delegate로 전용 routable pod 서브넷(cn-pod-subnet)에서 IP 할당.
# 파드 2nd NIC가 Azure-인지 routable IP 획득 → 파드 단위 추적/태그 정책 가능(요구사항 정합).
# 검증 필요(Overlay primary + Azure CNI delegate / preview): DESIGN.md §8.
# <SUBNET_ID> 는 terraform output cn_pod_subnet_id 값으로 치환.
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: azure-routable-secondary
  namespace: default
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "azure-vnet",
      "mode": "bridge",
      "ipam": {
        "type": "azure-vnet-ipam"
      },
      "subnet": "<SUBNET_ID>"
    }
```

- [ ] **Step 2: 검증**

Run: YAML 문법 검사 또는 `kubectl apply --dry-run=client -f ...`
Expected: 에러 없음. (실제 동작은 apply 후 검증 — DESIGN.md §8.)

- [ ] **Step 3: 커밋**

```bash
git add scenarios/aks-multinic-cn-series/k8s/nad-azure-delegate.yaml
git commit -m "feat(aks-multinic-cn-series): NAD Azure CNI delegate(Approach B) 추가"
```

---

## Task 8: 검증용 dual-NIC 샘플 파드

**Files:**
- Create: `scenarios/aks-multinic-cn-series/k8s/sample-pod-dualnic.yaml`

- [ ] **Step 1: 파드 매니페스트 작성**

```yaml
# net1 = Multus 2nd NIC. 기본은 Approach A(macvlan-secondary).
# Approach B 검증 시 어노테이션을 azure-routable-secondary 로 변경.
apiVersion: v1
kind: Pod
metadata:
  name: dualnic-demo
  namespace: default
  annotations:
    k8s.v1.cni.cncf.io/networks: macvlan-secondary
spec:
  containers:
    - name: net-tools
      image: nicolaka/netshoot:latest
      command: ["sleep", "infinity"]
  restartPolicy: Never
```

- [ ] **Step 2: 검증**

Run: `kubectl apply --dry-run=client -f scenarios/aks-multinic-cn-series/k8s/sample-pod-dualnic.yaml`
Expected: `pod/dualnic-demo created (dry run)`.

- [ ] **Step 3: 커밋**

```bash
git add scenarios/aks-multinic-cn-series/k8s/sample-pod-dualnic.yaml
git commit -m "feat(aks-multinic-cn-series): dual-NIC 검증 파드 추가"
```

---

## Task 9: CN-Series 설계 스케치(apply 비대상)

**Files:**
- Create: `scenarios/aks-multinic-cn-series/k8s/cn-series/cn-series-sketch.yaml`

- [ ] **Step 1: 스케치 작성(전부 주석/플레이스홀더, 실배포 금지 명시)**

```yaml
# ============================================================
# CN-Series 설계 스케치 — apply 대상 아님.
# 실배포에는 Palo Alto 라이선스/이미지/Panorama 연동 필요.
# 공식: https://github.com/PaloAltoNetworks/cn-series-helm
#       https://docs.paloaltonetworks.com/pan-os/10-1/.../deploy-the-cn-series-as-a-kubernetes-service
# ------------------------------------------------------------
# 요지:
#  - CN-NGFW(데이터플레인) DaemonSet/Deployment가 Multus 2nd NIC(net1)로
#    검사 트래픽을 받도록 k8s.v1.cni.cncf.io/networks 어노테이션 지정.
#  - PAN-CN-MGMT(관리플레인)가 Panorama에 등록, 라이선스/정책 수신.
#  - Helm values 예: multus.enable=true, plugins.dataplane 인터페이스=net1.
# ------------------------------------------------------------
# 예시(개념) — 실제 차트 값으로 대체 필요:
# annotations:
#   k8s.v1.cni.cncf.io/networks: azure-routable-secondary
# ============================================================
```

- [ ] **Step 2: 커밋**

```bash
git add scenarios/aks-multinic-cn-series/k8s/cn-series/cn-series-sketch.yaml
git commit -m "docs(aks-multinic-cn-series): CN-Series 설계 스케치(비배포) 추가"
```

---

## Task 10: 검증 스크립트

**Files:**
- Create: `scenarios/aks-multinic-cn-series/scripts/verify-dualnic.sh`

- [ ] **Step 1: 스크립트 작성**

```bash
#!/usr/bin/env bash
# 샘플 파드의 2nd NIC(net1) 부착과 IP를 검증하고 추적성을 데모한다.
# 사전: kubectl 컨텍스트가 대상 AKS로 설정됨, Multus + NAD + 파드 배포 완료.
set -euo pipefail

POD="${1:-dualnic-demo}"
NS="${2:-default}"

echo "== [1] 파드 상태 =="
kubectl -n "$NS" get pod "$POD" -o wide

echo "== [2] 네트워크 어노테이션(Multus) =="
kubectl -n "$NS" get pod "$POD" -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/networks}{"\n"}'

echo "== [3] 파드 인터페이스(net1 존재 확인) =="
kubectl -n "$NS" exec "$POD" -- ip -brief addr show

echo "== [4] net1 IP 추출 =="
NET1_IP=$(kubectl -n "$NS" exec "$POD" -- sh -c "ip -4 -o addr show net1 2>/dev/null | awk '{print \$4}'" || true)
if [ -n "${NET1_IP}" ]; then
  echo "net1 IP = ${NET1_IP}  (routable 서브넷 대역인지 확인)"
else
  echo "[WARN] net1 미발견 — Multus/NAD/어노테이션 구성을 확인하세요(DESIGN.md §8)."
fi

echo "== [5] (Approach B) egress 소스 IP 데모 =="
echo "외부에서 관찰되는 소스 IP가 노드 SNAT가 아닌 파드별 routable IP인지 확인하세요."
echo "예: kubectl -n $NS exec $POD -- curl -s https://ifconfig.me ; 또는 대상 리소스의 접근 로그 확인."
```

- [ ] **Step 2: 실행권한 부여 + 문법 검사**

Run: `chmod +x scenarios/aks-multinic-cn-series/scripts/verify-dualnic.sh && bash -n scenarios/aks-multinic-cn-series/scripts/verify-dualnic.sh`
Expected: 에러 없음(문법 OK).

- [ ] **Step 3: 커밋**

```bash
git add scenarios/aks-multinic-cn-series/scripts/verify-dualnic.sh
git commit -m "feat(aks-multinic-cn-series): dual-NIC 검증 스크립트 추가"
```

---

## Task 11: README (배포/재현/정리 절차)

**Files:**
- Create: `scenarios/aks-multinic-cn-series/README.md`

- [ ] **Step 1: README 작성**

다음 섹션 포함: 개요(DESIGN.md 링크) · 사전요건(az CLI, kubectl, terraform, 구독 권한, 적절한 VM 쿼터) · 배포 절차(`terraform init/plan/apply`, `az aks get-credentials`) · Multus 경로 선택(수동 `kubectl apply -f k8s/multus-daemonset/` 또는 `enable_managed_multus=true`) · NAD/파드 적용(Approach A/B) · 검증(`scripts/verify-dualnic.sh`) · 제약/검증 항목(DESIGN.md §8 참조) · 정리(`terraform destroy`).

- [ ] **Step 2: 루트 README 인덱스 표에 한 줄 추가**

`/README.md`의 시나리오 인덱스 표에 추가:

```
| [`aks-multinic-cn-series`](./scenarios/aks-multinic-cn-series/) | AKS(Azure CNI Overlay)에 Multus로 2nd NIC 부착 PoC + CN-Series 설계/AWS 비교 |
```

- [ ] **Step 3: 커밋**

```bash
git add scenarios/aks-multinic-cn-series/README.md README.md
git commit -m "docs(aks-multinic-cn-series): README 및 루트 인덱스 추가"
```

---

## Task 12: 최종 검증

- [ ] **Step 1: Terraform 전체 검증**

Run: `cd scenarios/aks-multinic-cn-series/infra && terraform fmt -check && terraform init -backend=false && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 2: 매니페스트 YAML 문법 검증**

Run: `for f in scenarios/aks-multinic-cn-series/k8s/**/*.yaml scenarios/aks-multinic-cn-series/k8s/*.yaml; do python -c "import yaml,sys;list(yaml.safe_load_all(open(sys.argv[1])))" "$f" && echo "OK $f"; done`
Expected: 모든 파일 OK.

- [ ] **Step 3: 스크립트 문법 검증**

Run: `bash -n scenarios/aks-multinic-cn-series/scripts/verify-dualnic.sh`
Expected: 에러 없음.

---

## Self-Review 체크

- **Spec coverage**: DESIGN §3(아키텍처)→T2-4, §5(Multus 관리형/수동)→T3·T5, §6(Approach A/B/C)→T6·T7(+C는 문서), §7(추적성)→T8·T10, §9(AWS 비교)→DESIGN 완료, §8(검증항목)→README·verify 스크립트. 커버됨.
- **Placeholder scan**: NAD-B의 `<SUBNET_ID>`, 수동 Multus의 upstream 인용은 의도된 외부 의존(치환/다운로드 명령 명시). CN-Series 스케치는 비배포 명시.
- **Type/name 일관성**: NAD 이름(`macvlan-secondary`/`azure-routable-secondary`)·서브넷 이름(`cn-pod-subnet`)·output(`cn_pod_subnet_id`)·파드 어노테이션 일치.
