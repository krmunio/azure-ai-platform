# PoC Implementation Plan (Tumor Board Agentic AI)

> Goal: Narrow **part** of the Stanford case into a minimal PoC that can actually be deployed and validated on Azure.
> Not the full 5-agent production system — start from **a single use case** with clear ROI.

> Korean version: [POC-PLAN.md](./POC-PLAN.md)

## 0. PoC Scope (deliberately reduced)

- **In**: Orchestrator + 2 agents (**timeline generation**, **clinical-trial matching**) + RAG (AI Search) + HITL approval.
- **Out (deferred to phase 2)**: imaging analysis (DICOM), multi-region DR, APIM semantic cache, Purview data lineage.
- **Data**: Start with **synthetic FHIR samples** (e.g., Synthea) instead of real PHI. Real PHI only after passing the compliance gate.

> Why reduced: Standing up 5 agents + DICOM + multi-region all at once produces an unverifiable demo. First prove the pipeline runs with two agents.

## 1. Phased Plan

| Phase | Content | Deliverable / Done criteria |
|---|---|---|
| **P0 · Foundation** | RG, Hub-Spoke VNet, Private DNS, Log Analytics, App Insights, Key Vault, Managed Identity | `terraform apply` succeeds, `terraform validate` passes |
| **P1 · Data** | Storage (ZRS), Cosmos (session), Health Data Services (FHIR), load synthetic FHIR | FHIR `$validate`/CRUD succeeds (reuse existing `scenarios/fhir-service-functional-tests`) |
| **P2 · Knowledge/RAG** | AI Search index (guidelines & clinical-trial docs), hybrid search | Sample query returns top-k grounding |
| **P3 · Agents** | AI Foundry Project, model deployment (GPT family), Orchestrator + 2 agents in Agent Service | Orchestrator calls both agents and returns a synthesized response |
| **P4 · App/HITL** | Container Apps web app + API, clinician approval gate, citation display | One demo scenario end-to-end, source citation on each recommendation |
| **P5 · Observability/Eval** | Foundry Tracing + App Insights, accuracy/grounding evaluation script | Per-agent traces verified, one evaluation report |

## 2. Validation Gates (required before declaring done)

- [ ] `terraform validate` + `plan` error-free (`infra/`)
- [ ] All PaaS behind Private Endpoints, public access blocked
- [ ] Zero hardcoded secrets (Managed Identity + Key Vault), zero hardcoded real resource names/IDs (AGENTS.md rule)
- [ ] GPT-family calls use `max_completion_tokens`, token limit 800+ (avoid empty responses)
- [ ] No final recommendation is surfaced to clinicians without HITL approval
- [ ] Every recommendation carries a source citation (hallucination mitigation)

## 3. Risks & Prerequisites

- **Compliance**: Before real PHI, execute a BAA, minimize PHI, and pin the region (e.g., koreacentral). The PoC sidesteps this with synthetic data.
- **Provider coverage**: AI Foundry **Agent Service** has thin Terraform azurerm support → configure that part via `azapi` or post-deployment script/portal (note it in `infra/` comments).
- **Cost/time**: APIM creation is slow (tens of minutes) and costly → excluded from the PoC; add after P4 if needed.
- **Model tiering**: Route simple matching to small models and only synthesis/timeline to large models to manage token cost.

## 4. Next Steps (after the PoC)

Imaging-analysis agent (DICOM) → switch to real PHI → APIM AI Gateway → Purview lineage → multi-region DR → bias/drift monitoring.

---

*Once this PoC is validated, it has grown into a deployable, self-contained unit in `case-studies/` →
at that point, consider graduating it to `scenarios/tumor-board-agentic-poc/`.*
