#!/usr/bin/env bash
# Synthea가 생성한 FHIR transaction Bundle(output/fhir/*.json)을 Azure FHIR service에 적재한다.
# 실제 리소스명은 넣지 않는다. 엔드포인트는 FHIR_URL 환경변수로만 받는다.
#
#   export FHIR_URL="https://{workspace명}-{fhir명}.fhir.azurehealthcareapis.com"
#   ./load-synthea.sh /path/to/synthea/output/fhir
set -uo pipefail

: "${FHIR_URL:?FHIR_URL 환경변수를 설정하세요}"
FHIR_URL="${FHIR_URL%/}"
DIR="${1:?사용법: load-synthea.sh <synthea output/fhir 디렉터리>}"
[ -d "$DIR" ] || { echo "디렉터리 없음: $DIR"; exit 1; }

TOKEN="$(az account get-access-token --resource "$FHIR_URL" --query accessToken -o tsv)" \
  || { echo "토큰 발급 실패: az login 후 재시도"; exit 1; }

OK=0; ERR=0
shopt -s nullglob
# Synthea 환자 번들은 Organization/Practitioner 를 참조하므로, 참조 대상인
# hospitalInformation / practitionerInformation 번들을 먼저 적재한다(참조 무결성).
info=("$DIR"/hospitalInformation*.json "$DIR"/practitionerInformation*.json)
patients=()
for f in "$DIR"/*.json; do
  case "$(basename "$f")" in
    hospitalInformation*|practitionerInformation*) ;;
    *) patients+=("$f") ;;
  esac
done
files=("${info[@]}" "${patients[@]}")
[ ${#files[@]} -gt 0 ] || { echo "$DIR 에 *.json Bundle이 없습니다"; exit 1; }
echo "적재 대상: ${#files[@]} 개 Bundle (참조 대상 ${#info[@]} 선적재) → $FHIR_URL"

for f in "${files[@]}"; do
  # Synthea Bundle은 type=transaction 이므로 base URL에 POST한다.
  code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$FHIR_URL" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/fhir+json" \
            --data-binary "@$f")"
  if [ "$code" = "200" ] || [ "$code" = "201" ]; then
    OK=$((OK+1)); printf '  OK  [%s] %s\n' "$code" "$(basename "$f")"
  else
    ERR=$((ERR+1)); printf '  ERR [%s] %s\n' "$code" "$(basename "$f")"
  fi
done

echo "== 적재 완료: OK=$OK ERR=$ERR =="
# ponytail: 순차 POST. 수천 건 이상이면 az healthcareapis fhir 의 $import(비동기 대량반입)로 전환.
[ "$ERR" -eq 0 ]
