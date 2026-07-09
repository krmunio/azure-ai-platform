# azure-ai-platform

*Read this in [Korean](./README.md).*

A **scenario-based** repository for deploying and validating Azure resources.
Each scenario behaves like a small, self-contained repo with its own infrastructure code and documentation.

## Directory convention

```
scenarios/
  <resource-scenario-keyword>/      # kebab-case, e.g. acr-private-regional-replication
    DESIGN.md                       # design document
    PLAN.md                         # implementation plan
    README.md                       # scenario overview + deploy/reproduce steps
    infra/                          # standalone IaC (Terraform)
      providers.tf
      variables.tf
      main.tf
      outputs.tf
      terraform.tfvars.example
      .gitignore
```

- The top level holds per-scenario folders under `scenarios/`.
- A scenario folder does not depend on other scenarios (independently deployable/removable).
- IaC code lives under the scenario's `infra/` folder.

## Scenario index

| Scenario | Description |
| --- | --- |
| [`acr-private-regional-replication`](./scenarios/acr-private-regional-replication/) | Reproduce the error when adding regional replication to a private ACR (deploys the environment up to just before replica configuration) |
| [`acr-pe-ip-switch-downtime`](./scenarios/acr-pe-ip-switch-downtime/) | Measure traffic downtime when switching an ACR Private Endpoint IP type (Static ↔ Dynamic) (probe + switch + analysis) |
| [`fhir-service-functional-tests`](./scenarios/fhir-service-functional-tests/) | Azure Health Data Services FHIR service functional validation (CRUD, transaction, search, versioning, $validate, $export, $everything) + result report template |
| [`apim-ai-gateway`](./scenarios/apim-ai-gateway/) | Deploy & validate APIM as an AI Gateway (token limit, load balancing + circuit breaker, semantic caching, keyless MI, token metrics) + benefit-measuring scripts |

## Adding a new scenario

1. Create a `scenarios/<name>/` folder (kebab-case)
2. Write the IaC under `infra/` and document deploy/validation steps in `README.md`
3. Add a row to the index table above
