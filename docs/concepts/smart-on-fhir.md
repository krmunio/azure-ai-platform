# SMART on FHIR

의료 앱이 **EHR/FHIR 서버에 안전하게 붙기 위한 표준**. 핵심은
**OAuth 2.0(인가) + OpenID Connect(인증) + FHIR(데이터 모델)** 조합.
"한 번 만든 앱을 여러 병원 시스템에 그대로 연동"하는 게 목표
(SMART = _Substitutable Medical Applications, Reusable Technologies_).

## 왜 필요한가

FHIR는 데이터 표현만 표준화한다. **"누가·무슨 권한으로 접근하나"**는 정의하지 않는다.
SMART on FHIR가 그 **인증·인가·앱 실행 컨텍스트**를 표준화해, EHR마다 커스텀 연동을
다시 짜는 비용을 없앤다.

## 구성 요소

| 요소 | 역할 |
| --- | --- |
| **OAuth 2.0** | 앱에 스코프 기반 액세스 토큰 발급(인가) |
| **OpenID Connect** | 사용자 신원 확인(`id_token`) |
| **FHIR API** | 표준 리소스(Patient, Observation 등) 읽기/쓰기 |
| **Scopes** | 접근 범위. `patient/*.read`, `user/Observation.write` 등 |
| **Launch context** | 앱 실행 시 환자·진료 컨텍스트 전달(`launch/patient`) |

## 두 가지 Launch 흐름

- **EHR Launch**: EHR 화면 안에서 앱 실행 → EHR가 환자 컨텍스트를 넘겨줌.
- **Standalone Launch**: 앱을 단독 실행 → 사용자가 로그인 후 환자 선택.

```
앱 → (authorize) → EHR 인가서버 → 로그인·동의 → code
   → (token) → access_token(+scope, patient) → FHIR API 호출
```

## 스코프 형식

`{context}/{resource}.{action}` — 예:

- `patient/Observation.read` : 현재 환자의 관찰 리소스 읽기
- `user/*.read` : 로그인 사용자 권한 범위 전체 읽기
- `openid fhirUser` : 신원·사용자 FHIR 리소스

## Azure 구현 매핑

| 필요 기능 | Azure |
| --- | --- |
| FHIR API 서버 | Azure Health Data Services — FHIR service |
| 인가·인증(OAuth2/OIDC) | Microsoft Entra ID |
| 앱 게이트웨이/정책 | API Management |

> Azure FHIR service는 SMART on FHIR 프록시/스코프 매핑을 지원한다.
> → FHIR 배포·검증: [`scenarios/fhir-service-functional-tests`](../../scenarios/fhir-service-functional-tests/)

## 관련 개념 구분

- **FHIR**: 데이터 모델·API 표준.
- **SMART on FHIR**: 그 위의 **앱 인증·인가·실행 컨텍스트** 표준.
- **CDS Hooks**: 진료 흐름 중 실시간 임상의사결정지원 트리거(SMART와 자주 함께 씀).
