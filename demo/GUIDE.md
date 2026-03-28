# Azure SRE Agent — Demo Guide

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

- **Environment name**: e.g., `sreagent-demo-01` (this becomes part of all resource names and the resource group `rg-sreagent-demo-01`).

### 2.2 Set Required Parameters

```bash
azd env set AZURE_LOCATION "eastus2"
azd env set sqlAadAdminObjectId "$(az ad signed-in-user show --query id -o tsv)"
azd env set sqlAadAdminLogin "$(az ad signed-in-user show --query userPrincipalName -o tsv)"

# Optional: SRE Agent GitHub integration
azd env set AZURE_GITHUB_TOKEN "<your-github-pat>"   # PAT with repo scope
azd env set AZURE_GITHUB_REPO_URL "https://github.com/<your-org>/msftlabs-sre-agent-demo"
```

### 2.3 Deploy Everything

```bash
azd up
```

This single command:

1. Runs `scripts/preprovision.ps1` which detects your deployer identity and cleans any stale SRE Agent action groups.
2. Provisions all Azure resources via Bicep — App Service, Application Gateway with WAF, SQL with per-IP firewall rules, Log Analytics, Application Insights, **Azure SRE Agent**, and alert rule.
3. Runs `scripts/postprovision.ps1` which:
   - Grants the Web App managed identity `db_owner` SQL access and seeds the database with content pages.
   - Configures the SRE Agent — sets the GitHub PAT (if provided), creates an Azure Monitor incident action group, and wires it to the alert rule.
4. Deploys the .NET web app.
5. Runs `scripts/postup.ps1` which displays the **Application Gateway public URL**.

> **Note:** You may see `RoleAssignmentExists` errors on re-deployment — these are safe to ignore.

### 2.4 Verify Deployment

After `azd up` completes, you will see output like:

```
==========================================
  MSFTLabs SRE Demo - Deployment Complete
==========================================

  Application URL:   http://agw-xxxxxxxxxx.eastus2.cloudapp.azure.com
  Public IP:         xx.xx.xx.xx

==========================================
```

Open the **Application URL** in a browser to confirm the app is working.

### 2.5 Verify Health

Navigate to `/Health/Probe` on the Application URL. Confirm the SQL check is green:

- **SQL Database**: Connected (PASS)

---

## Step 3: Run the Demo

This demo tells a story: InfoSec pushed a security policy that disabled public network access on a SQL Server at 3 AM on Saturday morning — without telling anyone. The main website is now down. We'll use Azure SRE Agent to detect, investigate, and remediate the outage automatically.

### 3.1 Show the Healthy Application

1. Open the **Application Gateway URL** in a browser — show the working website.
2. Navigate to `/Health/Probe` — show the **SQL Database: PASS** health check.
3. Briefly explain the architecture: App Gateway → App Service → SQL Database.

### 3.2 Break the Application (Simulate the Policy Change)

1. Open the **Azure Portal** and navigate to the SQL Server resource (`sql-{resourceToken}`).
2. Go to **Networking** → **Public access** tab.
3. Change from **"Selected networks"** to **"Disable"**. Click **Save**.
4. Narrate: *"InfoSec just pushed a new security policy that requires disabling public network access on all SQL Servers. This was applied at 3 AM on a Saturday — no change advisory, no notification."*

> **This change takes several minutes to propagate.** Use this time to set up the SRE Agent (Step 3.3). The health probe refreshes its SQL connection pool every 5 seconds, so it will detect the failure as soon as the change takes effect.

### 3.3 Configure the SRE Agent (While Waiting for Propagation)

Use the propagation wait time to finish configuring the SRE Agent in the portal. The agent resource itself was already deployed via Bicep, and the `postprovision` script configured the GitHub PAT and incident action group.

#### Verify the Agent

1. Open [https://sre.azure.com](https://sre.azure.com) in a new browser tab.
2. The SRE Agent (`sre-{resourceToken}`) should appear in the list — click it.
3. Verify **Settings** → **Incidents** shows **Azure Monitor** as **Connected**.
4. Narrate: *"The SRE Agent was deployed as part of our Bicep infrastructure and automatically connected to Azure Monitor for incident routing."*

#### Grant Permissions

1. Go to **Settings** → **Azure settings** → **Identity**.
2. Grant the SRE Agent's Managed Identity **Contributor** role on the demo resource group.
   - This gives the agent permission to read resource configurations, query Activity Logs, and make changes to remediate issues.

#### Upload Knowledge Files

1. Go to **Builder** → **Knowledge** tab.
2. Click **+ Add knowledge source** → **Upload file**.
3. Upload both files from the `knowledgeFiles/` folder:
   - `application-architecture.md`
   - `appgw-health-probe-troubleshooting.md`
4. Narrate: *"Knowledge files give the agent context about our specific environment — what resources exist, how they're connected, and what to look for."*

> **Note:** Knowledge files must be uploaded through the portal — no ARM REST API is available for this.

> **While configuring, use the talking points below to fill time.**

#### Talking Points While Agent Deploys

**Why Anthropic (Claude) vs Azure OpenAI (GPT)?**

- SRE Agent supports **both** model providers — this is a choice, not a lock-in.
- **Anthropic (Claude)** is the _Preferred_ option in the portal:
  - Strong at following complex, multi-step instructions with nuance (important for investigation workflows).
  - Excellent at reasoning through cause-and-effect chains (e.g., "public access disabled → connection failed → health probe failed → 502").
  - Tends to be more cautious / less likely to hallucinate remediation steps.
- **Azure OpenAI (GPT)** is also available:
  - Runs entirely within your Azure tenant and the EU Data Boundary (EUDB) if required for compliance.
  - Good option if your organization has data residency requirements or existing Azure OpenAI investments.
- **Bottom line**: Choose Anthropic for best investigation quality; choose Azure OpenAI if EUDB/data sovereignty is a hard requirement.

**Key SRE Agent Capabilities**

- **Incident platforms**: Connects to Azure Monitor, PagerDuty, or ServiceNow — alerts become incidents automatically.
- **Managed resources**: Scoped to specific resource groups — the agent only sees and acts on what you allow.
- **Knowledge files**: Upload architecture docs, runbooks, or environment guides so the agent understands _your_ specific environment, not just generic Azure.
- **Subagents**: Specialized agents with focused instructions — you can have different subagents for different incident types.
- **Incident response plans**: Map severity levels to subagents — Sev 1 triggers the investigator automatically, no human needed at 3 AM.
- **Autonomy levels**: From fully autonomous to human-in-the-loop — you control how much the agent can do on its own.
- **Execute Code skill**: The agent can spin up a sandboxed VM with your managed identity to run arbitrary CLI commands (az cli, PowerShell, etc.) for investigation and remediation.
- **Audit trail**: Every action the agent takes is logged — full transparency for post-incident review.

#### Configure Azure Settings & Permissions

1. If not already done, grant the SRE Agent's Managed Identity **Contributor** role on the demo resource group (see above).

#### Connect Incident Platform

1. Go to **Settings** → **Incidents**.
2. Confirm **Azure Monitor** shows as **Connected**.
3. Narrate: *"The postprovision script created an Azure Monitor action group that routes alerts directly to the SRE Agent as incidents — no manual configuration needed."*

#### Upload the Knowledge Files

1. If not already done, go to **Builder** → **Knowledge** tab.
2. Upload both files from `knowledgeFiles/`:
   - `application-architecture.md`
   - `appgw-health-probe-troubleshooting.md`
3. Narrate: *"Knowledge files give the agent context about our specific environment — what resources exist, how they're connected, and what to look for."*

### 3.4 Create the Subagent and Incident Response Plan

#### Create the Investigation Subagent

1. Go to **Builder** → **Canvas** tab.
2. Click **+ Create subagent**.
3. Configure:
   - **Name**: `sre-investigator`
   - **Instructions**: Paste the following:

   ```
   ## Goal
   Diagnose and remediate backend service outages in the MSFTLabs SRE Demo
   environment by investigating Azure resource health, recent changes, and
   impacted dependencies — then facilitate rollback when appropriate to
   restore service health.

   ## Environment
   - Web App: app-{resourceToken} — .NET 8 on Linux App Service, health
     endpoint at /Health/Probe
   - Application Gateway: agw-{resourceToken} — WAF_v2, health probe polls
     /Health/Probe every 30s
   - SQL Server: sql-{resourceToken} — Entra-only auth, public access =
     Selected networks, per-IP firewall rules (AppServiceOutbound-0,
     AppServiceOutbound-1, etc.)
   - SQL Database: sredemodb
   - Application Insights: appi-{resourceToken}
   - Log Analytics: log-{resourceToken}

   ## Tasks
   1. Confirm the outage: Identify which backend services or resources are
      down. Gather resource names, resource group, and subscription context
      from the alert.
   2. Check Application Gateway: Inspect backend health status. If backends
      are unhealthy, check the Web App health probe at /Health/Probe for
      errors.
   3. Check Activity Log: Query the Azure Activity Log for recent
      write/delete operations on impacted resources within the last 24
      hours — focus on SQL Server changes to publicNetworkAccess, firewall
      rules, or networking configuration.
   4. Check Application Insights: Look for SQL connectivity exceptions and
      failed dependencies using queries like:
      - dependencies | where type == "SQL" and success == false | summarize
        count() by resultCode
      - exceptions | where timestamp > ago(1h) | summarize count() by type,
        outerMessage
   5. Correlate changes to impact: Determine if any recent change aligns
      with the outage start time. The most common root cause is: public
      network access was disabled on the SQL Server, breaking the App
      Service → SQL connection.
   6. Propose and execute rollback: If a recent change is identified as
      the likely cause, propose a specific rollback (e.g., re-enable public
      network access on SQL Server set to "Selected networks") and verify
      per-IP firewall rules (AppServiceOutbound-*) are still in place.
      Always confirm with the user before executing any rollback.
   7. Acknowledge and close alerts: After remediation is verified,
      acknowledge and close the firing Azure Monitor alert(s).

   ## Constraints
   - Managed Identity has Contributor on the Resource Group — use it for
     all Azure operations.
   - If no recent changes are found or the cause is unclear, state this
     clearly and suggest escalation rather than guessing.
   - Limit rollback scope to the specific change correlated with the
     outage; do not perform broad or speculative rollbacks.
   - Do not repeat the same diagnostic steps — if something doesn't work,
     move on to the next approach.

   ## Output Format
   Summarize findings in a structured format:
   - Outage Summary: What is down, since when, and what is the user impact.
   - Recent Changes Found: List of relevant Activity Log entries with
     timestamps and callers.
   - Correlation Assessment: How the identified change caused the outage,
     with evidence.
   - Remediation Taken: Exact steps executed to restore service, with
     verification results.
   ```

4. Click **Save**.

#### Create the Incident Response Plan

1. In **Builder** → **Canvas**, click **+ Create** → **Trigger** → **Incident response plan**.
2. Configure:

   | Field                      | Value                  |
   | -------------------------- | ---------------------- |
   | **Name**                   | `outage-handler`       |
   | **Severity**               | `Sev 1`               |
   | **Response subagent**      | `sre-investigator`     |
   | **Agent autonomy level**   | `Autonomous (Default)` |

3. Click **Create**.

#### Verify the Canvas

The **Builder** → **Canvas** should show:

```
┌─────────────────────────┐         ┌─────────────────────┐
│  Incident Response Plan │  ────>  │   sre-investigator  │
│  outage-handler         │         │   (Subagent)        │
│  Sev 1, On              │         │                     │
└─────────────────────────┘         └─────────────────────┘
```

### 3.5 Confirm the Outage

By now, the SQL public network access change should have propagated.

1. Switch back to the browser with the Application Gateway URL.
2. Refresh the page — it should return **HTTP 502 Bad Gateway**.
3. Navigate to `/Health/Probe` — show **SQL Database: FAIL** with a connection error.
4. Narrate: *"The website is now completely down. The health probe is failing because the App Service can no longer reach SQL. The Application Gateway sees the unhealthy backend and returns 502 to all users."*

### 3.6 Watch SRE Agent Handle the Incident

1. Switch to the **SRE Agent** portal → **Incidents** page.
2. Click **Refresh** until the incident appears: **"AppGW Unhealthy Backend"** (Sev 1), status **"In progress"**.
3. Click the incident to open the investigation thread.
4. Walk through the agent's real-time analysis as it:
   - Checks Application Gateway backend health
   - Queries the Activity Log and finds the `publicNetworkAccess` change
   - Checks Application Insights for SQL connection failures
   - Correlates the timeline and identifies root cause
   - Proposes remediation: re-enable public network access (Selected networks)
   - Executes the rollback

### 3.7 Verify Remediation

1. After the agent completes, refresh the Application Gateway URL — the site should be back online.
2. Navigate to `/Health/Probe` — show **SQL Database: PASS**.
3. Show the agent's RCA output summarizing:
   - **What happened**: Public network access was disabled on the SQL Server.
   - **Who made the change**: The caller identity from the Activity Log.
   - **What was done**: Public network access re-enabled to "Selected networks".
   - **Verification**: Site is back online, health probe passing.

### 3.8 Close the Alert

1. Go to **Azure Monitor** → **Alerts** → find `alert-appgw-unhealthy-backend`.
2. Show the alert history — firing time, resolution time.
3. The SRE Agent should have acknowledged/closed the alert as part of its workflow.

---

## Key Talking Points

- **Real-world scenario**: This simulates an actual security policy being pushed out that breaks production — at 3 AM on a Saturday with no change advisory.
- **Detection speed**: The agent picks up the incident within minutes of the AppGW health alert firing.
- **Root cause via Activity Log**: The agent identifies *who* made the change and *what* changed by parsing the Activity Log.
- **Autonomous remediation**: The agent re-enables public network access (Selected networks) to restore service — using its Contributor role on the resource group.
- **RCA output**: The agent summarizes exactly what caused the issue and what steps were taken to remediate.
- **No human intervention**: From alert to resolution, the entire workflow is automated.

---

## Step 4: Post-Demo Wrap-up

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

| Alert                             | Type   | Severity | Status            | Trigger                                           |
| --------------------------------- | ------ | -------- | ----------------- | ------------------------------------------------- |
| **AppGW Unhealthy Backend** | Metric | Sev 1    | **Enabled** | `UnhealthyHostCount > 0` on Application Gateway |

This alert fires when the Application Gateway health probe (polling `/Health/Probe` every 30 seconds) detects that the backend Web App is unhealthy. In the demo scenario, this happens because the SQL health check fails after public network access is disabled.

---

## Troubleshooting

| Issue                                                    | Resolution                                                                                                                           |
| -------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `postprovision.ps1` fails on SQL firewall              | Ensure your public IP is reachable; try from a Codespace instead                                                                     |
| Health probe shows SQL FAIL after deployment             | Wait 1–2 minutes for the managed identity SQL user to take effect                                                                   |
| 502 not appearing after disabling SQL public access      | Wait several minutes — Azure control plane changes propagate slowly; the health probe refreshes its connection pool every 5 seconds |
| SRE Agent not created during deployment                  | Verify `azd provision` completed successfully; the SRE Agent is deployed via `infra/modules/sre-agent.bicep`                         |
| Incident action group `AadWebhookResourceNotOwnedByCaller` | The `preprovision.ps1` script should auto-clean stale action groups; if it recurs, manually delete the action group and re-run `azd provision` |
| SRE Agent shows no incidents                             | Ensure the incident response plan is created in the portal and set to Sev 1; verify the action group is wired to the alert rule     |
| `RoleAssignmentExists` errors during `azd provision` | Safe to ignore — the role assignments already exist from a previous deployment                                                      |
