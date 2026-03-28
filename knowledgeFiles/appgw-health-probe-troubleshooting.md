# Application Gateway Health Probe Troubleshooting Guide

> **Purpose**: Detailed guidance for diagnosing and resolving Application Gateway health probe failures in the MSFTLabs SRE Demo environment. Designed for Azure SRE Agent knowledge consumption.

---

## 1. Health Probe Configuration Reference

| Setting | Value |
|---|---|
| Probe Name | `webAppHealthProbe` |
| Protocol | HTTPS |
| Path | `/Health/Probe` |
| Interval | 30 seconds |
| Timeout | 30 seconds |
| Unhealthy Threshold | 3 consecutive failures |
| Host Name | Picked from backend HTTP settings (`pickHostNameFromBackendHttpSettings: true`) |
| Expected Status Codes | 200–399 |
| Backend Pool | Web App FQDN via HTTPS on port 443 |

The Application Gateway sends an HTTPS request to the Web App's `/Health/Probe` endpoint every 30 seconds. If 3 consecutive probes fail (non-2xx/3xx response or timeout), the backend is marked **unhealthy** and the gateway returns **502 Bad Gateway** to clients.

---

## 2. What the Health Probe Checks

The `/Health/Probe` endpoint (`src/web/Controllers/HealthController.cs`) performs:

| Check | How | Healthy Condition | Failure Response |
|---|---|---|---|
| SQL Connectivity | Opens a dedicated `SqlConnection` (5-second pool lifetime, `ApplicationName=HealthProbe`) and runs `SELECT COUNT(*) FROM SitePages` | Query returns successfully | HTTP 503 with `SqlHealthy = false` and `SqlError` message |

The probe returns **HTTP 200** when all checks pass and **HTTP 503** when any check fails. A 503 response falls outside the gateway's 200–399 match range, causing the probe to be counted as a failure.

---

## 3. Triage Workflow

When the `alert-appgw-unhealthy-backend` alert fires (or you observe 502 errors from the Application Gateway), follow this decision tree:

### Step 1: Confirm the Probe Is Actually Failing

Run this KQL query in Log Analytics:

```kql
AppServiceHTTPLogs
| where CsUriStem == "/Health/Probe"
| where TimeGenerated > ago(30m)
| project TimeGenerated, ScStatus, TimeTaken, CsHost
| order by TimeGenerated desc
```

- If `ScStatus == 200`: The probe is healthy; skip to [Step 6 (Network/Gateway Issues)](#step-6-check-network-and-gateway-configuration).
- If `ScStatus == 503`: The probe is failing due to an application-level check. Continue to Step 2.
- If **no rows returned**: The probe requests are not reaching the Web App at all. Skip to [Step 5 (Web App Availability)](#step-5-verify-web-app-is-running).

### Step 2: Identify Which Check Is Failing

Check Application Insights for the specific failure:

```kql
traces
| where timestamp > ago(30m)
| where message startswith "Health probe:"
| project timestamp, message
| order by timestamp desc
```

Look for the pattern: `Health probe: Overall=Unhealthy, SQL=Unhealthy`

This tells you which subsystem is failing.

### Step 3: Diagnose SQL Connectivity Failure

SQL is the most common cause of probe failure in this environment. Check for:

#### 3a. SQL Server Firewall Blocking Azure Services

The chaos trigger `/api/revoke-sql-access` deletes the `AllowAllAzureIps` firewall rule. Verify:

```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL"
| where Category == "Errors"
| where TimeGenerated > ago(1h)
| project TimeGenerated, Message
| order by TimeGenerated desc
```

**Verify via CLI:**
```bash
az sql server firewall-rule list --resource-group <rg-name> --server <sql-server-name> -o table
```

**Resolution:** Re-create the firewall rule:
```bash
az sql server firewall-rule create \
  --resource-group <rg-name> \
  --server <sql-server-name> \
  --name AllowAllAzureIps \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0
```

Or call the restore endpoint: `POST https://<function-app>/api/restore-sql-access`

#### 3b. Web App Managed Identity Not Authorized in SQL

If the managed identity SQL user was not created (e.g., `postprovision.ps1` failed at Step 2), the probe will get a login failure.

**Error signature in Application Insights:**
```
Microsoft.Data.SqlClient.SqlException: Login failed for user '<token-identified principal>'
```

**Resolution:** Manually create the SQL user. Obtain a SQL access token and run:
```sql
CREATE USER [<webAppName>] FROM EXTERNAL PROVIDER;
ALTER ROLE db_owner ADD MEMBER [<webAppName>];
```

#### 3c. SQL Database Unavailable or DTU Exhaustion

The database uses the Basic SKU (5 DTUs). Under extreme load, queries may time out.

**Check DTU usage:**
```kql
AzureMetrics
| where ResourceProvider == "MICROSOFT.SQL"
| where MetricName == "dtu_consumption_percent"
| where TimeGenerated > ago(1h)
| summarize avg(Average), max(Maximum) by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

**Resolution:** Scale the database to a higher tier via the Azure portal or CLI:
```bash
az sql db update --resource-group <rg-name> --server <sql-server-name> --name sredemodb --service-objective S0
```

#### 3d. SitePages Table Does Not Exist

If the database seed (`scripts/seed-db`) failed during provisioning, the `SitePages` table may not exist, causing `SELECT COUNT(*) FROM SitePages` to fail.

**Error signature:**
```
Microsoft.Data.SqlClient.SqlException: Invalid object name 'SitePages'
```

**Resolution:** Run the seed tool manually:
```bash
cd scripts/seed-db
dotnet run --no-launch-profile -- <sql-server>.database.windows.net sredemodb <access-token>
```

### Step 4: Check Application Insights Dependencies

```kql
dependencies
| where timestamp > ago(1h)
| where target has "database.windows.net" or type == "SQL"
| where success == false
| summarize count() by target, resultCode, bin(timestamp, 5m)
| order by timestamp desc
```

This shows the timeline and error codes for failed SQL calls, helping distinguish between intermittent and persistent failures.

### Step 5: Verify Web App Is Running

If the probe requests never reach the Web App:

1. **Check App Service status:**
   ```bash
   az webapp show --resource-group <rg-name> --name <webapp-name> --query "state" -o tsv
   ```
   Expected: `Running`

2. **Check for deployment failures:**
   ```kql
   AppServicePlatformLogs
   | where TimeGenerated > ago(1h)
   | where Level == "Error"
   | project TimeGenerated, Message
   | order by TimeGenerated desc
   ```

3. **Check if the app is crashing on startup:**
   ```kql
   AppServiceConsoleLogs
   | where TimeGenerated > ago(1h)
   | project TimeGenerated, ResultDescription
   | order by TimeGenerated desc
   | take 50
   ```

4. **Restart the Web App:**
   ```bash
   az webapp restart --resource-group <rg-name> --name <webapp-name>
   ```

### Step 6: Check Network and Gateway Configuration

If the probe shows healthy at the Web App but the gateway still reports unhealthy backends:

#### 6a. Backend Pool FQDN Mismatch

Verify the backend pool points to the correct Web App hostname:
```bash
az network application-gateway show --resource-group <rg-name> --name <appgw-name> \
  --query "backendAddressPools[0].backendAddresses[0].fqdn" -o tsv
```

Expected: `<webapp-name>.azurewebsites.net`

#### 6b. HTTPS Certificate Issues

The gateway connects to the Web App over HTTPS (port 443) using `pickHostNameFromBackendAddress`. If the Web App's TLS certificate is invalid or expired:
- The gateway probe fails with a TLS handshake error.
- The Web App logs may not show any probe requests.

**Resolution:** App Service managed certificates are auto-renewed. If using a custom certificate, check expiry:
```bash
az webapp config ssl list --resource-group <rg-name> --query "[].{Name:name, Expiry:expirationDate}" -o table
```

#### 6c. NSG or Subnet Blocking

The Application Gateway requires specific ports open on its subnet (`10.0.1.0/24`):
- Inbound: ports 65200–65535 (Azure infrastructure) and port 80 (frontend listener)
- Outbound: HTTPS to the Web App backend

Check that no NSG rules are blocking these:
```bash
az network nsg list --resource-group <rg-name> -o table
```

#### 6d. Application Gateway Stuck in Failed State

If the gateway shows a provisioning state other than `Succeeded`:
```bash
az network application-gateway show --resource-group <rg-name> --name <appgw-name> \
  --query "provisioningState" -o tsv
```

**Resolution:** If stuck in `Updating` or `Failed`, wait or stop/start the gateway:
```bash
az network application-gateway stop --resource-group <rg-name> --name <appgw-name>
az network application-gateway start --resource-group <rg-name> --name <appgw-name>
```

---

## 4. KQL Queries for Health Probe Investigation

### Probe Response Timeline (Last 2 Hours)

```kql
AppServiceHTTPLogs
| where CsUriStem == "/Health/Probe"
| where TimeGenerated > ago(2h)
| summarize
    HealthyCount = countif(ScStatus >= 200 and ScStatus < 400),
    UnhealthyCount = countif(ScStatus >= 400)
    by bin(TimeGenerated, 5m)
| order by TimeGenerated desc
```

### Correlate Probe Failures with SQL Errors

```kql
let probeFailures = AppServiceHTTPLogs
| where CsUriStem == "/Health/Probe" and ScStatus >= 500
| project ProbeTime = TimeGenerated;
let sqlErrors = AzureDiagnostics
| where ResourceProvider == "MICROSOFT.SQL" and Category == "Errors"
| project SqlErrorTime = TimeGenerated, Message;
probeFailures
| join kind=inner (sqlErrors) on $left.ProbeTime == $right.SqlErrorTime
| project ProbeTime, Message
| order by ProbeTime desc
```

### Application Gateway Backend Health Metric

```kql
AzureMetrics
| where ResourceProvider == "MICROSOFT.NETWORK"
| where MetricName == "UnhealthyHostCount"
| where TimeGenerated > ago(2h)
| project TimeGenerated, Average, Maximum
| order by TimeGenerated desc
```

### Health Probe Log Entries in Application Insights

```kql
traces
| where timestamp > ago(2h)
| where message startswith "Health probe:"
| extend OverallStatus = extract("Overall=([^,]+)", 1, message)
| extend SqlStatus = extract("SQL=([^,]+)", 1, message)
| project timestamp, OverallStatus, SqlStatus
| order by timestamp desc
```

---

## 5. Common Root Causes — Quick Reference

| Symptom | Most Likely Cause | Fix |
|---|---|---|
| Probe returns 503, SQL=Unhealthy | SQL firewall rule `AllowAllAzureIps` deleted | Re-create firewall rule or call `/api/restore-sql-access` |
| Probe returns 503, SQL login failed | Web App managed identity not in SQL DB | Run T-SQL: `CREATE USER [webAppName] FROM EXTERNAL PROVIDER; ALTER ROLE db_owner ADD MEMBER [webAppName];` |
| Probe returns 503, `Invalid object name 'SitePages'` | Database seed did not run | Run `dotnet run` in `scripts/seed-db` |
| No probe requests reaching Web App | Web App stopped or crashed | Check `az webapp show --query state`; restart if needed |
| Probe 200 but gateway still unhealthy | TLS handshake failure between gateway and backend | Verify backend FQDN and HTTPS settings; check certificate validity |
| Gateway returning 502 | Backend marked unhealthy after 3 failed probes | Identify and fix the underlying probe failure first; gateway recovers automatically within 30–90 seconds |
| Gateway in `Failed` provisioning state | Configuration update error or Azure platform issue | Stop and start the Application Gateway |
| Intermittent probe failures | SQL DTU exhaustion on Basic tier | Scale up the database SKU (e.g., Basic → S0) |

---

## 6. Recovery Verification

After applying a fix, verify recovery:

1. **Manually call the probe** to confirm it returns 200:
   ```bash
   curl -k https://<webapp-name>.azurewebsites.net/Health/Probe
   ```

2. **Wait for the gateway to re-probe** (up to 30 seconds for next probe, then 3 successful probes to mark healthy again — up to 90 seconds total).

3. **Confirm the gateway backend is healthy:**
   ```bash
   az network application-gateway show-backend-health \
     --resource-group <rg-name> --name <appgw-name> \
     --query "backendAddressPools[0].backendHttpSettingsCollection[0].servers[0].health" -o tsv
   ```
   Expected: `Healthy`

4. **Verify the alert auto-resolves** — the `alert-appgw-unhealthy-backend` metric alert evaluates every 1 minute over a 5-minute window. Once `UnhealthyHostCount` drops to 0, the alert resolves automatically.

5. **Test end-to-end through the gateway:**
   ```bash
   curl http://<appgw-fqdn>/
   ```
   Expected: HTTP 200 with the home page HTML.
