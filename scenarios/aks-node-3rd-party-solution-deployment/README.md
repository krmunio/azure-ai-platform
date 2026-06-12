# AKS Worker Node 3rd Party 솔루션 배포 시나리오

AKS **워커 노드**에 3rd party 솔루션(보안 에이전트, 스토리지 SDC, DLP 등)을 배포하는
방법을 **케이스별로** 정리한 시나리오다. 솔루션이 컨테이너만으로 동작하는지, 아니면
**호스트 OS 레벨 설치**가 필요한지에 따라 전략이 갈린다.

- 설계: [`DESIGN.md`](./DESIGN.md)
- 매니페스트: [`manifests/`](./manifests/) — `debug-daemonset.yaml`, `installer-daemonset.yaml`, `installer-configmap.yaml`, `Dockerfile.installer`, `helm-values.example.yaml`
- 인프라(최소 AKS+ACR): [`infra/`](./infra/)

> 본 문서는 **일반화된 패턴**을 다룬다. 특정 벤더 제품명/라이선스는 포함하지 않는다.
> 명령의 `<...>` 자리표시자는 환경에 맞게 치환한다.

---

## 1. 배경

AKS는 **관리형 노드**를 제공한다. 노드 VM은 AKS가 라이프사이클(업그레이드·스케일·재이미지)을
관리하며, 운영자의 SSH/노드 직접 접근은 기본적으로 제한된다. 그러나 규제 환경에서는
워커 노드에 3rd party 솔루션을 빠짐없이 배포해야 한다.

솔루션은 두 부류로 나뉜다.

1. **컨테이너만으로 동작** — 에이전트/probe가 Pod 안에서 실행. → **케이스 A**
2. **호스트 OS 레벨 설치 필요** — `systemd` 서비스 상주 또는 커널 모듈 적재. → **케이스 B**

> ⚠️ **재이미지/스케일아웃 주의**: 관리형 노드는 업그레이드·스케일아웃 시 새 OS 디스크로
> 교체될 수 있다. 호스트 레벨 설치(케이스 B)는 **DaemonSet으로 멱등하게 재실행**되어
> 새 노드에서 자동 재설치되도록 설계해야 한다.

---

## 2. 케이스 분류

| 케이스 | 적용 상황 | 메커니즘 | 대표 산출물 |
| --- | --- | --- | --- |
| **A. Helm Chart 기반 DaemonSet** | 솔루션이 **컨테이너만으로** 동작 | Helm으로 privileged DaemonSet 배포. 노드당 1 Pod 상주, agent를 컨테이너 내 실행, 중앙 콘솔 자동 연결 | [`helm-values.example.yaml`](./manifests/helm-values.example.yaml) |
| **B. Installer-DaemonSet 기반** | **호스트 OS 레벨 설치** 필요 | DaemonSet이 install script를 `nsenter`/`chroot`로 호스트에서 headless 실행 → 호스트에 패키지 설치 + `systemd` 등록 | [`installer-daemonset.yaml`](./manifests/installer-daemonset.yaml), [`installer-configmap.yaml`](./manifests/installer-configmap.yaml) |

두 케이스 모두 노드 전체 적용을 위해 **DaemonSet**을 토대로 한다. 차이는
"컨테이너 안에서 도는가(A)" vs "호스트에 설치하는가(B)"다.

---

## 3. 구성이 필요한 환경 / 사전 요구사항

| 항목 | 요구사항 |
| --- | --- |
| AKS 클러스터 | 시스템/사용자 노드풀. 본 시나리오 [`infra/`](./infra/)로 최소 구성 배포 가능 |
| 노드 OS | Ubuntu (예: 22.04 / 24.04). 패키지 포맷(`.deb`/`.tar`)이 OS 버전과 일치해야 함 |
| 권한 | 호스트 설치(케이스 B)는 **privileged 컨테이너 + hostPID + hostPath** 필요 |
| Pod Security | 네임스페이스가 privileged Pod를 허용해야 함 (PSA `privileged`). 예: `kube-system` |
| 이미지/패키지 반입 | 폐쇄망 가정. 설치 파일은 **이미지에 번들**하거나 **ACR**로 반입(외부 다운로드 불가정) |
| 도구 | `kubectl`, `helm`(케이스 A), `az`(인프라), `terraform`(인프라) |

> 노드 OS와 패키지 아키텍처(x86_64/arm64) 불일치는 케이스 B 설치 실패의 가장 흔한 원인이다.
> 노드풀이 혼합 OS/아키텍처면 `nodeSelector`로 분리 배포한다.

---

## 4. Debug node 띄우는 방법

노드에 직접 접근할 수 없으므로, **호스트 네임스페이스로 진입하는 임시 Pod**를 띄워
진단/수동 검증을 한다. 두 가지 방법이 있다.

### 방법 1: `kubectl debug node` (권장, 단발성 진단)

```bash
# 대상 노드에 호스트 루트가 /host로 마운트된 임시 Pod 생성
kubectl debug node/<node-name> -it --image=ubuntu:22.04 -- bash

# Pod 내부: 호스트 파일시스템은 /host 하위에 마운트됨
chroot /host        # 호스트 컨텍스트로 진입
systemctl status    # 호스트 systemd 확인
exit                # debug pod 종료 시 자동 정리
```

### 방법 2: privileged debug DaemonSet (모든 노드 상주 진단)

모든 노드에 동시에 진입해야 하거나 반복 진단이 필요할 때 사용한다.
[`manifests/debug-daemonset.yaml`](./manifests/debug-daemonset.yaml) 참조.

```bash
kubectl apply -f manifests/debug-daemonset.yaml

# 특정 노드의 debug pod로 진입
POD=$(kubectl -n kube-system get pod -l app=node-debug \
  --field-selector spec.nodeName=<node-name> -o jsonpath='{.items[0].metadata.name}')
kubectl -n kube-system exec -it "$POD" -- nsenter -t 1 -m -u -i -n -p -- bash

# 정리
kubectl delete -f manifests/debug-daemonset.yaml
```

> `nsenter -t 1 ...`는 PID 1(호스트 init)의 네임스페이스로 진입한다(hostPID 필요).
> `chroot /host`는 파일시스템만 호스트로 바꾼다. 설치엔 보통 둘 중 하나면 충분하다.

---

## 5. 호스트에 파일 설치 방법

debug node(또는 케이스 B의 Installer-DaemonSet)에서 호스트 컨텍스트로 진입한 뒤 설치한다.

### `.deb` 패키지 설치 (예: Ubuntu)

```bash
# 호스트 루트가 /host로 마운트된 컨테이너 안에서
cp /staging/<solution>.deb /host/tmp/
chroot /host /bin/bash -c "dpkg -i /tmp/<solution>.deb || apt-get install -f -y"

# headless(비대화형) 설치가 필요하면 환경변수/응답파일로 프롬프트 억제
chroot /host /bin/bash -c "DEBIAN_FRONTEND=noninteractive dpkg -i /tmp/<solution>.deb"
```

### `.tar` 아카이브 + 설치 스크립트 (예: SDC/probe류)

```bash
cp /staging/<solution>.tar /host/tmp/
chroot /host /bin/bash -c "
  mkdir -p /opt/<solution> &&
  tar -xf /tmp/<solution>.tar -C /opt/<solution> &&
  /opt/<solution>/install.sh --silent
"
```

### 설치 검증 (systemd 서비스)

```bash
chroot /host systemctl enable --now <solution>.service
chroot /host systemctl status <solution>.service --no-pager
chroot /host journalctl -u <solution>.service --no-pager | tail -n 30
```

> **멱등성**: 케이스 B의 DaemonSet은 노드가 새로 뜰 때마다 install script를 재실행한다.
> 스크립트는 "이미 설치됨"을 감지해 **중복 설치를 건너뛰도록** 작성한다
> (예: `systemctl is-active <solution> && exit 0`). 예시는
> [`manifests/installer-configmap.yaml`](./manifests/installer-configmap.yaml) 참조.

---

## 6. 설치 파일을 노드로 복사하는 방법

설치 파일(`.deb`/`.tar`)을 노드(또는 설치 컨테이너)로 가져오는 4가지 방법과 장단점.

| 방법 | 설명 | 장점 | 단점 / 주의 |
| --- | --- | --- | --- |
| **(a) 컨테이너 이미지에 번들** | 설치 파일을 이미지에 `COPY`해 ACR로 push. DaemonSet이 그 이미지를 사용 | 폐쇄망 친화적, 버전 고정, 멱등 재설치에 강함 | 이미지 재빌드 필요, 이미지 크기 증가 |
| **(b) ConfigMap (스크립트)** | install **스크립트**를 ConfigMap으로 주입(`volumeMount`) | 바이너리 분리, 스크립트만 빠르게 수정 | ConfigMap은 ~1MiB 제한 → **바이너리 자체는 부적합**(스크립트 전용) |
| **(c) `hostPath` 경유** | 미리 노드 디렉터리에 둔 파일을 `hostPath`로 마운트 | 대용량 가능 | 노드에 사전 배치 수단 필요(닭-달걀), 재이미지 시 소실 |
| **(d) `kubectl cp` + debug pod** | debug pod로 파일 복사 후 `/host`에 두기 | 임시/수동 검증에 간편 | 노드별 수동, 자동화/멱등성 부적합 |

**권장 조합**
- **운영/자동화(케이스 B)**: **(a) 이미지 번들** + **(b) ConfigMap 스크립트**.
  바이너리는 이미지에, 로직은 ConfigMap에 두어 DaemonSet이 멱등 재설치.
- **일회성 진단/PoC**: **(d) `kubectl cp`** + debug pod.

```bash
# (d) 예시: debug pod로 파일 복사 후 호스트로 이동
kubectl -n kube-system cp ./<solution>.deb <debug-pod>:/host/tmp/<solution>.deb
kubectl -n kube-system exec -it <debug-pod> -- chroot /host dpkg -i /tmp/<solution>.deb
```

---

## 7. 케이스 A: Helm Chart 기반 DaemonSet 배포

솔루션이 컨테이너만으로 동작할 때. 벤더가 Helm Chart를 제공하는 경우가 많다.

```bash
# 1) (폐쇄망) 차트/이미지를 사내로 반입 후 이미지를 ACR로 push
#    helm pull <repo>/<chart> --version <ver>  (인터넷 환경에서 미리 받아 반입)

# 2) values 작성: manifests/helm-values.example.yaml 참고
#    - image.repository 를 ACR로 지정
#    - daemonset 권한(hostNetwork/hostPID/privileged) 및 중앙 콘솔 주소 설정

# 3) 설치
helm install <release> <chart-ref> \
  -n kube-system \
  -f manifests/helm-values.example.yaml

# 4) 롤아웃/Pod 검증 (노드당 1 Pod, Running)
kubectl -n kube-system rollout status ds/<release>
kubectl -n kube-system get pods -l app.kubernetes.io/name=<chart> -o wide
```

기대 결과: 노드 수만큼 DaemonSet Pod가 `Running 1/1`, 중앙 관리 콘솔에 노드가 자동 등록.

---

## 8. 케이스 B: Installer-DaemonSet 기반 호스트 설치

호스트 OS 레벨 설치가 필요할 때. DaemonSet이 install script를 호스트에서 headless로 실행한다.

```bash
# 0) (선행) 설치 패키지를 번들한 installer 이미지 빌드/푸시
#    Dockerfile: manifests/Dockerfile.installer
ACR=$(cd infra && terraform output -raw acr_login_server)
az acr login -n "${ACR%%.*}"
docker build -f manifests/Dockerfile.installer \
  --build-arg PKG_SRC=./mysolution.deb \
  -t "$ACR/solution-installer:latest" manifests/
docker push "$ACR/solution-installer:latest"
#    → installer-daemonset.yaml의 image를 위 태그로 치환(<acr> 자리)

# 1) install script(ConfigMap)와 DaemonSet 배포
kubectl apply -f manifests/installer-configmap.yaml
kubectl apply -f manifests/installer-daemonset.yaml

# 2) install script 변경 시 DaemonSet 재기동으로 전 노드 재설치 트리거
kubectl -n kube-system rollout restart ds/<solution>-installer

# 3) 설치 Pod 상태 확인 (각 노드에서 설치 후 sleep 상주 또는 완료)
kubectl -n kube-system get pods -l name=<solution>-installer -o wide

# 4) 호스트 서비스 정상 동작 확인 (debug pod 경유)
kubectl debug node/<node-name> -it --image=ubuntu:22.04 -- \
  chroot /host systemctl status <solution>.service --no-pager
```

> ⚠️ **0번 단계 필수**: `installer-daemonset.yaml`의 `image`는 `<acr>.azurecr.io/...`
> 자리표시자다. 이미지를 먼저 빌드/푸시하고 태그를 치환하지 않으면 Pod가
> `ImagePullBackOff`로 뜬다. `PKG_PATH`/`SERVICE_NAME` env도 실제 패키지·서비스명으로 맞춘다.

기대 결과: 설치 DaemonSet Pod가 모든 노드에서 정상 종료/상주하고, 각 호스트에서
`<solution>.service`가 `active (running)`.

---

## 9. 인프라 배포 (`infra/`)

진단/재현용 **최소 AKS + ACR**를 Terraform으로 배포한다.

```bash
cd scenarios/aks-node-3rd-party-solution-deployment/infra
cp terraform.tfvars.example terraform.tfvars   # 값 조정
terraform init
terraform apply

# 클러스터 자격증명 가져오기
az aks get-credentials \
  -g "$(terraform output -raw resource_group_name)" \
  -n "$(terraform output -raw aks_name)"
```

배포 리소스: Resource Group, ACR, AKS(시스템 노드풀) + 사용자 노드풀(Ubuntu).

### 정리(삭제)

```bash
# 워크로드 먼저 제거 (k8s 매니페스트만 — Dockerfile/values 제외)
kubectl delete -f manifests/installer-daemonset.yaml -f manifests/installer-configmap.yaml \
  -f manifests/debug-daemonset.yaml --ignore-not-found
helm uninstall <release> -n kube-system 2>/dev/null || true

cd scenarios/aks-node-3rd-party-solution-deployment/infra
terraform destroy
```

---

## 10. 트러블슈팅

| 증상 | 원인 | 해결 |
| --- | --- | --- |
| 설치 Pod `CrashLoopBackOff` | privileged/hostPID 미허용 (PSA 차단) | 네임스페이스 PSA를 `privileged`로, securityContext 확인 |
| `dpkg: error ... cannot access` | 호스트 마운트(`/host`) 누락 또는 chroot 경로 오류 | `hostPath: /` 마운트와 `chroot /host` 경로 점검 |
| 노드 스케일아웃 후 미설치 | 멱등 재설치 미설계 | Installer-DaemonSet 사용, 새 노드에서 자동 재실행되는지 확인 |
| 패키지 설치 실패(아키텍처/OS 불일치) | `.deb`/`.tar`가 노드 OS·아키텍처와 불일치 | `nodeSelector`로 OS/arch별 분리, 올바른 패키지 사용 |
| 중앙 콘솔에 노드 미등록(케이스 A) | 콘솔 주소/토큰 values 오설정, egress 차단 | Helm values의 콘솔 엔드포인트·자격증명, NSG/egress 점검 |

---

## 11. 구현·테스트 준비 점검

이 시나리오를 실제로 구현/테스트하기 전 점검 항목과, **직접 채워야 하는 값**이다.

### 사전 검증 완료 (저장소 단계)

| 항목 | 도구 | 결과 |
| --- | --- | --- |
| `infra/` 유효성 | `terraform validate` | ✅ Valid |
| `infra/` 배포 계획 | `terraform plan` | ✅ Plan: 6 to add (RG/ACR/AKS/노드풀/AcrPull) |
| `infra/` 포맷 | `terraform fmt -check` | ✅ |
| 매니페스트 스키마 | `kubeconform -strict (k8s 1.30)` | ✅ 3/3 Valid |
| install.sh 문법 | `bash -n` | ✅ |

> 위는 클러스터/구독 없이 검증 가능한 범위다. 실제 노드 설치 동작은 아래 값을
> 채운 뒤 클러스터에서 확인해야 한다.

### 직접 채워야 하는 값 (placeholder)

| 위치 | 자리표시자 | 채울 값 |
| --- | --- | --- |
| `infra/terraform.tfvars` | `subscription_id` | 대상 구독 ID |
| `Dockerfile.installer` 빌드 | `PKG_SRC`, 패키지 파일 | 실제 `.deb`/`.tar`와 빌드 컨텍스트 경로 |
| `installer-daemonset.yaml` | `image: <acr>...`, `SERVICE_NAME`, `PKG_PATH` | 푸시한 이미지 태그·서비스명·패키지 경로 |
| `installer-configmap.yaml` | `install.sh` 내부 | 패키지별 설치/검증 로직 |
| `helm-values.example.yaml` | `<acr>`, `<vendor>`, `console.*` 등 | 벤더 차트/이미지/콘솔 정보 |

### 테스트 가능 범위

- **케이스 B(Installer-DaemonSet)**: 본 시나리오 산출물(Dockerfile + ConfigMap + DaemonSet)
  만으로 **엔드투엔드 테스트 가능**. 패키지만 준비하면 된다.
- **케이스 A(Helm)**: **벤더 차트/이미지가 필요**하다(일반화된 values 예시만 제공).
  벤더 자산 없이 "DaemonSet 롤아웃 메커니즘"만 스모크 테스트하려면
  [`debug-daemonset.yaml`](./manifests/debug-daemonset.yaml)을 대용으로 배포해
  노드당 1 Pod `Running`을 확인한다.

### 권장 검증 순서

1. `terraform apply` → `az aks get-credentials`
2. (케이스 B) 패키지 준비 → `Dockerfile.installer` 빌드/푸시 → 이미지 태그 치환
3. `kubectl apply` (configmap → daemonset) → Pod `Running` 확인
4. `kubectl debug node/<node>`로 호스트 `systemctl status <service>` = `active` 확인
5. 노드풀 스케일아웃 후 새 노드에서 자동 재설치(멱등) 확인

## 검증 상태 (Verification Status)

이 시나리오는 **로컬에서 검증 가능한 부분**과 **라이브 Azure/벤더 자산이 있어야 확정되는 부분**을 구분한다.

**로컬에서 검증됨 (이 repo에서 확인 완료):**

- `terraform init -backend=false` + `terraform validate` → 통과(provider 스키마 기준 인자 유효).
- 모든 매니페스트 YAML 문법 파싱 통과(`debug-daemonset`, `installer-configmap`, `installer-daemonset`, `helm-values.example`).
- 실제 식별자는 `*.tfvars.example`/`helm-values.example`로 일반화(하드코딩 없음).

**라이브 Azure/벤더 환경에서 직접 확인 필요 (실제 구현/테스트 시):**

- `terraform apply` 성공 및 AKS 노드풀 정상 기동(구독/쿼터 필요).
- **케이스 A(Helm)**: 벤더 차트/이미지가 있어야 동작(여기선 일반화 values 예시만 제공). 벤더 자산 없이 롤아웃 메커니즘만 보려면 `debug-daemonset.yaml`로 노드당 1 Pod `Running` 확인.
- **케이스 B(Installer-DaemonSet)**: `Dockerfile.installer` 빌드/푸시 후 호스트 설치(`systemctl status <service>` = active)·노드 스케일아웃 멱등성 확인.

> 요약: IaC·매니페스트 문법과 롤아웃 골격은 로컬 검증됨. 실제 벤더 솔루션 설치 동작은 벤더 자산 + 라이브 클러스터가 있어야 확정된다.
