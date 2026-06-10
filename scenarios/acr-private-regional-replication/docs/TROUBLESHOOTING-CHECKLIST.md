# Private ACR Geo-replication 생성 실패 진단 체크리스트

> 증상: Private Endpoint 기반 ACR에 신규 리전(UK South) replica 생성 시 실패
> 최종 확정 원인: **기존 PE에 신규 data endpoint를 자동 확장하는 단계 실패**
> (`BadRequest: Failed to replicate private endpoint`)

본 문서는 위 증상에 대해 실제로 수행한 진단 절차와, 동일·유사 사례 재발 시
순서대로 점검할 체크리스트를 정리합니다. 명령의 `devacrrb2krc`, `dev-rg-rb2-krc`,
`dev-pvl-rb2-krc-acr` 등은 대상 환경 값으로 치환하여 사용합니다.

---

## 0. 핵심 결론 요약

- [x] private + geo-replication 구성 **자체는 정상 동작**(테스트 환경에서 재현 성공).
- [x] **차단성 원인(정책 Deny / RBAC 403 / Deny Assignment / 위치 제한)은 배제** — Activity Log에서 `write`가 `Accepted → Creating → Failed`로 진행(어드미션 통과).
- [x] **CMK 암호화 배제** (`encryption.status = disabled`).
- [x] **PE 서브넷 IP 고갈 배제** (`/26`, 24/59 사용 → 35 여유). replica 추가는 PE에 ipconfig 1개만 더함.
- [x] **존 중복성(zoneRedundancy) 단독 원인 배제** — `--zone-redundancy Disabled`로도 실패(에러만 더 구체화됨).
- [x] **최종 원인 확정**: 기존 PE(`dev-pvl-rb2-krc-acr`)에 신규 `*.uksouth.data.azurecr.io`
      엔드포인트(ipconfig + 사설 IP + A레코드)를 자동 추가하는 "PE replicate" 단계 실패.

---

## 1. 에러 1차 분류 (Activity Log)

- [ ] correlationId로 중첩(child) 이벤트의 실제 상태 흐름 확인
  ```bash
  az monitor activity-log list --correlation-id <correlationId> \
    --query "[].{op:operationName.value, status:status.value, sub:subStatus.value, msg:properties.statusMessage}" -o jsonc
  ```
  - 판정: `write`가 **Accepted/Created → Creating → Failed** 이면
    → 어드미션 통과 = **정책/RBAC/Deny Assignment/위치제한 원인 아님**(백엔드 프로비저닝 실패).
  - 주의: Activity Log 보존 **90일** — 실패 직후 수집해야 함.

---

## 2. 레지스트리 구성 확인 (차단·구성 요인 배제)

- [ ] 암호화/아이덴티티/존중복/네트워크/SKU 일괄 확인
  ```bash
  az acr show -n devacrrb2krc \
    --query "{encryption:encryption, identity:identity, zoneRedundancy:zoneRedundancy, publicNetworkAccess:publicNetworkAccess, networkRuleBypass:networkRuleBypassOptions, sku:sku.name}" -o jsonc
  ```
  - [ ] `encryption.status` = `disabled` → CMK 원인 배제 (enabled면 Key Vault 방화벽/권한 추가 점검).
  - [ ] `sku` = `Premium` (Private Link/Geo-replication 전제).
  - [ ] `publicNetworkAccess`, `networkRuleBypassOptions` 값 기록(후속 가설용).
  - [ ] `zoneRedundancy` 값 기록(홈 리전 기준).

---

## 3. 리전/존 지원 여부 확인 (존 중복 가설 점검)

- [ ] 대상 리전 AZ 지원 여부 (구독 노출 기준)
  ```bash
  SUB=$(az account show --query id -o tsv)
  az rest --method get \
    --url "https://management.azure.com/subscriptions/$SUB/locations?api-version=2022-12-01" \
    --query "value[?name=='uksouth'].availabilityZoneMappings" -o jsonc
  ```
  - 판정: `logicalZone` 1/2/3 이 모두 나오면 **3 AZ 사용 가능** → "AZ 미지원" 배제.
- [ ] (참고) ACR은 리소스 공급자에 `zoneMappings`를 채우지 않음 → 위 리전 AZ API가 표준 확인법.
- [ ] 실제 존 중복 할당 capacity는 **사전 조회 불가** → 생성 시도(4단계) 또는 지원티켓으로만 확인.

---

## 4. 단일 변수 분리 테스트 (CLI 직접 생성 — 에러 상세 확보)

> 포털의 Replications 지도(map) 추가는 존 중복 토글을 노출하지 않으므로 CLI 사용.
> Terraform은 상세 사유를 삼키므로 **원인 규명 단계에서는 CLI 직접 생성** 권장.

- [ ] 존 중복 끄고 생성(단일 변수 분리)
  ```bash
  az acr replication create -r devacrrb2krc -l uksouth --zone-redundancy Disabled -o jsonc
  ```
  - 성공 → 존 중복 프로비저닝(capacity)이 원인.
  - 실패하되 **에러가 구체화**되면(예: `Failed to replicate private endpoint`) → 5단계로.
- [ ] (옵션) 다른 리전으로 생성하여 리전 고유 문제인지 분리
  ```bash
  az acr replication create -r devacrrb2krc -l japaneast -o jsonc
  ```
- [ ] 상세 로그 캡처
  ```bash
  az acr replication create -r devacrrb2krc -l uksouth --zone-redundancy Disabled --debug 2>&1 | tail -50
  ```

---

## 5. Private Endpoint 복제 실패 정밀 진단 (최종 원인 영역)

> 에러 `Failed to replicate private endpoint` = 기존 PE에 신규 리전 data endpoint를
> 끼워넣는 단계 실패. 아래로 PE 상태/구성/차단요인을 점검.

- [ ] PE 연결 상태 점검 (Approved/Succeeded 여부)
  ```bash
  az acr private-endpoint-connection list -r devacrrb2krc \
    --query "[].{name:name, status:privateLinkServiceConnectionState.status, provState:provisioningState, desc:privateLinkServiceConnectionState.description}" -o table
  ```
  - 비정상(Pending/Rejected/Disconnected/Failed) 발견 시 → 해당 연결 정리/재승인 후 재시도.
- [ ] PE의 현재 FQDN ↔ IP 매핑 확인 (data endpoint 개수)
  ```bash
  PEID=$(az acr private-endpoint-connection list -r devacrrb2krc --query "[0].privateEndpoint.id" -o tsv)
  az network private-endpoint show --ids "$PEID" \
    --query "customDnsConfigs[].{fqdn:fqdn, ips:ipAddresses}" -o jsonc
  ```
  - 기대: `azurecr.io` + `<home>.data.azurecr.io` 만 존재(신규 `*.uksouth.data` 누락 = 추가 실패 흔적).
- [ ] **리소스 잠금(Lock)** 으로 NIC/PE 수정 차단 여부
  ```bash
  az lock list -g dev-rg-rb2-krc -o table
  # 중앙 DNS Zone이 위치한 RG/구독에 대해서도 동일 확인
  ```
- [ ] **서브넷 PE 네트워크 정책** 으로 ipconfig 추가 차단 여부
  ```bash
  SUBNET_ID="/subscriptions/<sub>/resourceGroups/dev-rg-rb2-krc/providers/Microsoft.Network/virtualNetworks/dev-vnet-rb2-krc/subnets/dev-subnet-rb2-krc-pvl"
  az network vnet subnet show --ids "$SUBNET_ID" \
    --query "{pe:privateEndpointNetworkPolicies, pls:privateLinkServiceNetworkPolicies}" -o jsonc
  ```
- [ ] **중앙(cross-subscription) DNS Zone Group 자동 갱신 권한** 확인
  - PE의 DNS Zone Group이 다른 구독(예: `prd-sub-rb-krc`)의 `privatelink.azurecr.io`를 가리키는 경우,
    신규 A레코드(`*.uksouth.data`) 자동 등록을 위해 해당 구독/zone에 대한
    **Private DNS Zone Contributor** 권한이 필요.

---

## 6. 해결책 (근본 원인 기반)

### 6-A. 차단요인(Lock/정책)이 발견된 경우 — 정상 경로 복구
- [ ] Lock 제거 또는 서브넷 PE 정책 조정 후 replica 재생성(정상 경로로 성공 가능).

### 6-B. 차단요인이 없는데도 PE 복제 실패 — PE 재생성으로 우회
> PE 자동 확장 경로가 깨졌으니, replica를 먼저 만든 뒤 PE를 재생성.
> **PE 삭제 구간 동안 private pull 일시 중단 → 반드시 유지보수 창에서 진행.**
- [ ] 1) 기존 PE 삭제
  ```bash
  az network private-endpoint delete -n dev-pvl-rb2-krc-acr -g dev-rg-rb2-krc
  ```
- [ ] 2) replica 추가(복제할 PE가 없으므로 성공)
  ```bash
  az acr replication create -r devacrrb2krc -l uksouth --zone-redundancy Disabled
  ```
- [ ] 3) PE 재생성(동일 서브넷/중앙 Zone Group) → registry + 모든 리전 data endpoint를 한 번에 노출,
      DNS Zone Group이 전체 A레코드 자동 등록.
- [ ] 4) 검증: PE의 `customDnsConfigs`에 `*.uksouth.data` 포함 확인.

### 6-C. 비파괴적 해결 / 정확한 RP 사유 필요 — 지원 티켓
- [ ] Azure 지원 티켓에 다음 첨부:
  - 에러 메시지 `Failed to replicate private endpoint`
  - correlationId
  - PE 구성(중앙 cross-subscription DNS Zone Group 사용 사실)

---

## 7. 사후 검증 (생성 성공 후)

- [ ] replica 상태 Ready/Succeeded
  ```bash
  az acr replication list -r devacrrb2krc \
    --query "[].{replica:name, location:location, zoneRedundancy:zoneRedundancy, status:provisioningState}" -o table
  ```
- [ ] PE에 신규 data endpoint A레코드 등록 확인(`*.uksouth.data → 사설 IP`).
- [ ] 대상 리전 워크로드가 **로컬 data endpoint로 직접 연결**되도록 PE/DNS 구성 점검
      (그렇지 않으면 사본은 있으나 "리전 근접 pull" 이점은 제한 — 본 시나리오 보고서 5장 참조).

---

## 참고

- ACR Geo-replication: https://learn.microsoft.com/azure/container-registry/container-registry-geo-replication
- ACR Private Link: https://learn.microsoft.com/azure/container-registry/container-registry-private-link
- 본 시나리오 상세: `../README.md`, `../DESIGN.md`, 보고서 `ACR_Private_GeoReplication_Report.docx`
