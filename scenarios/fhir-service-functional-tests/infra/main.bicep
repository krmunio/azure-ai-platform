// Azure Health Data Services: workspace + FHIR service (R4).
// 실제 리소스명은 하드코딩하지 않는다 — 모든 이름은 파라미터로 주입한다.
// 배포 범위: resource group.

@description('리소스 배포 위치')
param location string = resourceGroup().location

@description('Health Data Services 워크스페이스 이름 (영숫자, 3-24자, 전역 고유)')
@minLength(3)
@maxLength(24)
param workspaceName string

@description('FHIR service 이름 (워크스페이스 내 고유)')
@minLength(3)
@maxLength(24)
param fhirServiceName string

@description('FHIR 버전')
@allowed([
  'fhir-R4'
])
param fhirVersion string = 'fhir-R4'

resource workspace 'Microsoft.HealthcareApis/workspaces@2024-03-31' = {
  name: workspaceName
  location: location
}

resource fhir 'Microsoft.HealthcareApis/workspaces/fhirservices@2024-03-31' = {
  parent: workspace
  name: fhirServiceName
  location: location
  kind: fhirVersion
  // 시스템 할당 ID: $export 등에서 스토리지 접근에 사용.
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    authenticationConfiguration: {
      // 기본값: 현재 테넌트를 authority, 서비스 URL을 audience로 사용.
      authority: '${environment().authentication.loginEndpoint}${subscription().tenantId}'
      audience: 'https://${workspaceName}-${fhirServiceName}.fhir.azurehealthcareapis.com'
      smartProxyEnabled: false
    }
  }
}

@description('FHIR service 엔드포인트 URL — 시나리오 실행 시 FHIR_URL 로 사용')
output fhirUrl string = 'https://${workspaceName}-${fhirServiceName}.fhir.azurehealthcareapis.com'

@description('FHIR service 시스템 할당 principalId — 스토리지 롤 부여($export) 시 사용')
output fhirPrincipalId string = fhir.identity.principalId
