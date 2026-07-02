#!/usr/bin/env bash
# Azure FHIR service 기능 검증 시나리오 러너.
# 실제 리소스명은 넣지 않는다. FHIR 엔드포인트는 환경변수로만 받는다.
#
#   export FHIR_URL="https://{workspace명}-{fhir명}.fhir.azurehealthcareapis.com"
#   ./run-scenarios.sh
#
# 인증: Azure CLI(az login) 자격증명으로 FHIR audience 토큰을 발급한다.
set -uo pipefail

: "${FHIR_URL:?FHIR_URL 환경변수를 설정하세요 (예: https://<ws>-<fhir>.fhir.azurehealthcareapis.com)}"
FHIR_URL="${FHIR_URL%/}"
DATA_DIR="$(cd "$(dirname "$0")/../data" && pwd)"
LOG="${LOG:-./fhir-test-$(date +%Y%m%d-%H%M%S).log}"

TOKEN="$(az account get-access-token --resource "$FHIR_URL" --query accessToken -o tsv)" || {
  echo "토큰 발급 실패: az login 후 재시도"; exit 1; }

PASS=0; FAIL=0; SKIP=0
log() { echo "$@" | tee -a "$LOG"; }

# req METHOD PATH EXPECTED_CODE [BODY_FILE|-] [EXTRA_HEADER...]
# 마지막 응답 본문은 $BODY, 상태코드는 $CODE, ETag는 $ETAG 에 담긴다.
req() {
  local method="$1" path="$2" expect="$3" body="${4:--}"; shift 4 || shift $#
  local hdrs=(-H "Authorization: Bearer $TOKEN" -H "Accept: application/fhir+json")
  [ "$body" != "-" ] && hdrs+=(-H "Content-Type: application/fhir+json" --data-binary "@$body")
  local h; for h in "$@"; do hdrs+=(-H "$h"); done
  local tmp hdrfile; tmp="$(mktemp)"; hdrfile="$(mktemp)"
  CODE="$(curl -sS -o "$tmp" -D "$hdrfile" -w '%{http_code}' -X "$method" "${hdrs[@]}" "$FHIR_URL$path")"
  BODY="$(cat "$tmp")"; ETAG="$(tr -d '\r' <"$hdrfile" | awk 'tolower($1)=="etag:"{print $2}')"
  rm -f "$tmp" "$hdrfile"
}

check() { # NAME EXPECTED
  if [ "$CODE" = "$2" ]; then log "  PASS [$CODE] $1"; PASS=$((PASS+1));
  else log "  FAIL [got $CODE, want $2] $1"; log "    body: $(echo "$BODY" | head -c 300)"; FAIL=$((FAIL+1)); fi
}

log "== Azure FHIR 기능 검증 =="
log "endpoint: $FHIR_URL"
log "started:  $(date -Is)"; log ""

# --- 1. Patient 등록 → 조회 (CRUD) ---
log "[1] Patient 등록/조회"
req POST /Patient 201 "$DATA_DIR/patient.json"
check "POST Patient 생성" 201
PID="$(echo "$BODY" | grep -o '"id":[[:space:]]*"[^"]*"' | head -1 | cut -d'"' -f4)"
log "  patient id: ${PID:-<none>}"
PETAG="$ETAG"
req GET "/Patient/$PID" 200
check "GET Patient/{id} 조회" 200

# --- 2. 진료기록 트랜잭션 Bundle (참조 무결성) ---
log "[2] Encounter+Observation+Condition 트랜잭션 Bundle"
sed "s|PATIENT_ID|$PID|g" "$DATA_DIR/clinical-bundle.json" > /tmp/fhir-bundle.json
req POST / 200 /tmp/fhir-bundle.json
check "transaction Bundle 처리" 200

# --- 3. 검색 파라미터 ---
log "[3] 검색"
req GET "/Patient?_id=$PID" 200
check "search Patient?_id" 200
req GET "/Observation?subject=Patient/$PID&_include=Observation:subject" 200
check "search Observation + _include" 200

# --- 4. 버전/이력, 낙관적 동시성(ETag) ---
log "[4] 버전/이력"
sed "s|PATIENT_ID|$PID|g" "$DATA_DIR/patient-update.json" > /tmp/fhir-patient-upd.json
req PUT "/Patient/$PID" 200 /tmp/fhir-patient-upd.json "If-Match: $PETAG"
check "PUT + If-Match (낙관적 동시성)" 200
req GET "/Patient/$PID/_history" 200
check "GET _history" 200

# --- 5. 프로파일 검증 ($validate → OperationOutcome) ---
log "[5] \$validate (규격 위반 감지)"
req POST "/Patient/\$validate" 200 "$DATA_DIR/patient-invalid.json"
# $validate 는 위반 시에도 200 + OperationOutcome(issue severity=error) 를 반환
if echo "$BODY" | grep -qi 'OperationOutcome'; then
  log "  PASS [$CODE] \$validate가 OperationOutcome 반환"; PASS=$((PASS+1))
else
  log "  FAIL \$validate 응답에 OperationOutcome 없음"; FAIL=$((FAIL+1)); fi

# --- 6. Bulk export ($export, 202 kick-off) ---
log "[6] Bulk \$export"
req GET "/\$export" 202 - "Prefer: respond-async"
if [ "$CODE" = "202" ]; then
  log "  PASS [202] \$export 비동기 수락"; PASS=$((PASS+1))
elif [ "$CODE" = "400" ] && echo "$BODY" | grep -qi 'not enabled'; then
  log "  SKIP [400] \$export 미활성(스토리지 미구성) — 범위 밖"; SKIP=$((SKIP+1))
else
  log "  FAIL [got $CODE, want 202] \$export"; log "    body: $(echo "$BODY" | head -c 300)"; FAIL=$((FAIL+1)); fi

# --- 7. Patient \$everything (그래프 조회) ---
log "[7] Patient/{id}/\$everything"
req GET "/Patient/$PID/\$everything" 200
check "\$everything" 200

# --- 8. 정리 (DELETE) ---
log "[8] 정리"
req DELETE "/Patient/$PID" 204
check "DELETE Patient" 204

log ""; log "== 결과: PASS=$PASS FAIL=$FAIL SKIP=$SKIP =="
log "finished: $(date -Is)  log: $LOG"
[ "$FAIL" -eq 0 ]
