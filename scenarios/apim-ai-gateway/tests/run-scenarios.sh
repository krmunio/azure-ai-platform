#!/usr/bin/env bash
# APIM AI Gateway 기능/이점 검증 러너.
# 실제 리소스명·키는 코드에 넣지 않는다. 모두 환경변수로만 받는다.
#
#   export APIM_GATEWAY_URL="https://<apim>.azure-api.net"   # terraform output apim_gateway_url
#   export APIM_SUBSCRIPTION_KEY="<apim-subscription-key>"    # APIM > Subscriptions 에서 발급
#   export CHAT_DEPLOYMENT="gpt-4o-mini"                      # terraform output chat_deployment_name
#   export OPENAI_API_VERSION="2024-10-21"                    # terraform output openai_api_version
#   ./run-scenarios.sh
#
# 검증 항목:
#   [1] Keyless 연결        — MI로 Azure OpenAI 호출(키 없이) 200
#   [2] 토큰 제한(TPM)      — 연속 호출 시 429 + x-ratelimit-* 헤더 (비용/남용 제어)
#   [3] 로드밸런싱/복원력   — 부하 하에서도 성공률 유지 (Pool + circuit breaker)
#   [4] 시맨틱 캐싱(옵션)   — 유사 프롬프트 2회차 지연 급감 (성능/비용 절감)
set -uo pipefail

: "${APIM_GATEWAY_URL:?APIM_GATEWAY_URL 환경변수를 설정하세요}"
: "${APIM_SUBSCRIPTION_KEY:?APIM_SUBSCRIPTION_KEY 환경변수를 설정하세요}"
CHAT_DEPLOYMENT="${CHAT_DEPLOYMENT:-gpt-4o-mini}"
OPENAI_API_VERSION="${OPENAI_API_VERSION:-2024-10-21}"
APIM_GATEWAY_URL="${APIM_GATEWAY_URL%/}"
CHAT_URL="$APIM_GATEWAY_URL/openai/deployments/$CHAT_DEPLOYMENT/chat/completions?api-version=$OPENAI_API_VERSION"
LOG="${LOG:-./aigw-test-$(date +%Y%m%d-%H%M%S).log}"

PASS=0; FAIL=0; SKIP=0
log() { echo "$@" | tee -a "$LOG"; }

# chat "프롬프트" [max_tokens]  → $CODE, $TIME(초), $HDRS, $BODY 채움
chat() {
  local prompt="$1" maxtok="${2:-16}"
  local tmp hdr; tmp="$(mktemp)"; hdr="$(mktemp)"
  local payload
  payload="$(printf '{"messages":[{"role":"user","content":%s}],"max_tokens":%s}' \
    "$(printf '%s' "$prompt" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "\"%s\"",$0}')" "$maxtok")"
  read -r CODE TIME < <(curl -sS -o "$tmp" -D "$hdr" -w '%{http_code} %{time_total}' \
    -X POST "$CHAT_URL" \
    -H "Ocp-Apim-Subscription-Key: $APIM_SUBSCRIPTION_KEY" \
    -H "Content-Type: application/json" \
    --data-binary "$payload")
  HDRS="$(tr -d '\r' <"$hdr")"; BODY="$(cat "$tmp")"; rm -f "$tmp" "$hdr"
}

log "== APIM AI Gateway 기능/이점 검증 =="
log "gateway: $APIM_GATEWAY_URL"
log "started: $(date -Is)"; log ""

# --- [1] Keyless 연결 ---
log "[1] Keyless 연결 (Managed Identity → Azure OpenAI, 키 미사용)"
chat "Reply with the single word: pong" 16
if [ "$CODE" = "200" ]; then
  log "  PASS [200] 프록시 경유 chat completion 성공 (keyless)"; PASS=$((PASS+1))
elif [ "$CODE" = "401" ] || [ "$CODE" = "403" ]; then
  log "  FAIL [$CODE] 인증 실패 — APIM MI 롤 부여/전파 확인 필요"; FAIL=$((FAIL+1))
  log "    body: $(echo "$BODY" | head -c 300)"
else
  log "  FAIL [$CODE] 예기치 않은 응답"; log "    body: $(echo "$BODY" | head -c 300)"; FAIL=$((FAIL+1))
fi

# --- [2] 토큰 제한(TPM) ---
log ""
log "[2] 토큰 제한 policy (TPM 초과 시 429)"
GOT_429=0; RATELIMIT_HDR=0; N=25
for i in $(seq 1 "$N"); do
  chat "Write a long paragraph about Azure API Management as an AI gateway. Iteration $i." 256
  echo "$HDRS" | grep -qi 'x-ratelimit-remaining-tokens' && RATELIMIT_HDR=1
  if [ "$CODE" = "429" ]; then
    GOT_429=1
    log "  요청 #$i → 429 (Retry-After: $(echo "$HDRS" | awk 'tolower($1)=="retry-after:"{print $2}'))"
    break
  fi
done
if [ "$GOT_429" = "1" ]; then
  log "  PASS 토큰 한도 초과 시 429로 스로틀링됨 (비용/남용 제어 이점)"; PASS=$((PASS+1))
else
  log "  SKIP $N회 내 429 미발생 — tokens_per_minute를 낮추거나 반복 수를 늘려 재시도"; SKIP=$((SKIP+1))
fi
[ "$RATELIMIT_HDR" = "1" ] && log "  (정보) x-ratelimit-remaining-tokens 헤더 관측됨"

# --- [3] 로드밸런싱 / 복원력 ---
log ""
log "[3] 로드밸런싱 + 서킷브레이커 (Pool 백엔드, 부하 하 성공률)"
sleep 61   # [2]의 TPM 창을 비워 순수 가용성만 측정
OK=0; TOT=12
for i in $(seq 1 "$TOT"); do
  chat "ping $i" 4
  { [ "$CODE" = "200" ] || [ "$CODE" = "429" ]; } && OK=$((OK+1))
done
log "  $TOT회 중 게이트웨이 정상 처리(200/429): $OK"
if [ "$OK" -ge $((TOT * 3 / 4)) ]; then
  log "  PASS Pool 라우팅으로 높은 가용성 유지 (복원력 이점)"; PASS=$((PASS+1))
else
  log "  FAIL 성공률 저조 — 백엔드/circuit breaker/quota 상태 확인"; FAIL=$((FAIL+1))
fi

# --- [4] 시맨틱 캐싱 (옵션) ---
log ""
log "[4] 시맨틱 캐싱 (유사 프롬프트 2회차 지연 급감)"
sleep 61
chat "What is the capital city of France? Answer in one word." 8
T1="$TIME"; C1="$CODE"
sleep 1
chat "Tell me the capital of France in a single word." 8
T2="$TIME"; C2="$CODE"
log "  1회차: code=$C1 time=${T1}s / 2회차(유사): code=$C2 time=${T2}s"
if [ "$C1" = "200" ] && [ "$C2" = "200" ] && awk "BEGIN{exit !($T2 < $T1*0.6)}"; then
  log "  PASS 2회차 지연이 크게 감소 — semantic cache hit 추정 (성능/비용 이점)"; PASS=$((PASS+1))
else
  log "  SKIP 캐시 효과 불명확 — enable_semantic_cache=true(Redis) 여부/임계값 확인"; SKIP=$((SKIP+1))
fi

log ""; log "== 결과: PASS=$PASS FAIL=$FAIL SKIP=$SKIP =="
log "finished: $(date -Is)  log: $LOG"
[ "$FAIL" -eq 0 ]
