# ACR Private Endpoint: Static IP → Dynamic IP 전환 가이드

> 대상: Private Endpoint(PE)가 **Static(수동) IP**로 구성되어 있어
> geo-replication 신규 리전 추가 시 `Failed to replicate private endpoint`로
> 실패하는 ACR. (배경·근본 원인은 [TROUBLESHOOTING-CHECKLIST.md](./TROUBLESHOOTING-CHECKLIST.md) 9장 참조)
>
> 명령의 `{acr명}`, `{rg명}`, `{pe명}` 등은 대상 환경 값으로 치환하여 사용합니다.

---

## 0. 왜 전환하는가

ACR은 **레지스트리당 PE 1개**가 registry endpoint + 모든 리전의 data
endpoint(`*.<region>.data.azurecr.io`)를 한 NIC에서 커버한다. 신규 리전
replica를 추가하면 ACR이 **기존 PE NIC에 ipconfig 1개와 사설 IP를 자동
확장**하는데, PE가 **Static IP**면 신규 ipconfig용 IP를 자동 할당하지 못해
PE 구성이 실패하고 replica가 `Failed`가 된다.

→ PE를 **Dynamic IP**로 전환하면 서브넷에서 가용 IP를 자동 할당받아 ipconfig
자동 확장이 정상 동작한다.

> **참고**: Azure는 기존 PE ipconfig의 할당 방식(Static ⇄ Dynamic)을
> *즉시(on-the-fly)* 바꿀 수 없다. 두 방식 모두 ipconfig를 **제거 후 재추가**
> 하거나 PE 자체를 재생성해야 하며, 그 구간 동안 **private pull이 일시 중단**된다.
> 따라서 **반드시 유지보수 창에서 진행**한다.

---

## 1. 사전 점검 (전환 전 필수)

### 1-1. 현재 PE가 Static IP인지 확인
```bash
az network nic show \
  --ids $(az network private-endpoint show -n {pe명} -g {rg명} \
            --query "networkInterfaces[0].id" -o tsv) \
  --query "ipConfigurations[].{Name:name, PrivateIPAddress:privateIPAddress, Alloc:privateIPAllocationMethod}" \
  -o table
```
- `Alloc` 컬럼이 **`Static`** 이면 본 가이드 대상이다. `Dynamic`이면 전환 불필요.

### 1-2. Static IP가 *반드시* 필요한 요구사항 확인
- 고정 IP 기반 방화벽 규칙, 외부 시스템의 IP allowlist 등 **PE의 IP를 고정값으로
  의존하는 구성**이 있는지 점검한다.
- 필수 요구가 **있다면** Dynamic 전환 시 IP가 바뀌어 해당 규칙이 깨질 수 있다.
  이 경우 geo-replication과 Static PE는 현재 양립이 어려우므로
  [TROUBLESHOOTING-CHECKLIST.md](./TROUBLESHOOTING-CHECKLIST.md) 6-C(지원 티켓)로
  RP 측 공식 대안을 확인한다.
- 필수 요구가 **없다면** 아래 전환을 진행한다.

### 1-3. 현재 구성 백업(롤백 대비)
```bash
# 현재 PE/NIC 구성 스냅샷 보관 (Static IP 값·서브넷·연결 상태 기록)
az network private-endpoint show -n {pe명} -g {rg명} -o jsonc > pe-backup.json
az network nic show \
  --ids $(az network private-endpoint show -n {pe명} -g {rg명} \
            --query "networkInterfaces[0].id" -o tsv) -o jsonc > nic-backup.json
```
- 기록 권장 항목: 기존 **Static IP 값**, 서브넷 ID, `groupIds`, ipconfig별
  `name`/`memberName`, DNS Zone Group 연결 여부.

---

## 2. 두 방식 비교

| 항목 | **방식 A — in-place ipconfig 재구성** (권장) | **방식 B — PE 삭제·재생성** |
|------|---------------------------------------------|------------------------------|
| 작업 내용 | PE의 ipconfig만 remove → add(IP 미지정) | PE 리소스 전체 삭제 후 재생성 |
| 중단 범위 | ipconfig 재구성 구간의 **짧은 private pull 중단** | PE 삭제~재승인까지 **더 긴 중단** |
| PE 리소스 보존 | ✅ 유지 | ❌ 새 리소스로 교체 |
| 연결 승인(approval) | ✅ 보존(재승인 불필요) | ❌ 재승인 필요(수동/자동 승인 흐름 재수행) |
| DNS Zone Group | ✅ 유지 | ❌ 재구성 필요(중앙 cross-subscription이면 권한 주의) |
| 작업량/복잡도 | 낮음 | 높음 |
| 롤백 | ipconfig를 원래 Static IP로 재추가 | 백업 기준 PE 전체 재구성 |

> 가능하면 **방식 A**를 사용한다. 연결 승인·DNS Zone Group을 보존하므로 부수
> 작업과 중단이 작다. 방식 A가 환경 제약(권한/정책)으로 막히거나 PE 구성이
> 비정상일 때 **방식 B**로 폴백한다.

---

## 3. 방식 A — in-place ipconfig 재구성 (권장)

> 핵심: 기존 PE를 유지한 채 **Static ipconfig를 제거하고 IP를 지정하지 않고
> 다시 추가**하면 Dynamic으로 할당된다.

### 3-1. 현재 ipconfig 이름·멤버 확인
```bash
az network private-endpoint ip-config list \
  --endpoint-name {pe명} -g {rg명} \
  --query "[].{name:name, groupId:groupId, member:memberName, ip:privateIpAddress}" -o table
```
- ACR PE의 `groupId`는 보통 **`registry`**, `memberName`은 **`registry`**(및 리전별
  data 멤버)다. 위 출력의 실제 값으로 아래 명령을 치환한다.

### 3-2. Static ipconfig 제거
```bash
az network private-endpoint ip-config remove \
  --endpoint-name {pe명} -g {rg명} \
  --name {ipconfig명}
```

### 3-3. Dynamic으로 재추가 (`--private-ip-address` 미지정 = Dynamic)
```bash
az network private-endpoint ip-config add \
  --endpoint-name {pe명} -g {rg명} \
  --name {ipconfig명} \
  --group-id registry \
  --member-name registry
```
- `--private-ip-address`를 **지정하지 않으면** Azure가 서브넷에서 가용 IP를
  자동 할당(Dynamic)한다.
- ipconfig가 여러 개(리전별 data 멤버 등)면 각 멤버에 대해 3-2~3-3을 반복한다.

### 3-4. 5장(사후 검증)으로 진행.

---

## 4. 방식 B — PE 삭제·재생성 (대안)

> 방식 A가 불가하거나 PE 구성이 비정상일 때 사용. PE 삭제 구간 동안 private
> pull이 중단되고, **연결 재승인 + DNS Zone Group 재구성**이 필요하다.

- 1) 기존(Static) PE 삭제
  ```bash
  az network private-endpoint delete -n {pe명} -g {rg명}
  ```
  > 중앙(cross-subscription) DNS Zone Group을 사용하는 경우, 삭제 시
  > `privateDnsZoneGroup` 정리 단계에서 중앙 DNS RG의 Lock(`CanNotDelete`)에
  > 막힐 수 있다 — [TROUBLESHOOTING-CHECKLIST.md](./TROUBLESHOOTING-CHECKLIST.md)
  > 8장 참조.
- 2) PE를 **Dynamic IP**로 재생성(동일 서브넷, 동일 중앙 DNS Zone Group).
     `--private-ip-address`를 지정하지 않으면 Dynamic으로 생성된다.
- 3) 연결 승인 상태 확인(수동 승인 흐름이면 승인 수행).
- 4) 5장(사후 검증)으로 진행.

---

## 5. 사후 검증

### 5-1. 할당 방식이 Dynamic인지 확인
```bash
az network nic show \
  --ids $(az network private-endpoint show -n {pe명} -g {rg명} \
            --query "networkInterfaces[0].id" -o tsv) \
  --query "ipConfigurations[].{Name:name, PrivateIPAddress:privateIPAddress, Alloc:privateIPAllocationMethod}" \
  -o table
```
- 모든 ipconfig의 `Alloc`이 **`Dynamic`** 이어야 한다.

### 5-2. PE 연결 상태 확인
```bash
az network private-endpoint show -n {pe명} -g {rg명} \
  --query "privateLinkServiceConnections[].{name:name, status:privateLinkServiceConnectionState.status}" -o table
```
- `status`가 **`Approved`** 여야 한다.

### 5-3. geo-replication 재시도 및 확인
```bash
az acr replication create -r {acr명} -l {리전} -o jsonc
az acr replication list -r {acr명} \
  --query "[].{loc:location, prov:provisioningState}" -o table
```
- 신규 리전 replica가 **`Succeeded`** 여야 한다.

### 5-4. DNS A레코드/customDnsConfigs 확인
```bash
az network private-endpoint show -n {pe명} -g {rg명} \
  --query "customDnsConfigs[].{fqdn:fqdn, ips:ipAddresses}" -o jsonc
```
- `*.<리전>.data.azurecr.io`가 PE 사설 IP로 매핑되어 있어야 한다.

---

## 6. 롤백

- **방식 A**: 5장에서 문제가 확인되면, 추가했던 ipconfig를 다시 제거하고
  백업(`nic-backup.json`)의 **원래 Static IP**로 재추가한다.
  ```bash
  az network private-endpoint ip-config remove \
    --endpoint-name {pe명} -g {rg명} --name {ipconfig명}
  az network private-endpoint ip-config add \
    --endpoint-name {pe명} -g {rg명} --name {ipconfig명} \
    --group-id registry --member-name registry \
    --private-ip-address {백업한_static_ip}
  ```
- **방식 B**: 백업(`pe-backup.json`)을 기준으로 PE를 원래 Static 구성으로
  재생성하고 연결 승인·DNS Zone Group을 복구한다.

---

## 7. 관련 시나리오

전환 시 **실제 중단 시간(다운타임)을 트래픽 부하 상태에서 측정**하려면 별도
시나리오를 참조한다(있을 경우): IP 유형 변경 중 `docker pull` 트래픽을 지속
발생시키며 실패율·중단 구간을 지표로 수집한다.

---

## 검증 상태 (Verification Status)

> AGENTS.md(scenarios 검증 규칙)에 따른 현재 가이드의 검증 상태.

| 항목 | 상태 | 비고 |
|------|------|------|
| `az network private-endpoint ip-config` (add/remove/list) 명령·인자 실재 | ✅ 확인 | 로컬 `az` CLI `--help`로 인자(`--endpoint-name`, `--group-id`, `--member-name`, `--private-ip-address`) 확인 |
| Static→Dynamic을 즉시(on-the-fly) 변경 불가, remove/add 필요 | ✅ 확인 | Azure CLI/PE 동작상 ipconfig 재구성 필요 |
| **방식 B(삭제·재생성)로 Dynamic 전환 시 geo-replication 성공** | ✅ 재현됨 | [TROUBLESHOOTING-CHECKLIST.md](./TROUBLESHOOTING-CHECKLIST.md) 9장(테스트 환경 재현) |
| **방식 A(in-place ipconfig 재구성)** 실 환경 end-to-end 재현 | ⚠️ 미재현 | 명령 자체는 검증됨. ACR PE에서 ipconfig remove/add 후 연결·DNS 정상 여부는 대상 환경에서 유지보수 창에 검증 필요 |
| ACR PE의 `group-id`/`member-name` 값 | ⚠️ 환경별 확인 | 일반적으로 `registry`이나, 3-1 명령으로 실제 값 확인 후 치환 |

**적용 전 권장 절차**: 비프로덕션/테스트 ACR에서 방식 A를 1회 재현해 5장 검증
항목을 통과시킨 뒤 프로덕션 유지보수 창에 적용한다.
