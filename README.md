# SRE Agent Demo

Self-contained lab environment for demonstrating Azure SRE Agent capabilities. One-click deployment, one-button incident trigger.

![1774382927084](image/README/1774382927084.png)


## Architecture

| Resource | Purpose |
|---|---|
| **App Service (Linux/.NET 8)** | Multi-page web app with login, dashboard, admin panel, SQL injection trigger |
| **Application Gateway (WAF_v2)** | OWASP 3.2 Prevention mode — blocks SQL injection attacks |
| **Azure SQL Database** | User credential storage, session-backed authentication |
| **Application Insights** | Telemetry, performance monitoring, error tracking |
| **Log Analytics Workspace** | Centralized log collection, WAF firewall logs |
| **Function App (Python)** | Additional chaos engineering API endpoints |
| **Key Vault** | Stores SQL connection string and secrets (RBAC-secured) |

## Demo Scenario

The demo uses a single, clear incident flow:

1. **Admin clicks "Trigger SQL Injection Attack"** on the web app Admin page
2. The web app sends SQL injection patterns through the Application Gateway
3. The **WAF blocks** the requests (HTTP 403) and logs firewall events
4. **Azure Monitor alert fires** ("WAF Blocked Requests Detected", Sev 2)
5. **SRE Agent** picks up the incident and autonomously investigates — checking WAF logs, Application Gateway metrics, and Application Insights telemetry

## Prerequisites

- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli)
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Python 3.11](https://www.python.org/downloads/)

## Quick Start

### 1. Fork and Clone

```powershell
git clone https://github.com/<your-org>/msftlabs-sre-agent-demo.git
cd msftlabs-sre-agent-demo
```

### 2. Deploy

```bash
azd init              # Environment name: sre-demo
azd env set AZURE_LOCATION "centralus"
azd env set sqlAadAdminObjectId "$(az ad signed-in-user show --query id -o tsv)"
azd env set sqlAadAdminLogin "$(az ad signed-in-user show --query userPrincipalName -o tsv)"
azd up
```

### 3. Configure SRE Agent

1. Go to [https://sre.azure.com](https://sre.azure.com) and create an agent
2. Add `rg-sre-demo` as a managed resource group
3. Upload `knowledgeFiles/application-architecture.md` as a knowledge file
4. Create a subagent (e.g., `sre-investigator`)
5. Create an incident response plan → connect it to the subagent

### 4. Run the Demo

1. Log into the web app as admin
2. Go to the **Admin** page
3. Click **"Trigger SQL Injection Attack"**
4. Wait ~2 minutes for the WAF alert to fire
5. Watch SRE Agent investigate the incident

See [GUIDE.md](GUIDE.md) for the full walkthrough.

## Project Structure

```
├── infra/                  # Bicep infrastructure (azd)
│   ├── main.bicep          # Main orchestrator
│   ├── main.parameters.json
│   └── modules/
│       ├── appgateway.bicep    # Application Gateway + WAF
│       ├── appservice.bicep    # App Service Plan + Web App
│       ├── monitoring.bicep    # Log Analytics + App Insights
│       ├── keyvault.bicep      # Key Vault + secrets
│       ├── sql.bicep           # SQL Server + Database
│       ├── functionapp.bicep   # Storage + Function App
│       ├── alerts.bicep        # Azure Monitor alert rules
│       └── diagnostics.bicep   # Diagnostic settings
├── src/
│   ├── web/                # ASP.NET Core 8 MVC application
│   │   ├── Controllers/    # Home, Account, Dashboard, Admin, Health
│   │   ├── Data/           # EF Core DbContext + seeder
│   │   ├── Models/         # User, ViewModels
│   │   └── Views/          # Razor views
│   └── api/                # Python Azure Function App
│       └── function_app.py # Chaos engineering endpoints
├── knowledgeFiles/         # SRE Agent knowledge file
├── azure.yaml              # Azure Developer CLI config
├── GUIDE.md                # Full demo walkthrough
└── README.md
```
