# ACR Private Endpoint: Dynamic ⇄ Static IP 전환 (단일 업데이트 방식)

> 대상: ACR Private Endpoint(PE)의 IP 할당 방식을 **Dynamic ↔ Static** 으로
> 전환하려는 경우. ACR PE는 `registry` 멤버 외에 **리전별 data endpoint
> 멤버**(`registry_data_<region>`)를 함께 가지므로, 멤버 단위로 하나씩 바꾸는
> 방식(`ip-config add/remove`)은 실패한다. **모든 멤버를 단일 업데이트로 동시에**
> 설정해야 한다.
>
> 명령의 `{pe명}`, `{rg명}` 등은 대상 환경 값으로 치환하여 사용한다.
> 배경·근본 원인은 [TROUBLESHOOTING-CHECKLIST.md](./TROUBLESHOOTING-CHECKLIST.md) 9장 참조.

---

## 0. 왜 `ip-config add/remove`로는 안 되는가

ACR PE는 멤버 단위로 IP를 검증한다. `az network private-endpoint ip-config add/remove`
는 **멤버 하나씩 PUT**을 보내는데, ACR PE는 일부 멤버만 Static이고 나머지는
Dynamic인 **중간 상태를 거부**한다. 그래서 다음 두 에러가 번갈아 발생한다.

| 에러 코드 | 의미 |
|-----------|------|
| `PrivateEndpointIpConfigurationMissingMemberNamesRequiredByFps` | 명시한 Static ipconfig가 일부 멤버를 누락 → **모든 멤버**를 명시해야 함 |
| `PrivateEndpointStaticIpMustMatchDynamicIpMapping` | Static IP가 현재 Dynamic 매핑과 불일치 → in-place 전환은 **현재 IP를 그대로** 써야 함 |

→ 해결: PE의 `ipConfigurations` 배열을 **단 한 번의 업데이트**로 통째로 설정하는
`az network private-endpoint update --set ipConfigurations=...` 를 사용한다.

> **중요(in-place 제약)**: in-place로 Dynamic→Static 전환 시 Static IP는 **현재
> Dynamic이 잡고 있는 IP와 정확히 일치**해야 한다. *다른* IP로 바꾸려면 in-place로는
> 불가능하며 **PE 삭제 후 재생성**이 필요하다(원하는 IP로 새로 생성).

---

## 1. 전환 전 확인 (현재 멤버·IP·할당 방식)

```bash
RG={rg명} ; PE={pe명}

az network nic show \
  --ids $(az network private-endpoint show -n $PE -g $RG \
            --query "networkInterfaces[0].id" -o tsv) \
  --query "ipConfigurations[].{member:privateLinkConnectionProperties.requiredMemberName, ip:privateIPAddress, alloc:privateIPAllocationMethod}" \
  -o table
```

출력 예시(단일 리전 koreacentral):

```
Member                      Ip          Alloc
--------------------------  ----------  -------
registry_data_koreacentral  {data_ip}   Dynamic
registry                    {reg_ip}    Dynamic
```

- `member` / `ip` 값을 그대로 받아 적는다(아래 전환 명령에 사용).
- `alloc` 이 현재 어떤 상태인지 확인한다.
- 리전 replica가 여러 개면 `registry_data_<region>` 멤버가 그만큼 더 나온다 —
  **전부** 전환 명령에 포함해야 한다.

---

## 2. Dynamic → Static

모든 멤버의 ipconfig를 **현재 IP 그대로** 명시해 단일 업데이트로 설정한다.

```bash
RG={rg명} ; PE={pe명}

az network private-endpoint update -n $PE -g $RG --set ipConfigurations='[
  {"name":"acr-registry","properties":{"groupId":"registry","memberName":"registry","privateIPAddress":"{reg_ip}"}},
  {"name":"acr-data-koreacentral","properties":{"groupId":"registry","memberName":"registry_data_koreacentral","privateIPAddress":"{data_ip}"}}
]'
```

- `{reg_ip}` / `{data_ip}` 는 1장에서 확인한 **현재 Dynamic IP**와 동일해야 한다
  (다르면 `MustMatchDynamicIpMapping`).
- 멤버가 더 있으면 같은 형식의 객체를 배열에 추가한다(누락 시 `MissingMemberNames...`).
- `name` 은 ipconfig의 표시 이름으로 임의 지정 가능(멤버당 유일).

---

## 3. Static → Dynamic

명시적 ipconfig 배열을 **비우면** 모든 멤버가 자동(Dynamic) 할당으로 돌아간다.

```bash
RG={rg명} ; PE={pe명}

az network private-endpoint update -n $PE -g $RG --set ipConfigurations='[]'
```

> Dynamic 복귀 시 IP는 서브넷에서 자동 재할당되므로 **기존 Static IP와 달라질 수 있다.**
> 고정 IP가 필요한 방화벽 규칙 등이 있으면 영향에 주의한다.

---

## 4. 전환 후 검증

1장과 동일한 명령으로 `alloc` 컬럼을 확인한다.

```bash
RG={rg명} ; PE={pe명}

az network nic show \
  --ids $(az network private-endpoint show -n $PE -g $RG \
            --query "networkInterfaces[0].id" -o tsv) \
  --query "ipConfigurations[].{member:privateLinkConnectionProperties.requiredMemberName, ip:privateIPAddress, alloc:privateIPAllocationMethod}" \
  -o table
```

- Dynamic→Static: 모든 멤버 `alloc` 이 **`Static`**, IP가 의도한 값.
- Static→Dynamic: 모든 멤버 `alloc` 이 **`Dynamic`**.

PE에 명시적으로 정의된 ipconfig만 따로 보려면:

```bash
az network private-endpoint show -n $PE -g $RG \
  --query "ipConfigurations[].{name:name, member:memberName, ip:privateIpAddress}" -o table
```

> 참고: PE가 **완전 Dynamic**이면 이 목록은 비어 있다(`[]`). 자동 할당 ipconfig는
> `ipConfigurations`(명시적 정의)에는 나타나지 않고 NIC 레벨에서만 보이기 때문이다.

---

## 5. 주의 사항

- ipconfig 재구성 구간 동안 **private pull이 일시 중단**될 수 있으므로 **유지보수
  창에서 진행**한다.
- 단일 업데이트라 멤버별 add/remove 보다 중간 실패 위험이 작지만, 업데이트 자체는
  PE를 재구성하므로 트래픽 영향을 고려한다.
- geo-replication 신규 리전 추가는 PE가 **Dynamic** 일 때만 ipconfig 자동 확장이
  정상 동작한다(Static이면 `Failed to replicate private endpoint`) —
  [TROUBLESHOOTING-CHECKLIST.md](./TROUBLESHOOTING-CHECKLIST.md) 9장.

---

## 검증 상태 (Verification Status)

> AGENTS.md(scenarios 검증 규칙)에 따른 현재 가이드의 검증 상태.

| 항목 | 상태 | 비고 |
|------|------|------|
| `az network private-endpoint update --set ipConfigurations=[...]` 로 Dynamic→Static 전환 | ✅ 재현됨 | 단일 리전 ACR PE(registry + registry_data_koreacentral)에서 두 멤버 모두 `Static` 전환 확인 |
| `--set ipConfigurations='[]'` 로 Static→Dynamic 복귀 | ✅ 재현됨 | 두 멤버 모두 `Dynamic` 복귀 확인 |
| `ip-config add/remove` 증분 방식은 multi-member PE에서 실패 | ✅ 재현됨 | `MissingMemberNamesRequiredByFps` / `MustMatchDynamicIpMapping` 에러 발생 |
| in-place Static 전환 시 현재 Dynamic IP와 일치 강제 | ✅ 재현됨 | 다른 IP 지정 시 `MustMatchDynamicIpMapping` |
| 다수 리전(2개 이상 replica) PE에서의 동일 절차 | ⚠️ 미재현 | 원리상 동일(멤버 객체 추가)하나 다리전 환경 end-to-end 재현 필요 |
| az CLI 버전 | ℹ️ | `2.85.0` 에서 확인 |
