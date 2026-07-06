# Architecture Diagrams (Mermaid)

GitHub-renderable Mermaid version of the ASCII diagrams in the [← case study](./README.en.md).

> Korean version: [ARCHITECTURE.md](./ARCHITECTURE.md)

## Logical Architecture

```mermaid
flowchart TB
    subgraph P["Presentation / Collaboration Layer"]
        UI["Tumor Board dashboard · Teams/Copilot · clinician review UI"]
    end

    subgraph O["Orchestration Layer"]
        ORCH["Orchestrator Agent<br/>(AI Foundry Agent Service · planner · session/state · HITL gate)"]
    end

    subgraph A["Specialized Agents"]
        A1["Imaging Analysis"]
        A2["Clinical Trial Matching"]
        A3["Timeline Generation"]
        A4["Guideline / Evidence Retrieval"]
    end

    subgraph T["Tools / Knowledge Retrieval (Tools & RAG)"]
        RAG["Agentic Retrieval · AI Search (vector/hybrid) · Grounding · MCP tool calls"]
    end

    subgraph D["Data / Models"]
        M["Foundry model catalog"]
        EHR["EHR / FHIR<br/>(Health Data Services)"]
        CT["Clinical Trial DB<br/>(internal / ClinicalTrials.gov)"]
        IMG["Imaging store<br/>(DICOM/PACS · Blob)"]
    end

    UI -->|Entra ID auth, RBAC| ORCH
    ORCH --> A1 & A2 & A3 & A4
    A1 & A2 & A3 & A4 --> RAG
    RAG --> M & EHR & CT & IMG

    X["Cross-cutting: Observability · Governance/Trust · Security<br/>Azure Monitor/App Insights · Foundry Tracing · Content Safety · Purview · Defender · Key Vault"]
    X -.-> P & O & A & T & D
```

## Physical Architecture

```mermaid
flowchart TB
    User["Clinician / Researcher"]

    subgraph Edge["Entry / Security"]
        ENTRA["Entra ID (Conditional Access)"]
        FD["Front Door + WAF"]
    end

    subgraph VNet["Hub-Spoke VNet (Private)"]
        subgraph SApp["Spoke: App"]
            APP["App Service / Container Apps<br/>(web app + API)"]
            APIM["API Management<br/>(AI Gateway: token limits · routing · semantic cache)"]
        end
        subgraph SAI["Spoke: AI"]
            FOUNDRY["AI Foundry (Hub/Project)<br/>Agent Service · Foundry Models · Content Safety"]
            SEARCH["AI Search (vector/hybrid)"]
        end
        subgraph SData["Spoke: Data"]
            HDS["Health Data Services<br/>(FHIR + DICOM)"]
            BLOB["Blob Storage (ZRS)"]
            COSMOS["Cosmos DB (session/state)"]
            CTDB["Clinical Trial DB (SQL/connector)"]
        end
        COMMON["Common: Key Vault · Managed Identity · Private DNS · Bastion"]
    end

    OBS["Observability/Governance/Security (subscription-wide)<br/>Monitor · App Insights · Log Analytics · Foundry Tracing<br/>Purview · Defender for Cloud · Azure Policy"]

    User --> ENTRA --> FD
    FD -->|Private| APP
    APP --> APIM -->|Private Endpoint| FOUNDRY
    FOUNDRY --> SEARCH
    FOUNDRY -->|Private Endpoint| HDS & BLOB & COSMOS & CTDB
    OBS -.-> VNet
```
