# APIM as AI Gateway — Feature & Benefit Validation Scenario

*[Korean version](./README.md) of this document.*

This scenario deploys and validates the core claim of `AI Gateway.pdf`:
**"An AI Gateway is really Azure API Management (APIM)."** It places APIM in front of
Azure OpenAI (Foundry), applies the representative policies the deck highlights
(token limit, load balancing + circuit breaker, semantic caching) plus Keyless auth and
observability, then **measures each benefit**.

- Design: [`DESIGN.md`](./DESIGN.md)
- Plan: [`PLAN.md`](./PLAN.md)
- Infra: [`infra/`](./infra/) (Terraform, single flat state)
- Tests: [`tests/run-scenarios.sh`](./tests/run-scenarios.sh)

## Feature → benefit mapping

| Feature | policy / resource | Validated benefit |
| --- | --- | --- |
| Keyless (Managed Identity) | APIM MI + `Cognitive Services OpenAI User` role + `authentication-managed-identity` | secure backend auth without keys |
| Token limit (TPM) | `azure-openai-token-limit` | 429 throttling on overuse → cost/abuse control |
| Load balancing + circuit breaker | azapi backend Pool + circuit breaker | availability under load/failure → resiliency |
| Semantic caching (optional) | `azure-openai-semantic-cache-*` + Managed Redis | reuse similar prompts → lower latency/cost |
| Token metrics / logging | App Insights + `azure-openai-emit-token-metric` | per-consumer observability |

## Resources deployed

| Resource | Condition | Notes |
| --- | --- | --- |
| Resource Group | always | `koreacentral` default |
| Azure OpenAI (primary) + chat deployment | always | `gpt-4o-mini` default |
| Azure OpenAI (secondary) + chat deployment | `enable_load_balancing=true` | secondary region |
| API Management (StandardV2) + System MI | always | the AI gateway |
| Role assignment (OpenAI User) | always (+secondary) | keyless |
| azapi backend + Pool + circuit breaker | Pool when LB, else single | `Microsoft.ApiManagement/service/backends` |
| APIM API / operation / policy | always | `path=openai`, catch-all `POST /{*path}` |
| App Insights + logger + diagnostic | `enable_observability=true` | token metrics/logging |
| Managed Redis(RediSearch) + APIM cache + embeddings deployment | `enable_semantic_cache=true` | semantic cache |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- Authenticated Azure CLI (`az login`)
- Quota to deploy Azure OpenAI and the chosen model (e.g. `gpt-4o-mini`)
- Rights to create APIM v2 and (optionally) Redis Enterprise

> **Note**: APIM v2 provisioning takes tens of minutes; Redis Enterprise also takes a while.

## Deploy

```bash
cd scenarios/apim-ai-gateway/infra
cp terraform.tfvars.example terraform.tfvars   # adjust as needed
terraform init
terraform plan
terraform apply
```

Key outputs:

```bash
terraform output apim_gateway_url        # https://<apim>.azure-api.net
terraform output openai_proxy_base_url   # <gateway>/openai
terraform output chat_deployment_name
terraform output openai_api_version
```

## Validate

You need an APIM subscription key (portal **APIM > Subscriptions**). Pass real values via
environment variables only — never commit them.

```bash
cd scenarios/apim-ai-gateway/tests

export APIM_GATEWAY_URL="$(terraform -chdir=../infra output -raw apim_gateway_url)"
export APIM_SUBSCRIPTION_KEY="<apim-subscription-key>"
export CHAT_DEPLOYMENT="$(terraform -chdir=../infra output -raw chat_deployment_name)"
export OPENAI_API_VERSION="$(terraform -chdir=../infra output -raw openai_api_version)"

./run-scenarios.sh
```

Checks:

1. **Keyless connectivity** — call Azure OpenAI via MI (no keys) → 200
2. **Token limit** — repeated calls hit 429 + `x-ratelimit-remaining-tokens` header
3. **Load balancing / resiliency** — success rate holds under load (Pool + circuit breaker)
4. **Semantic caching** (optional) — 2nd similar prompt is much faster

> To make examples 2 & 3 obvious, lower `tokens_per_minute` (e.g. 200) and `chat_capacity`
> (e.g. 1) to trigger throttling/failover. Semantic caching requires `enable_semantic_cache=true`.

## See the benefits (optional)

- **Token metrics**: App Insights > Metrics > namespace `ai-gateway` token counts per consumer dimension.
- **Prompt/response logging**: the APIM diagnostic logs requests to App Insights.
- **Circuit breaker**: a backend returning repeated 429/5xx is excluded for `tripDuration` and traffic
  routes to the other Pool member.

## Cleanup

```bash
cd scenarios/apim-ai-gateway/infra
terraform destroy
```

## Convention notes

- Do **not** hardcode real resource names, subscription/tenant IDs, or keys in docs/code/scripts
  (use `name_prefix`+random suffix+variables; tests read env vars).
- Never commit to `main` — this scenario is developed on branch `scenario/apim-ai-gateway`.
