# Azure SRE Agent -- Demo Guide

Step-by-step walkthrough for deploying the MSFTLabs SRE Demo environment, configuring Azure SRE Agent, and running the SQL public network access incident demo.

---

## Prerequisites

Before starting, ensure you have:

- An Azure subscription with **Owner** or **Contributor + User Access Administrator** privileges.
- [Azure Developer CLI (azd)](https://learn.microsoft.com/azure/developer/azure-developer-cli/install-azd) installed.
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed and logged in (`az login`).
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0)
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
1. Provisions all Azure resources via Bicep (App Service, Application Gateway with WAF, SQL with per-IP firewall rules, Log Analytics, Application Insights, alert rule).
2. Runs `scripts/postprovision.ps1` which grants the Web App managed identity `db_owner` SQL access and seeds the database with content pages.
3. Deploys the .NET web app.
4. Runs `scripts/postup.ps1` which displays the **Application Gateway public URL**.

> **Note:** You may see `RoleAssignmentExists` errors on re-deployment — these are safe to ignore.

### 2.4 Verify Deployment

After `azd up` completes, you will see output like:

```
==========================================
  MSFTLabs SRE Demo - Deployment Complete
==========================================

  Application URL:   http://agw-xxxxxxxxxx.centralus.cloudapp.azure.com
  Public IP:         xx.xx.xx.xx

==========================================
```

Open the **Application URL** in a browser to confirm the app is working.

### 2.5 Verify Health

Navigate to `/Health/Probe` on the Application URL. Confirm the SQL check is green:
- **SQL Database**: Connected (PASS)

---

## Step 3: Configure Azure SRE Agent

After `azd up` completes, the demo infrastructure is deployed but SRE Agent is not yet connected.

### 3.1 Create the SRE Agent

1. Open [https://sre.azure.com](https://sre.azure.com) in your browser.
2. Click **+ Create** in the top-left.
3. Fill in:
   - **Name**: `sre-agent-demo` (or any descriptive name).
   - **Subscription**: Select the subscription where you deployed.
4. Click **Create**. You will be taken to the agent's **Builder** canvas.

### 3.2 Add the Demo Resource Group as a Managed Resource

1. In the SRE Agent portal, click **Settings** (gear icon in the left sidebar).
2. Click the **Managed resources** tab.
3. Click the **Resource groups** sub-tab.
4. Click **+ Add resource group**.
5. Select your demo resource group (e.g., `rg-sre-demo`).
6. Click **Add**.

> **Troubleshooting: Resource group not appearing?**
> The picker only shows resource groups where you have **direct Owner** role. The Bicep deployment includes `deployer-rg-owner.bicep` which assigns this automatically.

### 3.3 Verify the Incident Platform (Azure Monitor)

1. In the left sidebar, click **Builder**.
2. Click the **Incident platform** tab.
3. Confirm **Azure Monitor** shows as **Connected**.

### 3.4 Upload the Knowledge File

1. In the **Builder** view, click the **Knowledge** tab.
2. Click **+ Add knowledge source** > **Upload file**.
3. Select `knowledgeFiles/application-architecture.md` from your local clone.
4. Wait for the upload to complete.

### 3.5 Create the Investigation Subagent

1. Go to **Builder** > **Canvas** tab.
2. Click **+ Create subagent**.
3. Configure:

   | Field | Value |
   |---|---|
   | **Name** | `sre-investigator` |
   | **Instructions** | See below |

   **Instructions**:
   ```
   You are an SRE investigator for the MSFTLabs SRE Demo environment.

   When an Azure Monitor alert fires, investigate using these steps:
   1. Read the alert details — the primary alert is "AppGW Unhealthy Backend" (Sev 1) which fires when the Application Gateway health probe fails.
   2. Check the Application Gateway backend health and the Web App health probe at /Health/Probe.
   3. Check for recent changes via Activity Log on the SQL Server — look for changes to publicNetworkAccess, firewall rules, or networking configuration.
   4. Check Application Insights for SQL connectivity exceptions and failed dependencies.
   5. Identify root cause. The most likely cause is: someone disabled "Public network access" on the SQL Server, which breaks the App Service connection.
   6. Remediate by re-enabling public network access on the SQL Server (set to "Selected networks") and verify the per-IP firewall rules (AppServiceOutbound-*) are still in place.
   7. Provide a root cause analysis with evidence and timeline.

   Key resources:
   - Web App: app-{resourceToken} (.NET 8 on Linux App Service)
   - Application Gateway: agw-{resourceToken} (WAF_v2, health probe polls /Health/Probe)
   - SQL Server: sql-{resourceToken} (Entra-only auth, public access = Selected networks, per-IP firewall rules for App Service outbound IPs)
   - SQL Database: sredemodb
   - Application Insights: appi-{resourceToken}
   - Log Analytics: log-{resourceToken}

   SQL Server firewall rules are named AppServiceOutbound-0, AppServiceOutbound-1, etc. — one per App Service outbound IP.

   Useful KQL queries:
   - SQL failures: dependencies | where type == "SQL" and success == false | summarize count() by resultCode
   - Exceptions: exceptions | where timestamp > ago(1h) | summarize count() by type, outerMessage
   - Health probe failures: AppServiceHTTPLogs | where CsUriStem == "/Health/Probe" and ScStatus >= 500
   ```

4. Click **Save**.

### 3.6 Create the Incident Response Plan

1. In **Builder** > **Canvas**, click **+ Create** > **Trigger** > **Incident response plan**.
2. Configure:

   | Field | Value |
   |---|---|
   | **Name** | `sql-outage-handler` |
   | **Severity** | `Sev 1` |
   | **Response subagent** | `sre-investigator` |
   | **Agent autonomy level** | `Autonomous (Default)` |

3. Click **Create**.

### 3.7 Verify the Canvas

The **Builder** > **Canvas** should show:

```
┌─────────────────────────┐         ┌─────────────────────┐
│  Incident Response Plan │  ────>  │   sre-investigator  │
│  sql-outage-handler     │         │   (Subagent)        │
│  Sev 1, On              │         │                     │
└─────────────────────────┘         └─────────────────────┘
```

---

## Step 4: Run the Demo -- SQL Public Network Access Incident

### Before the Demo

1. Confirm the app is healthy: open the Application Gateway URL and navigate to `/Health/Probe` — SQL should show **PASS**.
2. Open the SRE Agent portal ([https://sre.azure.com](https://sre.azure.com)) in a second browser tab, on the **Incidents** page.

### Demo Flow

| Step | Action | What to Show |
|---|---|---|
| 1 | Open the **Azure Portal** and navigate to the SQL Server resource (`sql-{resourceToken}`). | Show the SQL Server overview — Public network access = "Selected networks". |
| 2 | Go to **Networking** > **Public access** tab. Change from **"Selected networks"** to **"Disable"**. Click **Save**. | Explain: "A new security policy requires disabling public network access on all SQL Servers." |
| 3 | **Wait several minutes** for the change to propagate. | Explain that Azure control-plane changes take time to propagate through existing connection pools. The health probe refreshes its SQL connection every 5 seconds. |
| 4 | Refresh the app in the browser. Pages start showing errors. Navigate to `/Health/Probe`. | Show **SQL Database: FAIL** with a connection error. |
| 5 | The Application Gateway health probe detects the failure and returns **HTTP 502 Bad Gateway**. | Refresh the Application Gateway URL — show the 502 error page. |
| 6 | Switch to the **SRE Agent Incidents** page. Click **Refresh**. | A new incident appears: "AppGW Unhealthy Backend" (Sev 1), status "In progress". |
| 7 | Click the incident to open the investigation thread. | Show the agent's real-time analysis — it checks Activity Log, finds the publicNetworkAccess change, checks backend health, and identifies root cause. |
| 8 | Wait for the agent to complete. | The agent provides RCA: public network access was disabled on the SQL Server, breaking the App Service connection through the per-IP firewall rules. |
| 9 | Agent remediates by re-enabling public network access. | Show the site coming back online after remediation. |

### Key Talking Points

- **Real-world scenario**: This simulates an actual security policy being pushed out that breaks production.
- **Detection speed**: The agent picks up the incident within minutes of the AppGW health alert firing.
- **Root cause via Activity Log**: The agent identifies *who* made the change and *what* changed by parsing the Activity Log.
- **Autonomous remediation**: The agent re-enables public network access (Selected networks) to restore service.
- **RCA output**: The agent summarizes exactly what caused the issue and what steps were taken to remediate.

### What to Look For in SRE Agent

- Activity Log entries showing `Microsoft.Sql/servers/write` with `publicNetworkAccess` changed to `Disabled`
- Application Insights exceptions: `Microsoft.Data.SqlClient.SqlException` with connection failures
- Application Gateway `UnhealthyHostCount` metric spike
- Health probe at `/Health/Probe` returning HTTP 503

---

## Step 5: Post-Demo Wrap-up

### Reset the Environment

If the SRE Agent successfully remediated the issue, the SQL Server public network access is already restored. Verify:

1. Open `/Health/Probe` — SQL should show **PASS**.
2. In the Azure Portal, confirm SQL Server Networking shows "Selected networks" with the AppServiceOutbound-* firewall rules intact.

### Clean Up

When finished with the demo environment:

```bash
azd down --purge --force
```

This removes all Azure resources including the resource group.

---

## Alert Rules

The deployment includes a single Azure Monitor alert rule:

| Alert | Type | Severity | Status | Trigger |
|---|---|---|---|---|
| **AppGW Unhealthy Backend** | Metric | Sev 1 | **Enabled** | `UnhealthyHostCount > 0` on Application Gateway |

This alert fires when the Application Gateway health probe (polling `/Health/Probe` every 30 seconds) detects that the backend Web App is unhealthy. In the demo scenario, this happens because the SQL health check fails after public network access is disabled.

---

## Troubleshooting

| Issue | Resolution |
|---|---|
| `postprovision.ps1` fails on SQL firewall | Ensure your public IP is reachable; try from a Codespace instead |
| Health probe shows SQL FAIL after deployment | Wait 1–2 minutes for the managed identity SQL user to take effect |
| 502 not appearing after disabling SQL public access | Wait several minutes — Azure control plane changes propagate slowly; the health probe refreshes its connection pool every 5 seconds |
| SRE Agent resource group picker is empty | Assign direct Owner role on the resource group (not inherited from management group) |
| SRE Agent shows no incidents | Ensure the incident response plan is created and set to Sev 1 |
| `RoleAssignmentExists` errors during `azd provision` | Safe to ignore — the role assignments already exist from a previous deployment |
