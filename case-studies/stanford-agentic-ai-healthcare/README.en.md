# Stanford Medicine Agentic AI Case Study & Azure Implementation Architecture

> Source: [Transforming Healthcare with Agentic AI: Stanford and Microsoft Lead the Future (WindowsForum, 2025-05-23)](https://windowsforum.com/threads/transforming-healthcare-with-agentic-ai-stanford-and-microsoft-lead-the-future.367652/)

**This folder**: [ARCHITECTURE.en.md](./ARCHITECTURE.en.md) (Mermaid diagrams) · [POC-PLAN.en.md](./POC-PLAN.en.md) (implementation plan) · [infra/](./infra/) (Terraform scaffolding)

> Korean version: [README.md](./README.md)

---

## 1. Stanford Medicine Case Study in Detail

### Background and Problem
Stanford Medicine handles **more than 4,000 Tumor Board patients** every year. Personalized care timelines meaningfully improve oncological outcomes, yet historically **only about 1% of patients** received this level of personalization. The reason: the data-aggregation and synthesis process was entirely **manual**. Clinicians had to comb through and combine the EHR, imaging reads, pathology reports, treatment history, the latest clinical guidelines, and clinical-trial databases by hand.

### Adopting Azure AI Foundry Agent Orchestration
In collaboration with Microsoft, they built a **multi-agent orchestration system**. The key is not one giant model but a structure that **coordinates task-specialized agents**.

| Agent Role | What It Does |
|---|---|
| **Medical Imaging Analysis** | Reviews diagnostic imaging and cross-references it against historical datasets and the latest medical guidelines |
| **Clinical Trial Matching** | Searches clinical-trial databases to determine patient eligibility |
| **Personalized Timeline Generation** | Synthesizes the EHR, diagnostic reports, treatment history, and external guidelines into a dynamic, individualized care plan |

### Reported Impact
- **Time savings**: Removes hours of clinician time per case spent extracting, synthesizing, and organizing data → faster treatment decisions.
- **Actionable insight**: Quickly surfaces subtle patient scenarios, available clinical trials, and current best practices.
- **Scalable personalization**: Potential to extend personalization from the 1% minority to a much broader patient population.
- **Accelerated research**: Better accessibility and usability of EHR/patient data speeds up real-world evidence (RWE) generation.
- Stanford CIO **Dr. Mike Pfeffer** noted that clinicians already use generative-AI summaries in actual Tumor Board meetings.

### Strengths and Cautions (the article's balanced view)
**Strengths**: modularity/scalability (swap or tune agents individually), stronger collaboration, compliance/governance (audit trails and observability), and use of data that was previously hard to access.

**Cautions**:
- **Transparency/explainability**: The architecture is transparent, but each agent's deep reasoning logic remains a black box → potential clinician resistance.
- **Generalization/bias**: Overfitting to Stanford data can degrade performance and raise equity concerns at smaller hospitals with different patient populations.
- **Regulatory barriers**: FDA and European regulatory frameworks are still forming and demand data residency and auditability.
- **Security/privacy**: Each agent widens the attack surface; both inter-agent communication and the cloud infrastructure must be validated.
- **Cost/complexity**: Significant upfront investment in licensing, compliance, model development, and workflow integration.

---

## 2. Azure Logical Architecture

The logical composition for implementing the Tumor Board scenario on Azure.

```
┌───────────────────────────────────────────────────────────────────────┐
│                     Presentation / Collaboration Layer                   │
│   Tumor Board dashboard (web app) · Teams/Copilot integration · UI       │
└───────────────────────────────────┬───────────────────────────────────┘
                                     │ (Entra ID auth, RBAC)
┌───────────────────────────────────▼───────────────────────────────────┐
│                    Orchestration Layer (Orchestrator Agent)              │
│   Azure AI Foundry Agent Service · workflow/planner · state & session    │
│   (Semantic Kernel / MAF multi-agent coordination, human-in-the-loop)    │
└───┬───────────────────┬────────────────────┬─────────────────────┬─────┘
    │                   │                    │                     │
┌───▼──────┐   ┌────────▼────────┐   ┌───────▼────────┐   ┌────────▼───────┐
│ Imaging  │   │ Clinical Trial  │   │ Timeline       │   │ Guideline /    │
│ Analysis │   │ Matching Agent  │   │ Generation     │   │ Evidence       │
│ Agent    │   │                 │   │ Agent          │   │ Retrieval Agent│
└───┬──────┘   └────────┬────────┘   └───────┬────────┘   └────────┬───────┘
    │                   │                    │                     │
┌───▼───────────────────▼────────────────────▼─────────────────────▼─────┐
│                    Tools / Knowledge Retrieval Layer (Tools & RAG)       │
│  Agentic Retrieval · AI Search (vector/hybrid) · Grounding · MCP tools   │
└───┬───────────────────┬────────────────────┬─────────────────────┬─────┘
    │                   │                    │                     │
┌───▼──────┐   ┌────────▼────────┐   ┌───────▼────────┐   ┌────────▼───────┐
│ Model    │   │ EHR / FHIR      │   │ Clinical Trial │   │ Imaging Store  │
│ Layer    │   │ (Healthcare     │   │ DB (internal / │   │ (DICOM/PACS,   │
│ Foundry  │   │  Data Services) │   │  ClinTrials    │   │  Blob)         │
│ catalog  │   │                 │   │  .gov connector)│  │                │
└──────────┘   └─────────────────┘   └────────────────┘   └────────────────┘

Cross-cutting (all layers):  Observability  ·  Governance/Trust  ·  Security
   Azure Monitor/App Insights · Foundry Tracing · Content Safety
   · Purview (data lineage/classification) · Defender · Key Vault · HIPAA/GDPR
```

**Key logical components**
- **Orchestrator Agent**: Decomposes and routes user requests to specialized sub-agents and synthesizes the results. Includes a human-in-the-loop approval gate.
- **Four specialized agents**: imaging analysis / clinical-trial matching / timeline generation / evidence retrieval.
- **Agentic Retrieval + RAG**: Not a single search but iterative, per-agent queries followed by synthesis. Grounded via AI Search vector/hybrid retrieval.
- **Data sources**: FHIR-based EHR, DICOM imaging (PACS/Blob), clinical-trial DB, guideline documents.
- **Cross-cutting concerns**: Observability, governance/trust, and security/compliance are common to every layer.

---

## 3. Azure Physical Architecture

The mapping to actual Azure resources. (Resource names follow your organization's conventions — placeholders used.)

```
                          ┌─────────────────────────┐
   Clinician/Researcher ─▶│  Entra ID (auth / CA)    │
                          │  Front Door + WAF        │
                          └────────────┬────────────┘
                                       │ Private
        ┌──────────────────────────────▼──────────────────────────────┐
        │                    Hub-Spoke VNet (Private)                   │
        │                                                               │
        │  ┌── Spoke: App ──────────────────────────────────────────┐  │
        │  │  App Service / Container Apps  (Tumor Board web app+API) │  │
        │  │  APIM (AI Gateway: token limits · routing · semantic     │  │
        │  │       cache)                                             │  │
        │  └────────────────────────┬───────────────────────────────┘  │
        │                           │ Private Endpoint                  │
        │  ┌── Spoke: AI ───────────▼───────────────────────────────┐  │
        │  │  Azure AI Foundry (Hub/Project)                         │  │
        │  │   ├ Agent Service (Orchestrator + specialized agents)   │  │
        │  │   ├ Foundry Models (GPT-4o/o-series, medical models)    │  │
        │  │   └ Content Safety                                     │  │
        │  │  Azure AI Search (vector/hybrid index)                  │  │
        │  └────────────────────────┬───────────────────────────────┘  │
        │                           │ Private Endpoint                  │
        │  ┌── Spoke: Data ─────────▼───────────────────────────────┐  │
        │  │  Azure Health Data Services (FHIR + DICOM service)      │  │
        │  │  Blob Storage (imaging/docs, ZRS) · Cosmos DB (session) │  │
        │  │  Clinical Trial DB (SQL/connector)                      │  │
        │  └────────────────────────────────────────────────────────┘  │
        │                                                               │
        │  Common: Key Vault · Managed Identity · Private DNS · Bastion │
        └───────────────────────────────────────────────────────────────┘

  Observability/Governance/Security (subscription-wide):
   Azure Monitor · Application Insights · Log Analytics · Foundry Tracing
   Microsoft Purview (data classification/lineage) · Defender for Cloud · Azure Policy
```

### Resource Mapping Summary

| Layer | Azure Service | Role |
|---|---|---|
| Entry/Security | Entra ID, Front Door + WAF, Private Endpoint | Authentication & conditional access, edge protection, private connectivity |
| API Gateway | API Management (AI Gateway) | Token limits, load balancing, semantic caching, content-safety policy |
| App/Hosting | App Service or Container Apps | Dashboard web app, backend API |
| Agent/Orchestration | Azure AI Foundry Agent Service | Runs the orchestrator + specialized agents |
| Models | Foundry Models (GPT-4o/o-series, etc.) | Reasoning, summarization, generation |
| Search/RAG | Azure AI Search | Vector/hybrid search, grounding |
| Safety | Azure AI Content Safety | Harm/hallucination mitigation, jailbreak detection |
| Clinical Data | Azure Health Data Services (FHIR + DICOM) | Standards-based storage/query of EHR & medical imaging |
| Storage/State | Blob Storage (ZRS), Cosmos DB | Imaging/documents, session & agent state |
| Secrets/Identity | Key Vault, Managed Identity | Credential/key management, passwordless auth |
| Observability | Azure Monitor, App Insights, Log Analytics, Foundry Tracing | Per-agent tracing, performance, audit |
| Governance | Purview, Defender for Cloud, Azure Policy | Data lineage/classification, threat detection, policy enforcement |

---

## 4. Key Considerations

### Compliance & Privacy
- Comply with **HIPAA / GDPR / local health laws** (e.g., personal-data-protection and medical acts). A **BAA (Business Associate Agreement)** with Microsoft is required.
- **PHI minimization/de-identification**: Minimize PHI exposure in prompts and logs; tokenize/mask where needed.
- **Data residency**: For domestic data, pin regions (e.g., Korea Central) and control cross-region transfers.
- **Data lineage**: Use Purview to track which data was fed into which agent/model.

### Security (multi-agent = wider attack surface)
- **Private networking**: All PaaS behind Private Endpoints; block public access.
- **Passwordless auth**: Managed Identity + Key Vault; no hardcoded secrets.
- **Validate inter-agent communication** and defend against prompt injection (Content Safety, input validation).
- **Least-privilege RBAC**: Granular permissions per agent and data source.

### Reliability & Clinical Safety
- **Human-in-the-loop required**: AI is decision *support*, not a replacement. Place clinician approval gates.
- **Explainability**: Present the basis for each recommendation (source documents, citations) → eases black-box resistance.
- **Hallucination mitigation**: RAG grounding, mandatory citations, Content Safety groundedness detection.
- **High availability**: Zone-redundant (ZRS storage, zonal deployment), multi-region DR.

### Observability & Governance
- **Per-agent tracing**: Foundry Tracing + App Insights to track each agent's decisions, performance, and interactions, ensuring an audit trail.
- **Evaluation pipeline**: Regularly benchmark accuracy, safety, and bias to prevent regressions.
- **Model version control**: Manage model/prompt change history (GitHub) with rollback capability.

### Bias & Generalization
- **Data-bias validation**: Avoid overfitting to a single institution's data; validate across diverse patient populations.
- **Monitoring**: Continuously track performance drift and equity metrics after deployment.

### Cost & Operations
- **Token-cost management**: APIM AI Gateway for token limits and semantic caching; use `max_completion_tokens` for GPT-family models.
- **Model tiering**: Route simple tasks to small models and only complex reasoning to large models.
- **Incremental pilot**: Start with a single use case that has clearly measurable ROI (e.g., clinical-trial matching), then expand.
- **Change management**: Train clinicians, integrate into workflows, and secure organizational buy-in.
