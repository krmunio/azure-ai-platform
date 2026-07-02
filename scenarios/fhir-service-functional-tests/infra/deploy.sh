#!/usr/bin/env bash
# Azure Health Data Services(FHIR service) 배포 + 실행 계정에 데이터 롤 부여.
# prefix는 실행 시 입력받아 모든 리소스명을 파생한다(실제 prefix 커밋 방지).
#
#   ./deploy.sh <prefix>        # 인자로 전달, 또는
#   ./deploy.sh                 # 프롬프트로 입력
#   LOCATION=eastus ./deploy.sh <prefix>
set -euo pipefail

PREFIX="${1:-}"
[ -n "$PREFIX" ] || read -rp "리소스 prefix 입력 (영문 소문자 3-11자): " PREFIX
[[ "$PREFIX" =~ ^[a-z][a-z0-9]{2,10}$ ]] || { echo "prefix는 소문자로 시작하는 영숫자 3-11자여야 합니다: '$PREFIX'"; exit 1; }

LOCATION="${LOCATION:-koreacentral}"
RG="rg-${PREFIX}-fhir"
WORKSPACE_NAME="${PREFIX}hdsws"     # 3-24자 영숫자, 전역 고유
FHIR_NAME="${PREFIX}fhir"           # 3-24자
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "prefix=$PREFIX  rg=$RG  workspace=$WORKSPACE_NAME  fhir=$FHIR_NAME  location=$LOCATION"

az group create -n "$RG" -l "$LOCATION" -o none

echo "[1/3] FHIR service 배포..."
FHIR_URL="$(az deployment group create \
  -g "$RG" -f "$HERE/main.bicep" \
  -p workspaceName="$WORKSPACE_NAME" -p fhirServiceName="$FHIR_NAME" -p location="$LOCATION" \
  --query 'properties.outputs.fhirUrl.value' -o tsv)"
echo "  FHIR_URL=$FHIR_URL"

echo "[2/3] 실행 계정에 FHIR Data Contributor 롤 부여..."
SUB="$(az account show --query id -o tsv)"
FHIR_ID="/subscriptions/${SUB}/resourceGroups/${RG}/providers/Microsoft.HealthcareApis/workspaces/${WORKSPACE_NAME}/fhirservices/${FHIR_NAME}"
ME="$(az ad signed-in-user show --query id -o tsv)"
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "FHIR Data Contributor" --scope "$FHIR_ID" -o none || \
  echo "  (롤 부여 실패/권한 부족 — 관리자에게 요청 필요)"

echo "[3/3] 완료. 시나리오 실행:"
echo "  export FHIR_URL=\"$FHIR_URL\""
echo "  ../tests/run-scenarios.sh"
# ponytail: $export용 스토리지+롤 부여는 미포함. export 검증 필요 시 별도 구성.
