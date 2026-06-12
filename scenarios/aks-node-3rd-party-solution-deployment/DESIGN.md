# 설계: AKS Worker Node 3rd Party 솔루션 배포 시나리오

## 배경

AKS는 **관리형(managed) 노드**를 제공한다. 노드 VM은 AKS가 라이프사이클(업그레이드,
스케일, 재이미지)을 관리하며, 운영자는 SSH/노드 직접 접근이 기본적으로 제한된다.
반면 금융·보안 규제 환경에서는 워커 노드에 **3rd party 솔루션**(EDR/보안 에이전트,
스토리지 SDC, DLP 등)을 배포해야 하는 요구가 흔하다.

이때 솔루션은 두 부류로 나뉜다.

1. **컨테이너만으로 동작하는 솔루션** — 에이전트/probe가 Pod 안에서 실행되며,
   필요한 호스트 자원은 `hostPath`/`hostNetwork`/`hostPID` 등 권한으로 접근한다.
2. **호스트 OS 레벨 설치가 필요한 솔루션** — `systemd` 서비스로 상주하거나 커널 모듈을
   적재해야 하는 경우. 패키지(`.deb`/`.tar`)를 **호스트 파일시스템에 설치**해야 한다.

이 차이에 따라 배포 전략이 달라진다. 본 시나리오는 두 전략을 **케이스로 분리**하여
정리하고, 재현 가능한 매니페스트와 최소 AKS 인프라를 제공한다.

## 핵심 제약

- **노드 풀 재이미지/스케일아웃 시 재설치 필요**: 관리형 노드는 업그레이드·스케일아웃 시
  새 OS 디스크로 교체될 수 있다. 호스트 레벨 설치는 **DaemonSet으로 멱등(idempotent)하게
  재실행**되도록 설계해야 한다(노드가 새로 뜨면 자동 재설치).
- **privileged 권한 필요**: 호스트 네임스페이스 진입(`nsenter`/`chroot`)과 커널 모듈
  적재는 privileged 컨테이너 + hostPID/hostPath가 필요하다.
- **설치 파일 반입 경로**: 폐쇄망에서는 패키지를 이미지에 번들하거나 사설 레지스트리(ACR)로
  반입한다. 외부 인터넷 다운로드를 가정하지 않는다.

## 케이스 분류

| 케이스 | 적용 상황 | 메커니즘 |
| --- | --- | --- |
| **A. Helm Chart 기반 DaemonSet** | 솔루션이 **컨테이너만으로** 동작 | Helm으로 privileged DaemonSet 배포. 노드당 1 Pod가 상주하며 probe/agent를 컨테이너 내에서 실행. 중앙 관리 콘솔과 자동 연결. |
| **B. Installer-DaemonSet 기반** | **호스트 OS 레벨 설치**가 필요 | DaemonSet의 init/main 컨테이너가 install script를 `nsenter`/`chroot`로 호스트에서 **headless 실행**. 패키지를 호스트에 설치하고 `systemd` 서비스로 등록. |

두 케이스 모두 노드 전체에 빠짐없이 적용하기 위해 **DaemonSet**을 공통 토대로 사용한다.
차이는 "컨테이너 안에서 도는가(A)" vs "호스트에 설치하는가(B)"다.

## 공통 운영 절차 (문서 섹션)

사용자 요청 항목을 다음 순서로 다룬다.

1. **구성이 필요한 환경 / 사전 요구사항** — AKS, 노드풀 OS(Ubuntu), privileged 허용,
   설치 파일 반입 경로(ACR/이미지 번들).
2. **Debug node 띄우는 방법** — `kubectl debug node/<node>`(호스트 마운트 `/host`)와
   privileged debug DaemonSet 두 방식. 진단/수동 검증용.
3. **호스트에 파일 설치 방법** — `chroot /host` 또는 `nsenter`로 호스트 컨텍스트 진입 후
   패키지 설치, `systemd` 등록·기동 검증.
4. **설치 파일을 노드로 복사** — (a) 컨테이너 이미지에 번들, (b) ConfigMap(스크립트),
   (c) `hostPath` 경유, (d) `kubectl cp` + debug pod. 장단점 비교.
5. **Helm 배포** — values/DaemonSet 구성, `helm install`, `kubectl rollout` 검증.

## 산출물

```
scenarios/aks-node-3rd-party-solution-deployment/
  DESIGN.md          # 본 문서
  README.md          # 케이스/절차 + 재현 가이드
  manifests/
    debug-daemonset.yaml          # 케이스 공통: privileged debug DaemonSet
    installer-daemonset.yaml      # 케이스 B: Installer-DaemonSet + 호스트 설치
    installer-configmap.yaml      # 케이스 B: headless install script
    Dockerfile.installer          # 케이스 B: 패키지 번들 installer 이미지 빌드
    helm-values.example.yaml      # 케이스 A: Helm values 예시
  infra/             # 최소 AKS(노드풀) + ACR Terraform (단일 state)
    providers.tf variables.tf main.tf outputs.tf
    terraform.tfvars.example .gitignore
```

## 비범위 (YAGNI)

- 특정 벤더 제품명/라이선스 구성은 다루지 않는다(일반화된 패턴만).
- 멀티 클러스터/허브-스포크 네트워크는 다루지 않는다(단일 AKS+ACR).
- 설치 파일 자체(바이너리)는 포함하지 않는다(반입 방법만 기술).
