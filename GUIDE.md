# Azure SRE Agent -- Demo Guide

Step-by-step walkthrough for deploying the MSFTLabs SRE Demo environment, configuring Azure SRE Agent in the Azure Portal, and running each chaos scenario live.

---

## Prerequisites

Before starting, ensure you have:

- An Azure subscription with **Owner** or **Contributor + User Access Administrator** privileges.
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) installed.
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed and logged in (`az login`).
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
- [Python 3.11](https://www.python.org/downloads/)
- Your Entra ID **Object ID** (needed for SQL admin). Run: `az ad signed-in-user show --query id -o tsv`

---

## Step 1: Fork and Clone the Repository

1. Fork `MSFTLabs/msftlabs-sre-agent-demo` to your GitHub account.
2. Clone locally or open in a GitHub Codespace:
   ```bash
   git clone https://github.com/<your-org>/msftlabs-sre-agent-demo.git
   cd msftlabs-sre-agent-demo
   ```

---

## Step 2: Deploy the Demo Environment

### 2.1 Initialize azd

```bash
azd init
```

When prompted, provide:
- **Environment name**: e.g., `sre-demo` (this becomes part of all resource names and the resource group `rg-sre-demo`).

### 2.2 Set Required Parameters

```bash
azd env set AZURE_LOCATION "eastus2"
azd env set sqlAadAdminObjectId "$(az ad signed-in-user show --query id -o tsv)"
azd env set sqlAadAdminLogin "$(az ad signed-in-user show --query userPrincipalName -o tsv)"
```

### 2.3 Deploy Everything

```bash
azd up
```

This single command:
1. Provisions all Azure resources via Bicep (App Service, SQL, Key Vault, Function App, Application Gateway with WAF, Log Analytics, Application Insights).
2. Runs `scripts/postprovision.ps1` which generates random passwords for all 11 demo users, stores them in Key Vault, grants the Web App managed identity SQL access, and seeds the database.
3. Deploys the .NET web app and the Python Function App.
4. Runs `scripts/postup.ps1` which displays the Web App URL, Application Gateway URL, and admin credentials.

### 2.4 Verify Deployment

After `azd up` completes, you will see output like:

```
==========================================
  MSFTLabs SRE Demo - Deployment Complete
==========================================

  Web App URL:       https://app-xxxxxxxxxx.azurewebsites.net
  App Gateway URL:   http://agw-xxxxxxxxxx.eastus2.cloudapp.azure.com

  Admin Login
  ───────────────────────────
  Username:          admin
  Password:          <generated-password>
==========================================
```

Open the **Web App URL** in a browser and log in with the admin credentials to confirm the app is working.

### 2.5 Verify Health

Navigate to `/Health/Probe` on the Web App. Confirm all three checks are green:
- **Managed Identity / Key Vault**: Connected
- **SQL Database**: Connected
- **Function App API**: Healthy

---

## Step 3: Configure Azure SRE Agent

### 3.1 Navigate to SRE Agent in the Portal

1. Go to the [Azure Portal](https://portal.azure.com).
2. Search for **"SRE Agent"** in the top search bar, or navigate to it from your subscription or resource group.
3. If SRE Agent is not yet available in your subscription, you may need to register the preview via **Preview Features** or request access.

### 3.2 Create a New SRE Agent Configuration

1. Click **+ Create** or **Configure SRE Agent**.
2. **Scope**: Select the subscription and resource group (`rg-{environmentName}`) that contains the demo resources.
3. **Monitoring Sources**: Ensure the following are connected:
   - **Application Insights**: Select the `appi-{resourceToken}` instance.
   - **Log Analytics Workspace**: Select the `log-{resourceToken}` instance.
4. **Resources to Monitor**: Select all resources in the resource group, or specifically:
   - Web App (`app-{resourceToken}`)
   - Function App (`func-{resourceToken}`)
   - SQL Server (`sql-{resourceToken}`)
   - Key Vault (`kv-{resourceToken}`)
   - Application Gateway (`agw-{resourceToken}`)

### 3.3 Upload Knowledge Files

1. In the SRE Agent configuration, find the **Knowledge Files** section.
2. Upload the file from this repository: `knowledgeFiles/application-architecture.md`
3. This gives the SRE Agent full context about the application architecture, expected behavior, chaos endpoints, error signatures, and relevant KQL queries.

### 3.4 Configure Alert Rules (if applicable)

Depending on SRE Agent's current capabilities, configure or verify:
- **Exception rate threshold**: Alert when `exceptions` count exceeds normal baseline.
- **Dependency failure rate**: Alert on failed SQL or Key Vault dependencies.
- **WAF block events**: Alert on `ApplicationGatewayFirewallLog` blocked entries.
- **Health probe failures**: Alert when backend health drops below 100%.

### 3.5 Validate SRE Agent Connection

Give the agent a few minutes to ingest baseline telemetry. Verify in the SRE Agent dashboard that it shows the monitored resources and is receiving data from Application Insights and Log Analytics.

---

## Step 4: Run the Demo -- Chaos Scenarios

### Before Each Scenario

1. Confirm the app is in a healthy state by checking `/Health/Probe`.
2. Log into the web app as admin.
3. Navigate to the **Admin** page (hamburger menu > Admin).
4. Keep the SRE Agent portal view open in a second browser tab.

---

### Demo 4.1: Key Vault Access Revocation

**Narrative**: "What happens when the Web App's managed identity loses access to Key Vault?"

| Step | Action |
|---|---|
| 1 | From the Admin page, click the **Revoke Key Vault Access** button (or `POST /api/revoke-keyvault-access` via the Function App). |
| 2 | Show the audience the Integration page (`/Dashboard/Integration`) — Key Vault status now shows **Disconnected** with an access denied error. |
| 3 | Show the Health Probe page (`/Health/Probe`) — Managed Identity check shows **Unhealthy**. |
| 4 | Switch to SRE Agent in the portal. Point out how the agent detects the spike in Key Vault `AuthorizationFailed` events and Application Insights exceptions. |
| 5 | Discuss what SRE Agent recommends: restoring the RBAC role assignment. |
| 6 | **Restore**: From the Admin page, click **Restore Key Vault Access** (or `POST /api/restore-keyvault-access`). |
| 7 | Refresh Integration and Health pages — both should return to healthy state. |

**What to look for in SRE Agent**:
- Detection of `Azure.RequestFailedException` in exceptions telemetry.
- Correlation with Key Vault `AuditEvent` access denied entries.
- Recommendation to restore `Key Vault Secrets User` role assignment.

---

### Demo 4.2: SQL Database Access Revocation

**Narrative**: "What happens when the Web App can no longer connect to the SQL database?"

| Step | Action |
|---|---|
| 1 | From the Admin page, click **Revoke SQL Access** (or `POST /api/revoke-sql-access`). |
| 2 | Try to navigate content pages or Dashboard — they will fail with 500 errors. |
| 3 | Check `/Health/Probe` — SQL check shows **Unhealthy** with connection timeout. |
| 4 | Switch to SRE Agent and observe detection of SQL connectivity failures. |
| 5 | Show Application Insights `dependencies` tab — SQL dependency calls failing. |
| 6 | **Restore**: Click **Restore SQL Access** (or `POST /api/restore-sql-access`). |
| 7 | Verify recovery on the Health Probe page. |

**What to look for in SRE Agent**:
- Spike in `SqlException` entries in Application Insights.
- Failed dependency tracking for SQL calls.
- Recommendation to check SQL Server firewall rules.

---

### Demo 4.3: WAF SQL Injection Detection

**Narrative**: "What does SRE Agent see when SQL injection attempts hit the WAF?"

| Step | Action |
|---|---|
| 1 | From the Admin page, click **Trigger WAF SQL Injection** (or `POST /api/trigger-waf-sql-injection`). |
| 2 | The function sends 5 malicious request patterns through the Application Gateway. |
| 3 | Check the results — most/all patterns should be **Blocked** (HTTP 403). |
| 4 | In Log Analytics, run the WAF firewall log query (see knowledge file for KQL). |
| 5 | In SRE Agent, show how the agent classifies these as security events and identifies the OWASP rule IDs that triggered. |
| 6 | **Key point**: No restore needed — the WAF correctly blocked the attacks. The app is unharmed. |

**What to look for in SRE Agent**:
- WAF block events in `ApplicationGatewayFirewallLog`.
- Classification as a security event rather than an application failure.

---

### Demo 4.4: Application Exception Storm

**Narrative**: "What does a sudden burst of application errors look like to SRE Agent?"

| Step | Action |
|---|---|
| 1 | From the Admin page, trigger **Error Storm** with count=100 (or `POST /api/trigger-error-storm?count=100`). |
| 2 | In Application Insights, open the **Failures** blade — observe the spike. |
| 3 | Show SRE Agent detecting the anomalous error rate and correlating it with the function app. |
| 4 | Optionally follow up with **Trigger Exception** (typed exceptions like `timeout` or `division`) to show individual exception tracking. |

---

### Demo 4.5: Latency and Resource Pressure

**Narrative**: "How does SRE Agent respond to performance degradation?"

| Step | Action |
|---|---|
| 1 | Trigger a slow response: `POST /api/trigger-slow-response?delay=30` |
| 2 | Trigger a CPU spike: `POST /api/trigger-cpu-spike?duration=30` |
| 3 | Show App Service metrics — CPU and response time charts spike. |
| 4 | Point out how SRE Agent detects latency anomalies and resource saturation. |

---

## Step 5: Post-Demo Wrap-up

### Talking Points

- **Detection speed**: How quickly SRE Agent identified each issue after the chaos trigger.
- **Root cause accuracy**: Did the agent correctly identify the root cause (RBAC change, firewall rule, WAF rule)?
- **Remediation guidance**: Were the recommendations actionable and correct?
- **Signal correlation**: Show how the agent correlated signals across Application Insights, Log Analytics, Key Vault audit logs, and WAF logs to build a complete picture.

### Reset the Environment

Ensure all access is restored before the next demo run:
1. `POST /api/restore-keyvault-access`
2. `POST /api/restore-sql-access`
3. Verify `/Health/Probe` shows all green.

---

## Step 6: Clean Up

When finished with the demo environment:

```bash
azd down --purge --force
```

This removes all Azure resources including the resource group, Key Vault (with purge), and all RBAC assignments.

---

## Quick Reference: Function App API Endpoints

| Endpoint | Method | Purpose |
|---|---|---|
| `/api/health` | GET | Health check |
| `/api/revoke-keyvault-access` | POST | Revoke Web App Key Vault access |
| `/api/restore-keyvault-access` | POST | Restore Web App Key Vault access |
| `/api/revoke-sql-access` | POST | Revoke Web App SQL connectivity |
| `/api/restore-sql-access` | POST | Restore Web App SQL connectivity |
| `/api/trigger-waf-sql-injection` | POST | Send SQL injection patterns through WAF |
| `/api/trigger-exception?type={type}` | POST | Generate typed exceptions |
| `/api/trigger-slow-response?delay={s}` | POST | Inject latency (max 230s) |
| `/api/trigger-memory-leak?size={mb}` | POST | Allocate memory (max 500MB) |
| `/api/trigger-cpu-spike?duration={s}` | POST | CPU saturation (max 60s) |
| `/api/trigger-error-storm?count={n}` | POST | Burst error logs (max 200) |
| `/api/trigger-log-flood?count={n}&level={lvl}` | POST | Flood logs (max 5000) |
| `/api/trigger-dependency-failure` | POST | Simulate external dependency failure |

---

## Troubleshooting

| Issue | Resolution |
|---|---|
| `postprovision.ps1` fails on SQL firewall | Ensure your public IP is reachable; try from a Codespace instead |
| Admin password shows "(unavailable)" on login page | Check that Key Vault Secrets User role is assigned to Web App managed identity |
| Health probe shows Function App unreachable | Verify Function App deployed and running; check `azd deploy` output for errors |
| WAF test shows 0 blocked patterns | Confirm Application Gateway and WAF policy are deployed; check that APP_GATEWAY_URL env var is set on Function App |
| SRE Agent not detecting issues | Verify Application Insights and Log Analytics are connected in SRE Agent config; allow 2-5 minutes for telemetry ingestion |
