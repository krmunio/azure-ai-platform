# Azure FHIR Service Functional Validation Scenario

*Read this in [Korean](./README.md).*

Before adopting Azure Health Data Services **FHIR service** as the foundation of a healthcare system,
this scenario reproducibly validates that the core FHIR features behave to spec and captures the outcome
as a **result report**.

- Run: [`tests/run-scenarios.sh`](./tests/run-scenarios.sh) — curl-based; runs 8 scenarios sequentially and produces a PASS/FAIL log
- Infra: [`infra/`](./infra/) — Bicep + `deploy.sh` that deploy the FHIR service
- Test data: [`data/`](./data/) — synthetic resources only (no real patients/PII)
- Bulk data: [`tests/load-synthea.sh`](./tests/load-synthea.sh) — load Synthea synthetic Bundles
- Report: [`REPORT-TEMPLATE.md`](./REPORT-TEMPLATE.md) — a template to fill in with run logs for submission
- Run result: [`REPORT.md`](./REPORT.md) — result report of a real instance run (10 PASS / 0 FAIL / 1 SKIP)

> **Resource-name rule**: Never put real resource names or subscription IDs anywhere in scripts/docs.
> Inject the FHIR endpoint only via the `FHIR_URL` environment variable.

## Validation scenarios

| # | Scenario | FHIR feature validated | Expected result |
|---|---------|------------------------|-----------------|
| 1 | Register Patient → read | Resource CRUD, server-assigned ID | `201` created, `200` read |
| 2 | Clinical-record transaction Bundle (Encounter+Observation+Condition) | Inter-resource references, `transaction` Bundle atomicity | `200` (`transaction-response`) |
| 3 | Search/filter | `_id`, `subject`, `_include` search parameters | `200` (`searchset` Bundle) |
| 4 | Versioning/history & optimistic concurrency | `PUT`+`If-Match` (ETag), `_history` | `200`, version incremented |
| 5 | Profile validation | `$validate` → `OperationOutcome` | `OperationOutcome(error)` on violation |
| 6 | Bulk export | Bulk Data `$export` async kick-off | `202` + `Content-Location` |
| 7 | Graph read | `Patient/{id}/$everything` | `200` (Bundle of related resources) |
| 8 | Cleanup | Resource `DELETE` | `200` |

## Prerequisites

- An **Azure FHIR service** instance (under an Azure Health Data Services workspace)
- An authenticated **Azure CLI** (`az login`) — the running account needs a FHIR data role
  (`FHIR Data Contributor` or higher; for the export test, `$export` permission/storage connection)
- `curl`, `python3` (for JSON validation, optional)

> If you don't have a FHIR service, deploy one with [`infra/`](./infra/) and target it (see "Infrastructure deployment" below).

## Infrastructure deployment (`infra/`)

If you don't have a FHIR service instance, deploy one with Bicep. It creates an Azure Health Data Services
**workspace + FHIR service (R4)** and grants the running account the `FHIR Data Contributor` role.

```bash
cd scenarios/fhir-service-functional-tests/infra
az login

./deploy.sh <prefix>            # pass prefix as an argument (or run without args to be prompted)
# LOCATION=eastus ./deploy.sh <prefix>   # to change the location
```

- The **prefix is provided at runtime** and derives all resource names — `rg-<prefix>-fhir`,
  `<prefix>hdsws` (workspace), `<prefix>fhir` (FHIR service). Do not commit a real prefix to the repo.
- prefix format: alphanumeric, starts with a lowercase letter, 3–11 characters.
- The FHIR service has a **system-assigned identity**, and its `principalId` is output
  (used when granting a storage role for `$export`).
- After deployment, export the emitted `FHIR_URL` to run the scenarios.
- The storage account/role for `$export` are out of scope. Configure them separately if needed.

## Run steps

```bash
cd scenarios/fhir-service-functional-tests

# 1) Set the target FHIR endpoint (never commit the real value)
export FHIR_URL="https://{workspace-name}-{fhir-name}.fhir.azurehealthcareapis.com"

# 2) Log in (once)
az login

# 3) Run — output goes to the console + fhir-test-<timestamp>.log
./tests/run-scenarios.sh
```

Exit code `0` = all PASS. Attach the generated `.log` file to the report.

### Extending test data — Synthea (optional)

**Synthea** (Synthetic Patient Population Simulator, an MITRE open-source project) simulates the **life story
of synthetic patients** (birth → disease → care → prescription → death) based on statistical/disease models
rather than real people, generating realistic healthcare data. Because it contains **no PII**, it can be used
freely for development, demos, and load testing.

- It supports FHIR (R4, etc.) output → generates **transaction Bundles** containing Patient/Encounter/Observation/Condition, etc. under `output/fhir/*.json`.
- POSTing the generated Bundles to a FHIR server loads them as-is (obtaining data for bulk search / `$export` validation).

```bash
# 1) Generate synthetic data (requires Java 11+)
git clone https://github.com/synthetichealth/synthea && cd synthea
./run_synthea -p 100          # generate FHIR Bundles for 100 patients → output/fhir/

# 2) Load into Azure FHIR service (endpoint via env var only)
export FHIR_URL="https://{workspace-name}-{fhir-name}.fhir.azurehealthcareapis.com"
/path/to/scenarios/fhir-service-functional-tests/tests/load-synthea.sh ./output/fhir
```

> **Never use real patient data** — use only Synthea synthetic data.
> Bulk loading can also be done via `$import` (async bulk ingest) instead of POSTing transaction Bundles.

## Validation status

- [x] Bash syntax check (`bash -n`) passed — `run-scenarios.sh`, `load-synthea.sh`, `deploy.sh`
- [x] Test-data JSON validity passed
- [x] Bicep compile (`az bicep build`) passed — `infra/main.bicep`
- [x] End-to-end smoke test against a mock FHIR server passed — validated req/check/ETag/token plumbing
- [x] **Real Azure FHIR service deployed and run** — deployed with `deploy.sh <prefix>`, scenarios **10 PASS / 0 FAIL / 1 SKIP**
- [ ] **Synthea bulk load run** — requires Java+Synthea and a deployed FHIR service (not yet done)

> Verified on a real instance: Azure FHIR returns `204` on `DELETE`; `$export` requires an export storage
> account to be configured and returns `400 "not enabled"` when it is not (the script treats this as SKIP).
