# ACR Private + Regional Replication Reproduction Scenario

*Read this in [Korean](./README.md).*

A scenario for reproducing the error that occurs when adding **regional replication (geo-replication)**
to an Azure Container Registry (ACR) that is configured as **private** (public network access disabled +
Private Endpoint).

The Terraform code in this folder deploys **only the environment up to just before the regional replica
is configured**. The replica is added separately in the "Error reproduction steps" section below, after
the deployment completes.

- Design: [`DESIGN.md`](./DESIGN.md)
- Implementation plan: [`PLAN.md`](./PLAN.md)
- Infrastructure code: [`infra/`](./infra/) — split into `platform/` (central management) and `application/` (workload)

## Infrastructure layout (`infra/`)

| Layer | Folder | Responsibility | Notes |
| --- | --- | --- | --- |
| platform | [`infra/platform/`](./infra/platform/) | Manages the **Private DNS Zone (`privatelink.azurecr.io`)** and VNet Link in the central (connectivity) subscription | Separate state/subscription |
| application | [`infra/application/`](./infra/application/) | The **workload**: ACR (Premium, public off) + VNet/Subnet + Private Endpoint, etc. | State just before replica configuration |

The two layers run with **independent Terraform state**; application looks up the zone created by platform
via a **`data` block (cross-subscription)** (no direct remote-state coupling).

## Deployed resources

### platform layer
| Resource | Notes |
| --- | --- |
| Resource Group | Central DNS RG (`central-dns-rg` by default) |
| Private DNS Zone | `privatelink.azurecr.io` |
| VNet Link | Links spoke VNets via `linked_vnet_ids` (optional) |

### application layer
| Resource | Notes |
| --- | --- |
| Resource Group | `koreacentral` (default) |
| Virtual Network + Subnet | For the Private Endpoint |
| Azure Container Registry | **Premium**, `public_network_access_enabled = false`, `admin_enabled = false` |
| Private Endpoint | ACR `registry` subresource |

> **The Private DNS Zone is not created by application; it is managed by platform (central).**
> Private Endpoint A-record registration is assumed to be handled by the central **Azure Policy
> (DeployIfNotExists)** by default.
> Setting `use_central_dns_zone_group = true` makes application look up the central zone via a `data`
> block and create the zone group on the Private Endpoint (requires cross-subscription write permission).
>
> The `georeplications` block is intentionally omitted (state just before replica configuration).

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- An authenticated Azure CLI (`az login`) or equivalent credentials
- Subscription permissions to create ACR Premium and a Private Endpoint

## Deployment steps

Deployment order: **platform → application**.

### 1. platform (central DNS) — if needed

If the central Private DNS Zone does not yet exist, deploy it first (skip if a central team already
manages it).

```bash
cd scenarios/acr-private-regional-replication/infra/platform
cp terraform.tfvars.example terraform.tfvars   # adjust subscription_id, etc.
terraform init && terraform apply
```

### 2. application (workload)

```bash
cd scenarios/acr-private-regional-replication/infra/application
cp terraform.tfvars.example terraform.tfvars   # adjust values as needed
terraform init
terraform plan
terraform apply
```

The moment `apply` completes is the **state just before regional replica configuration**.
The outputs (`acr_name`, `acr_login_server`, `resource_group_name`, `vnet_id`, etc.) are used in the next step.

> If you need to link a spoke VNet to the central zone, put application's `vnet_id` output into platform's
> `linked_vnet_ids` and `apply` platform again.

## Error reproduction steps (adding a replica)

After deployment, add a replica in another region to reproduce the error. Use one of the two methods.

### Method 1: Azure CLI

```bash
cd scenarios/acr-private-regional-replication/infra/application
ACR_NAME=$(terraform output -raw acr_name)

az acr replication create \
  --registry "$ACR_NAME" \
  --location japaneast
```

### Method 2: Terraform (add a `georeplications` block)

Add the block below to `azurerm_container_registry.this` in `infra/application/main.tf`, then `terraform apply`:

```hcl
  georeplications {
    location                = "japaneast"
    zone_redundancy_enabled = false
    tags                    = var.tags
  }
```

Record the resulting error message and circumstances.

## Quick troubleshooting guide

Below are **quick decision points** for the symptoms most commonly encountered in this scenario.
See the checklist document for the detailed diagnostic order and rationale.

- Detailed checklist: [`docs/TROUBLESHOOTING-CHECKLIST.md`](./docs/TROUBLESHOOTING-CHECKLIST.md)

| Symptom | First thing to check | Jump to |
| --- | --- | --- |
| Replica creation ends in `Failed` | Check whether Activity Log shows `write` as `Accepted -> Creating -> Failed` (distinguish immediate policy/RBAC blocking) | [Checklist steps 0–2](./docs/TROUBLESHOOTING-CHECKLIST.md) |
| Unclear whether it's a policy/permission issue | Look for `disallowed by policy`, `403/Forbidden`, Deny Assignment traces | [Checklist step 2](./docs/TROUBLESHOOTING-CHECKLIST.md) |
| Suspected PE/DNS path issue | Check whether auto-expansion of a new data endpoint (ipconfig/A-record) on the existing PE failed | [Checklist steps 5–6](./docs/TROUBLESHOOTING-CHECKLIST.md) |
| Suspect the PE uses a Static IP | First check whether the PE NIC `privateIPAllocationMethod` is `Static` | [Checklist step 7](./docs/TROUBLESHOOTING-CHECKLIST.md) |
| No zone link visible in PE DNS configuration | Distinguish VNet Link from Zone Group (`VNet Link != Zone Group`) | [Checklist step 5](./docs/TROUBLESHOOTING-CHECKLIST.md#5-private-endpoint-복제-실패-정밀-진단-최종-원인-영역) |

### Root-cause summary (based on recent cases)

1. First separate **admission-blocking causes** (policy Deny/RBAC/Lock) from backend provisioning failures.
2. An `Accepted -> Creating -> Failed` flow is usually a **backend-stage failure**, not an immediate policy/RBAC block.
3. Ultimately, the cause may be a failure of the "PE replicate" path that auto-adds a new data endpoint to the existing PE.

### Minimal diagnostic commands

The commands below are a minimal set for quickly narrowing down "where it fails".

```bash
# 1) Check Activity Log related to replica create/change
az monitor activity-log list \
  --resource-group {rg-name} \
  --offset 2h \
  --max-events 100

# 2) Check ACR replication status
az acr replication list \
  --registry {acr-name}

# 3) Check Private Endpoint ip configuration (verify data endpoint expansion)
az network private-endpoint show \
  --name {pe-name} \
  --resource-group {rg-name}
```

## Cleanup (deletion)

Delete in reverse order: application → platform.

```bash
cd scenarios/acr-private-regional-replication/infra/application
terraform destroy

cd ../platform
terraform destroy
```
