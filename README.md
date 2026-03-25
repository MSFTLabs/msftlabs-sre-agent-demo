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

## Getting Started

### Prerequisites

Ensure you are logged in to both CLIs (they use **separate** credential stores):

```powershell
# Azure CLI login
az login
az account set --subscription "<your-subscription-id>"

# Azure Developer CLI login (must match the same tenant)
azd auth login --tenant-id "<your-tenant-id>"
```

> **Tip:** Get your tenant ID with `az account show --query tenantId -o tsv`

---

### AZD Command Reference

#### Initialize a new environment

```powershell
azd init
# Follow the prompts — choose an environment name (e.g., sre-demo)
```

#### Configure environment variables

```powershell
# Required: Set your target subscription and region
azd env set AZURE_SUBSCRIPTION_ID "<your-subscription-id>"
azd env set AZURE_LOCATION "eastus2"
```

> **Note:** SQL Entra admin identity is auto-detected from your `az login` session via a preprovision hook — no manual setup needed.

#### Provision infrastructure only

```powershell
azd provision          # Deploys Bicep templates, runs postprovision.ps1 hook
```

#### Deploy application code only

```powershell
azd deploy             # Builds & deploys src/web (.NET) and src/api (Python)
azd deploy web         # Deploy only the web service
azd deploy api         # Deploy only the function app
```

#### Provision + deploy in one step

```powershell
azd up                 # Equivalent to: azd provision + azd deploy + postup hook
```

#### View / switch environments

```powershell
azd env list                          # List all environments
azd env select <env-name>            # Switch active environment
azd env get-values                    # Show all env variables for current environment
azd env set <KEY> "<VALUE>"           # Set a variable
azd env new <env-name>               # Create a new environment
```

#### Monitor and troubleshoot

```powershell
azd monitor --overview                # Open Application Insights overview
azd monitor --live                    # Open live metrics stream
azd monitor --logs                    # Open Log Analytics logs
```

#### Tear down

```powershell
azd down                              # Delete all Azure resources for the environment
azd down --purge                      # Also purge soft-deleted Key Vaults & App Configs
```

#### Other useful commands

```powershell
azd env refresh                       # Re-fetch outputs from the latest deployment
azd config show                       # Show global azd configuration
azd config set defaults.subscription "<subscription-id>"   # Set default subscription
azd config set defaults.location "eastus2"                 # Set default location
```

---

### Quick Deploy (copy-paste)

```powershell
git clone https://github.com/MSFTLabs/msftlabs-sre-agent-demo.git
cd msftlabs-sre-agent-demo

az login
azd auth login --tenant-id "$(az account show --query tenantId -o tsv)"

azd init
azd env set AZURE_LOCATION "eastus2"
azd up
```

The `preprovision` hook auto-detects your identity for SQL Entra admin. The `postprovision` hook seeds the SQL database, grants the web app managed identity `db_owner`, and stores demo user passwords in Key Vault. The `postup` hook prints the web app URL and admin credentials.

---

### Configure SRE Agent

1. Go to [https://sre.azure.com](https://sre.azure.com) and create an agent
2. Add `rg-sre-demo` as a managed resource group
3. Upload `knowledgeFiles/application-architecture.md` as a knowledge file
4. Create a subagent (e.g., `sre-investigator`)
5. Create an incident response plan → connect it to the subagent

### Run the Demo

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
