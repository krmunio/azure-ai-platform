#!/usr/bin/env bash
# Azure Health Data Services(FHIR service) 배포 + 실행 계정에 데이터 롤 부여.
# 실제 리소스명은 커밋하지 말 것 — 환경변수/파라미터로만 주입한다.
#
#   export RG="{rg명}" LOCATION="koreacentral"
#   export WORKSPACE_NAME="{workspace명}" FHIR_NAME="{fhir명}"
#   ./deploy.sh
set -euo pipefail

: "${RG:?RG(리소스그룹명) 환경변수 필요}"
: "${WORKSPACE_NAME:?WORKSPACE_NAME 환경변수 필요}"
: "${FHIR_NAME:?FHIR_NAME 환경변수 필요}"
LOCATION="${LOCATION:-koreacentral}"
HERE="$(cd "$(dirname "$0")" && pwd)"

az group create -n "$RG" -l "$LOCATION" -o none

echo "[1/3] FHIR service 배포..."
FHIR_URL="$(az deployment group create \
  -g "$RG" -f "$HERE/main.bicep" \
  -p workspaceName="$WORKSPACE_NAME" -p fhirServiceName="$FHIR_NAME" -p location="$LOCATION" \
  --query 'properties.outputs.fhirUrl.value' -o tsv)"
echo "  FHIR_URL=$FHIR_URL"

echo "[2/3] 실행 계정에 FHIR Data Contributor 롤 부여..."
FHIR_ID="$(az resource show \
  --resource-type Microsoft.HealthcareApis/workspaces/fhirservices \
  -g "$RG" --name "$WORKSPACE_NAME/$FHIR_NAME" --query id -o tsv)"
ME="$(az ad signed-in-user show --query id -o tsv)"
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "FHIR Data Contributor" --scope "$FHIR_ID" -o none || \
  echo "  (롤 부여 실패/권한 부족 — 관리자에게 요청 필요)"

echo "[3/3] 완료. 시나리오 실행:"
echo "  export FHIR_URL=\"$FHIR_URL\""
echo "  ./tests/run-scenarios.sh"
# ponytail: $export용 스토리지+롤 부여는 미포함. export 검증 필요 시 별도 구성.
