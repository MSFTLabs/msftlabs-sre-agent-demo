# Azure SRE Agent -- Demo Guide

Step-by-step walkthrough for deploying the MSFTLabs SRE Demo environment, configuring Azure SRE Agent, and running the SQL injection incident demo.

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
azd env set AZURE_LOCATION "centralus"
azd env set sqlAadAdminObjectId "$(az ad signed-in-user show --query id -o tsv)"
azd env set sqlAadAdminLogin "$(az ad signed-in-user show --query userPrincipalName -o tsv)"
```

### 2.3 Deploy Everything

```bash
azd up
```

This single command:
1. Provisions all Azure resources via Bicep (App Service, Application Gateway with WAF, SQL, Key Vault, Function App, Log Analytics, Application Insights, alert rules).
2. Runs `scripts/postprovision.ps1` which generates random passwords for all 11 demo users, stores them in Key Vault, grants the Web App managed identity SQL access, and seeds the database.
3. Deploys the .NET web app and the Python Function App.
4. Runs `scripts/postup.ps1` which displays the Web App URL, Application Gateway URL, and admin credentials.

> **Note:** You may see `RoleAssignmentExists` errors on re-deployment — these are safe to ignore.

### 2.4 Verify Deployment

After `azd up` completes, you will see output like:

```
==========================================
  MSFTLabs SRE Demo - Deployment Complete
==========================================

  Web App URL:       https://app-xxxxxxxxxx.azurewebsites.net
  App Gateway URL:   http://agw-xxxxxxxxxx.centralus.cloudapp.azure.com

  Admin Login
  ───────────────────────────
  Username:          admin
  Password:          <generated-password>
==========================================
```

Open the **Web App URL** in a browser and log in with the admin credentials to confirm the app is working.

### 2.5 Verify Health

Navigate to `/Health/Probe` on the Web App. Confirm all checks are green:
- **Managed Identity / Key Vault**: Connected
- **SQL Database**: Connected
- **Function App API**: Healthy

---

## Step 3: Configure Azure SRE Agent

After `azd up` completes, the demo infrastructure is deployed but SRE Agent is not yet connected. This section walks through every click needed to wire SRE Agent to the demo environment so it can detect and investigate the WAF SQL injection alerts.

### 3.1 Create the SRE Agent

1. Open [https://sre.azure.com](https://sre.azure.com) in your browser.
2. Click **+ Create** in the top-left.
3. Fill in:
   - **Name**: `sre-agent-demo` (or any descriptive name).
   - **Subscription**: Select the subscription where you deployed (the same one used with `azd up`).
4. Click **Create**. You will be taken to the agent's **Builder** canvas.

### 3.2 Add the Demo Resource Group as a Managed Resource

The SRE Agent needs explicit access to the resource group containing your demo resources. This step grants the agent's managed identity the necessary RBAC roles (Reader, Monitoring Reader, etc.) on the resource group.

1. In the SRE Agent portal, click **Settings** (gear icon in the left sidebar).
2. Click the **Managed resources** tab.
3. Click the **Resource groups** sub-tab.
4. Click **+ Add resource group**.
5. In the picker, find and select your demo resource group:
   - If you used `sre-demo` as the environment name: select `rg-sre-demo`.
   - General pattern: `rg-{environmentName}`.
6. Click **Add**. The portal will assign the required RBAC roles to the agent's managed identity.

> **Troubleshooting: Resource group not appearing in the picker?**
>
> The picker only shows resource groups where your signed-in user has **direct Owner** or **User Access Administrator** role — roles inherited from a management group are not sufficient. The Bicep deployment includes `infra/modules/deployer-rg-owner.bicep` which assigns Owner to the deployer at the resource group level. If this didn't take effect (e.g., you skipped provisioning), assign it manually:
> ```bash
> az role assignment create \
>   --assignee "$(az ad signed-in-user show --query id -o tsv)" \
>   --role "Owner" \
>   --scope "/subscriptions/{subscriptionId}/resourceGroups/rg-sre-demo"
> ```

### 3.3 Verify the Incident Platform (Azure Monitor)

The incident platform tells SRE Agent where to listen for incoming alerts. Azure Monitor is configured by default.

1. In the left sidebar, click **Builder**.
2. Click the **Incident platform** tab (next to "Canvas" and "Knowledge").
3. Confirm **Azure Monitor** shows as **Connected**.
   - If not connected, click **Connect** and authorize access to your subscription.

This is how SRE Agent receives the `alert-waf-blocked-requests` and `alert-appgw-unhealthy-backend` alerts that the Bicep deployment created.

### 3.4 Upload the Knowledge File

The knowledge file gives the agent deep context about your specific environment — resource names, architecture, alert rules, expected error signatures, and KQL queries it can use during investigations.

1. In the **Builder** view, click the **Knowledge** tab.
2. Click **+ Add knowledge source** > **Upload file**.
3. Select the file `knowledgeFiles/application-architecture.md` from your local clone.
4. Wait for the upload to complete (a green checkmark appears).

**What the knowledge file contains:**
- Full resource inventory (Web App, Function App, SQL, Key Vault, App Gateway, Log Analytics, App Insights) with naming patterns.
- Database schema (Users, SitePages tables).
- RBAC role assignments for each managed identity.
- All six alert rule definitions and their KQL queries.
- Chaos scenario playbooks — especially the **WAF SQL Injection** scenario marked as the primary demo.
- KQL query templates the agent can use (WAF blocked requests, failed dependencies, exceptions, Key Vault audit events).
- Architecture diagram showing the attack flow: Web App → App Gateway WAF → Blocked → Log Analytics → Alert → SRE Agent.

### 3.5 Create the Investigation Subagent

A subagent is the AI persona that actually performs the investigation when an incident arrives. You need at least one subagent before you can create an incident response plan.

1. Go to **Builder** > **Canvas** tab.
2. Click **+ Create subagent** (or **+ Create** > **Subagent**).
3. Configure the subagent:

   | Field | Value |
   |---|---|
   | **Name** | `sre-investigator` |
   | **Instructions** | See below |

   **Instructions** (paste this into the Instructions field):
   ```
   You are an SRE investigator for the MSFTLabs SRE Demo environment.

   When an Azure Monitor alert fires, investigate it using these steps:
   1. Read the alert details to understand which rule fired and at what severity.
   2. For WAF alerts (alert-waf-blocked-requests): Query ApplicationGatewayFirewallLog in Log Analytics to find blocked requests. Identify the OWASP rule IDs that matched, the request URIs, and the source IPs. Classify this as a security event — the WAF is correctly blocking malicious traffic. The web application backend should remain healthy.
   3. For backend health alerts (alert-appgw-unhealthy-backend): Check the Application Gateway backend health metrics and the Web App health probe at /Health/Probe. Investigate whether the root cause is a Key Vault access failure, SQL connectivity issue, or application crash by checking Application Insights exceptions and dependencies.
   4. Check Application Insights for correlated exceptions, failed dependencies, and request failures in the same time window.
   5. Provide a root cause analysis with evidence (specific log entries, metric values, timeline).
   6. Recommend remediation steps.

   Key resources in this environment:
   - Web App: app-{resourceToken} (.NET 8 on Linux App Service)
   - Application Gateway: agw-{resourceToken} (WAF_v2, OWASP 3.2 Prevention mode)
   - SQL Database: sql-{resourceToken}/sredemodb (Entra-only auth)
   - Key Vault: kv-{resourceToken} (RBAC authorization)
   - Application Insights: appi-{resourceToken}
   - Log Analytics Workspace: log-{resourceToken}

   Useful KQL queries:
   - WAF blocks: AzureDiagnostics | where Category == "ApplicationGatewayFirewallLog" | where action_s == "Blocked"
   - Exceptions: exceptions | where timestamp > ago(1h) | summarize count() by type, outerMessage
   - Failed deps: dependencies | where success == false | summarize count() by target, type, resultCode
   ```

4. **Tools and Skills**: Leave the default tool set or verify the agent has access to:
   - Azure Monitor (queries, metrics, alerts)
   - Log Analytics (KQL queries)
   - Application Insights (exceptions, dependencies, requests)
   - Azure Resource Manager (resource health, configuration)
5. Click **Save**.

### 3.6 Create the Incident Response Plan

The incident response plan is the trigger that connects Azure Monitor alerts to your subagent. When an alert fires and matches the plan's filter criteria, SRE Agent creates an incident and dispatches the subagent to investigate.

1. In the **Builder** > **Canvas** view, click **+ Create** > **Trigger** > **Incident response plan**.
2. Configure the plan:

   | Field | Value | Notes |
   |---|---|---|
   | **Name** | `waf-alert-handler` | Descriptive name for the plan |
   | **Severity** | `All severity` | Catches both Sev 1 (backend health) and Sev 2 (WAF blocks) |
   | **Title contains** | *(leave blank)* | Blank = matches all alert titles. Alternatively enter `SRE Demo` to match only this demo's alerts, which are all prefixed "SRE Demo:" |
   | **Response subagent** | `sre-investigator` | The subagent you created in 3.5 |
   | **Agent autonomy level** | `Autonomous (Default)` | The agent investigates without asking for approval |

3. Click **Next**.
4. The **Preview** page may show **"No matching alerts found"** — this is normal. The preview only shows alerts that are currently active. Your trigger will still work for future alerts.
5. Click **Create**.

### 3.7 Verify the Canvas

After completing steps 3.5 and 3.6, the **Builder** > **Canvas** should show:

```
┌─────────────────────────┐         ┌─────────────────────┐
│  Incident Response Plan │  ────>  │   sre-investigator  │
│  waf-alert-handler      │         │   (Subagent)        │
│  All severity, On       │         │                     │
└─────────────────────────┘         └─────────────────────┘
```

The incident response plan node connects to the subagent node with an arrow. The plan status should show **"On"**.

### 3.8 Understand the Alert-to-Incident Flow

Here is what happens end-to-end when you trigger the demo:

```
Admin page "Trigger SQL Injection Attack" button
    │
    ▼
Web App sends 5 SQL injection patterns to App Gateway URL
    │
    ▼
Application Gateway WAF blocks requests (HTTP 403)
    │
    ▼
WAF logs written to Log Analytics (ApplicationGatewayFirewallLog)
    │
    ▼  (~1 minute)
Azure Monitor alert rule "alert-waf-blocked-requests" evaluates:
    KQL: AzureDiagnostics | where Category == "ApplicationGatewayFirewallLog"
                          | where action_s == "Blocked"
    Threshold: count > 1 in 5-minute window
    │
    ▼
Alert fires (Severity 2, title "SRE Demo: WAF Blocked Requests Detected")
    │
    ▼
SRE Agent incident response plan "waf-alert-handler" matches (All severity)
    │
    ▼
SRE Agent creates Incident, dispatches "sre-investigator" subagent
    │
    ▼
Subagent queries Log Analytics for WAF logs, checks App Gateway metrics,
reviews Application Insights telemetry, and produces root cause analysis
```

The total time from button click to incident appearing in the SRE Agent portal is typically **1–3 minutes** (one alert evaluation cycle of 1 minute, plus ingestion latency).

---

## Step 4: Run the Demo -- SQL Injection Incident

### Before the Demo

1. Confirm the app is healthy at `/Health/Probe`.
2. Log into the web app as admin.
3. Open the SRE Agent portal ([https://sre.azure.com](https://sre.azure.com)) in a second browser tab, on the **Incidents** page.

### Demo Flow

| Step | Action | What to Show |
|---|---|---|
| 1 | Navigate to the **Admin** page in the web app. | Single "Trigger SQL Injection Attack" button. |
| 2 | Click **"Trigger SQL Injection Attack"**. | The button sends SQL injection patterns through the Application Gateway. A success message shows how many patterns were blocked (e.g., "5/5 patterns blocked by WAF"). |
| 3 | **Wait ~2 minutes** for the Azure Monitor alert evaluation cycle. | Explain that alerts evaluate every 1 minute with a 5-minute lookback window. |
| 4 | Switch to the **SRE Agent Incidents** page. Click **Refresh**. | A new incident appears: "WAF Blocked Requests Detected" (Sev 2), status "In progress". |
| 5 | Click the incident to open the investigation thread. | Show the agent's real-time analysis — it queries WAF logs, checks Application Gateway metrics, and identifies the OWASP rules that triggered. |
| 6 | Wait for the agent to complete investigation. | The agent provides root cause analysis: WAF correctly blocked SQL injection attempts matching OWASP 3.2 rules. |

### Key Talking Points

- **Detection speed**: The agent picks up the incident within minutes of the alert firing.
- **Root cause accuracy**: The agent correctly identifies WAF blocked requests as security events, not application failures.
- **Signal correlation**: The agent correlates WAF firewall logs in Log Analytics with Application Gateway metrics and Application Insights telemetry.
- **Autonomous investigation**: No human intervention needed — the agent acknowledges the alert, gathers evidence, and provides a summary.

### What to Look For in SRE Agent

- WAF block events in `ApplicationGatewayFirewallLog` with matched OWASP rule IDs
- Classification as a security event rather than an application failure
- Application Gateway health metrics (backend should remain healthy — WAF blocks happen at the gateway level)

---

## Step 5: Post-Demo Wrap-up

### Reset the Environment

No reset needed for the WAF demo — the SQL injection patterns are one-time requests that the WAF blocked. The application remains healthy throughout.

### Clean Up

When finished with the demo environment:

```bash
azd down --purge --force
```

This removes all Azure resources including the resource group, Key Vault (with purge), and all RBAC assignments.

---

## Alert Rules

The deployment includes six Azure Monitor alert rules. Only the WAF-related alerts are enabled by default for the demo:

| Alert | Severity | Status | Trigger |
|---|---|---|---|
| **WAF Blocked Requests Detected** | Sev 2 | **Enabled** | `ApplicationGatewayFirewallLog` with `action == "Blocked"` |
| **App Gateway Unhealthy Backend** | Sev 1 | **Enabled** | `UnhealthyHostCount > 0` metric |
| Key Vault Access Failure | Sev 1 | Disabled | Key Vault access denied exceptions |
| SQL Connectivity Failure | Sev 1 | Disabled | Failed SQL dependency calls |
| Exception Rate Spike | Sev 2 | Disabled | Unhandled exceptions in Application Insights |
| Function App Error Storm | Sev 2 | Disabled | Error-level Function App logs |

To enable additional alerts, set `enabled: true` in `infra/modules/alerts.bicep` and run `azd provision`.

---

## Troubleshooting

| Issue | Resolution |
|---|---|
| `postprovision.ps1` fails on SQL firewall | Ensure your public IP is reachable; try from a Codespace instead |
| Admin password shows "(unavailable)" on login page | Check that Key Vault Secrets User role is assigned to Web App managed identity |
| SQL injection trigger shows "AppGatewayUrl not configured" | Run `azd provision` to add the `AppGatewayUrl` app setting to the web app |
| WAF test shows 0 blocked patterns | Confirm Application Gateway and WAF policy are deployed; check App Gateway URL is reachable |
| SRE Agent resource group picker is empty | Assign direct Owner role on the resource group to your user (not inherited from management group) |
| SRE Agent shows no incidents | Ensure an incident response plan is created and connected to a subagent |
| `RoleAssignmentExists` errors during `azd provision` | Safe to ignore — the role assignments already exist from a previous deployment |
