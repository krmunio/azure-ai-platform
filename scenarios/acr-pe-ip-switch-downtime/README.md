# ACR PE IP-유형 변경 중단시간 측정 시나리오

ACR Private Endpoint(PE)의 IP 할당 방식을 **Static ↔ Dynamic** 으로 전환할 때,
data-plane 트래픽 관점에서 **얼마나 중단(downtime)되는지**를 부하 상태에서
측정·정량화하기 위한 시나리오다.

전환 절차 자체는
[`../acr-private-regional-replication/docs/GUIDE-PE-STATIC-TO-DYNAMIC.md`](../acr-private-regional-replication/docs/GUIDE-PE-STATIC-TO-DYNAMIC.md)
(방식 A — in-place ipconfig 재구성)를 따른다. 본 시나리오는 그 전환을 수행하는
동안 **가용성 프로브**를 돌려 중단 구간을 지표로 남긴다.

## 측정 원리

1. **프로브(`probe.sh`)**: 레지스트리 `https://<acr>.azurecr.io/v2/` 엔드포인트에
   인증 없이 일정 간격으로 HTTPS GET. `200/401/403`(연결 성공) = **up**,
   연결 실패/타임아웃/DNS 실패 = **down**. 자격증명 없이 **네트워크 경로
   가용성만** 격리해 측정한다. 결과를 CSV로 적재.
2. **전환(`switch-ip.sh`)**: `az network private-endpoint ip-config remove/add`로
   PE ipconfig를 Static↔Dynamic 재구성하면서 `switch_start`/`ipconfig_removed`/
   `ipconfig_added`/`switch_end` 타임스탬프를 이벤트 CSV로 기록.
3. **분석(`analyze.py`)**: 프로브 CSV에서 연속된 `down` 구간을 **앞뒤 `up`
   샘플로 경계 보정**해 중단 윈도우·총 중단시간·가용률을 계산하고, 이벤트 CSV와
   상관(전환 마커→첫 중단, 마커→복구)까지 산출.

> **중단시간 해상도 = 프로브 간격**. 더 정밀하게 보려면 `--interval`을 0.5초 등으로
> 낮춘다(부하/요청 수 증가 고려).

## 디렉터리 구성

```
scenarios/acr-pe-ip-switch-downtime/
  README.md
  scripts/
    probe.sh        # 가용성 프로브(연속) → CSV
    switch-ip.sh    # PE IP 유형 전환 + 이벤트 마커 기록 (방식 A)
    analyze.py      # 중단 윈도우/가용률/이벤트 상관 분석
  tests/
    test_analyze.py # analyze.py 단위 테스트(합성 CSV 기반)
```

## 사전 요구사항

- `az` CLI(로그인 + 대상 구독 선택), 대상 PE/RG/ipconfig 이름.
- 프로브를 **PE 사설 IP로 해석되는 네트워크 위치**(VNet 내 VM/도커, peering된
  네트워크 등)에서 실행해야 실제 private 경로를 측정한다.
- `curl`, `python3`(3.10+).
- (선택) 더 깊은 pull 부하를 원하면 `docker`로 별도 pull 루프를 병행.

## 실행 절차

별도 두 터미널(또는 백그라운드)에서 프로브를 먼저 띄우고, 전환을 수행한다.

```bash
cd scenarios/acr-pe-ip-switch-downtime/scripts

# 1) 프로브 시작 (예: 0.5초 간격, 600초 동안)
./probe.sh --registry <acr>.azurecr.io --interval 0.5 --duration 600 --out probe.csv &

# 2) 워밍업 후 IP 유형 전환 (Static -> Dynamic, in-place)
./switch-ip.sh --pe <pe명> --rg <rg명> --ipconfig <ipconfig명> \
  --to dynamic --events events.csv
#   (먼저 --dry-run으로 명령 확인 권장)

# 3) 프로브 종료(또는 --duration 만료 대기) 후 분석
python3 analyze.py probe.csv --events events.csv
python3 analyze.py probe.csv --events events.csv --json > report.json
```

출력 예시(중단 윈도우, 총 중단시간, 전환 마커→복구 시간 등)는 텍스트/JSON으로
제공된다.

## 테스트

`analyze.py`의 중단시간 계산 로직은 합성 CSV로 단위 검증한다(외부 의존성 없음).

```bash
cd scenarios/acr-pe-ip-switch-downtime
python3 -m unittest tests.test_analyze -v
# 또는: python3 tests/test_analyze.py
```

---

## 검증 상태 (Verification Status)

> AGENTS.md(scenarios 검증 규칙)에 따른 현재 시나리오의 검증 상태.

| 항목 | 상태 | 비고 |
|------|------|------|
| `analyze.py` 중단시간/가용률/이벤트 상관 로직 | ✅ 단위테스트 통과 | `tests/test_analyze.py` 7케이스(단일/다중/말단 중단, 상관, 입력검증) 통과 |
| `probe.sh` / `switch-ip.sh` 문법 | ✅ 확인 | `bash -n` 통과 |
| `analyze.py` CLI(text/JSON) 동작 | ✅ 확인 | 합성 CSV로 end-to-end 실행 확인 |
| `switch-ip.sh` 명령 구성 | ✅ 확인 | `--dry-run`으로 `az ... ip-config remove/add` 인자 구성 확인(가이드 방식 A와 일치) |
| `az network private-endpoint ip-config` 인자 실재 | ✅ 확인 | 로컬 `az` CLI `--help`로 확인 |
| 실제 ACR 대상 end-to-end(프로브+전환+중단 측정) | ⚠️ 미재현 | 실 ACR/PE 및 사설 네트워크 위치 필요. 비프로덕션에서 1회 재현 후 프로덕션 적용 권장 |
| 프로브 `/v2/` 가용성 신호의 data-plane 대표성 | ⚠️ 환경별 확인 | `/v2/`는 registry 엔드포인트 신호. layer pull까지 측정하려면 `docker pull` 루프 병행 권장 |

**권장**: 비프로덕션 ACR에서 방식 A 전환을 본 프로브와 함께 1회 측정해 중단
프로파일(보통 수 초 내외)을 확보한 뒤, 프로덕션 유지보수 창 계획에 반영한다.
