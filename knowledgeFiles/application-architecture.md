# MSFTLabs SRE Agent Demo -- Application Architecture and Operational Knowledge

> **Purpose**: This document is designed to be uploaded as a Knowledge File to Azure SRE Agent. It provides complete context about the application architecture, codebase, Azure resources, chaos engineering triggers, observability signals, and expected failure modes so that SRE Agent can accurately diagnose and remediate incidents in this environment.

---

## 1. Environment Overview

| Attribute | Value |
|---|---|
| Application Name | MSFTLabs SRE Demo |
| azd Project Name | `sre-agent-demo` |
| Resource Group Pattern | `rg-{environmentName}` |
| Deployment Tool | Azure Developer CLI (`azd up`) |
| Infrastructure as Code | Bicep (`infra/main.bicep`) |
| Target Subscription Scope | `subscription` |
| Resource Naming | Uses `uniqueString(subscription().id, environmentName, location)` token with standard abbreviation prefixes |

### How Deployment Works

1. `azd provision` deploys all Bicep modules (infra, networking, RBAC, diagnostics).
2. `scripts/postprovision.ps1` runs automatically after provisioning:
   - Generates random passwords for 11 demo users and stores them in Key Vault as secrets named `user-password-{username}`.
   - Adds a temporary SQL firewall rule for the deployer IP.
   - Creates the Web App managed identity as a `db_owner` SQL user in the `sredemodb` database.
   - Runs the `scripts/seed-db` .NET console tool to create the database schema (`Users`, `SitePages` tables) and seed demo data.
   - Removes the temporary deployer firewall rule.
3. `azd deploy` pushes the .NET web app and the Python Function App.
4. `scripts/postup.ps1` displays the Web App URL, App Gateway URL, and admin credentials (retrieved from Key Vault).

---

## 2. Azure Resources

All resources live inside a single resource group tagged with `azd-env-name`.

### 2.1 App Service Plan

| Property | Value |
|---|---|
| Bicep Module | `infra/modules/appservice.bicep` |
| SKU | B1 (Basic) |
| OS | Linux |
| Shared By | Web App and Function App (both use the same plan) |

### 2.2 Web App (.NET 8 / Linux)

| Property | Value |
|---|---|
| Bicep Module | `infra/modules/appservice.bicep` |
| Runtime | DOTNETCORE 8.0 on Linux |
| azd Service Name | `web` |
| Source Code | `src/web/` |
| Identity | System-assigned managed identity (enabled) |
| Always On | Yes |
| FTPS | Disabled |
| HTTPS Only | Yes |
| App Settings | `APPLICATIONINSIGHTS_CONNECTION_STRING`, `ApplicationInsightsAgent_EXTENSION_VERSION` (~3), `KeyVaultName`, `FunctionAppUrl`, `AppGatewayUrl` |
| Connection String | `DefaultConnection` -- connects to Azure SQL using `Authentication=Active Directory Default` (managed identity, no password) |
| Health Probe Endpoint | `/Health/Probe` (used by Application Gateway) |

**Managed identity permissions granted at deployment:**
- Key Vault Secrets User (`4633458b-17de-408a-b874-0445c86b69e6`) on the Key Vault -- allows reading secrets.
- SQL DB Contributor on the SQL Server (Azure RBAC).
- `db_owner` membership in the `sredemodb` database (created by `postprovision.ps1` via T-SQL `CREATE USER [webAppName] FROM EXTERNAL PROVIDER`).

### 2.3 Function App (Python 3.11 / Linux)

| Property | Value |
|---|---|
| Bicep Module | `infra/modules/functionapp.bicep` |
| Runtime | Python 3.11 on Linux (Functions v4) |
| azd Service Name | `api` |
| Source Code | `src/api/` |
| Entry Point | `src/api/function_app.py` |
| Identity | System-assigned managed identity (enabled) |
| HTTP Auth Level | Anonymous (all routes) |
| App Settings | `APPLICATIONINSIGHTS_CONNECTION_STRING`, `KeyVaultName`, `AZURE_SUBSCRIPTION_ID`, `RESOURCE_GROUP_NAME`, `WEBAPP_PRINCIPAL_ID`, `SQL_SERVER_NAME`, `APP_GATEWAY_URL` |
| Storage Account | Dedicated `StorageV2 / Standard_LRS` for `AzureWebJobsStorage` |

**Managed identity permissions granted at deployment (for chaos management):**
- Key Vault Secrets User on the Key Vault.
- User Access Administrator (`18d7d88d-d35e-4fb5-a5c3-7773c20a72d9`) on the resource group -- allows the Function App to add/remove RBAC role assignments for chaos scenarios.
- SQL Server Contributor (`6d8ee4ec-f05a-4a1d-8b00-a9b17e38b437`) on the resource group -- allows the Function App to manage SQL Server firewall rules for chaos scenarios.

**Python Dependencies** (`src/api/requirements.txt`):
- `azure-functions`
- `azure-identity`
- `azure-mgmt-authorization`
- `azure-mgmt-sql`

### 2.4 Azure SQL Database

| Property | Value |
|---|---|
| Bicep Module | `infra/modules/sql.bicep` |
| Server Authentication | Entra ID only (`azureADOnlyAuthentication: true`) -- no SQL password auth |
| Database Name | `sredemodb` |
| SKU | Basic |
| TLS | 1.2 minimum |
| Auditing | Enabled, Azure Monitor target |
| Threat Protection | Enabled |
| Firewall Rule | `AllowAllAzureIps` (0.0.0.0 -- 0.0.0.0) -- allows Azure services to connect |

**Database Schema:**

**Table: `Users`**

| Column | Type | Notes |
|---|---|---|
| Id | INT IDENTITY PK | Auto-increment |
| Username | NVARCHAR(50) | Unique index |
| Email | NVARCHAR(256) | Unique index |
| PasswordHash | NVARCHAR(MAX) | BCrypt hashed |
| FirstName | NVARCHAR(50) | |
| LastName | NVARCHAR(50) | |
| DisplayName | NVARCHAR(100) | |
| Bio | NVARCHAR(500) | |
| Role | NVARCHAR(20) | "Admin" or "User" |
| CreatedAt | DATETIME2 | UTC |
| LastLoginAt | DATETIME2 | Nullable |

**Table: `SitePages`**

| Column | Type | Notes |
|---|---|---|
| Id | INT IDENTITY PK | Auto-increment |
| Slug | NVARCHAR(100) | Unique index, used in URL routing |
| Title | NVARCHAR(200) | |
| Content | NVARCHAR(MAX) | HTML content |
| Summary | NVARCHAR(500) | |
| Category | NVARCHAR(50) | "SRE Concepts", "Security", etc. |
| SortOrder | INT | Display ordering |
| IsActive | BIT | Soft-delete flag |
| CreatedAt | DATETIME2 | UTC |
| UpdatedAt | DATETIME2 | Nullable |

**Seeded Data:**
- 11 user accounts: 1 admin (`admin`, Role=Admin) and 10 standard users (jmorales, akovacs, schen, bmurphy, pnakamura, dwilliams, lpetrova, rsingh, efischer, okim). Passwords are generated randomly and stored in Key Vault as `user-password-{username}`.
- 6 site pages covering: Monitoring Fundamentals, Incident Response, Managed Identity Security, WAF and Network Security, Chaos Engineering, Service-Level Objectives.

### 2.5 Azure Key Vault

| Property | Value |
|---|---|
| Bicep Module | `infra/modules/keyvault.bicep` |
| SKU | Standard |
| Authorization Model | RBAC (`enableRbacAuthorization: true`) |
| Soft Delete | Enabled (7-day retention) |

**Secrets stored at deployment:**

| Secret Name | Purpose |
|---|---|
| `sql-connection-string` | Azure SQL connection string using Active Directory Default auth |
| `appinsights-connection-string` | Application Insights connection string |
| `demo-secret` | Test secret for health probe and integration page verification (`SRE-Demo-Active-{uniqueString}`) |
| `user-password-admin` | Admin account password (random, generated by postprovision.ps1) |
| `user-password-jmorales` | User password (random) |
| `user-password-akovacs` | User password (random) |
| `user-password-schen` | User password (random) |
| `user-password-bmurphy` | User password (random) |
| `user-password-pnakamura` | User password (random) |
| `user-password-dwilliams` | User password (random) |
| `user-password-lpetrova` | User password (random) |
| `user-password-rsingh` | User password (random) |
| `user-password-efischer` | User password (random) |
| `user-password-okim` | User password (random) |

### 2.6 Application Gateway with WAF

| Property | Value |
|---|---|
| Bicep Module | `infra/modules/appgateway.bicep` |
| SKU | WAF_v2, capacity 1 |
| WAF Mode | Prevention |
| Managed Rule Set | OWASP 3.2 |
| Frontend | Public IP (Standard SKU, static) with DNS label |
| Backend Pool | Web App FQDN via HTTPS (port 443) with `pickHostNameFromBackendAddress` |
| Listener | HTTP on port 80 |
| Health Probe | HTTPS to `/Health/Probe` every 30 seconds, unhealthy threshold 3 |
| VNet | `10.0.0.0/16`, app gateway subnet `10.0.1.0/24` |
| Diagnostics | All logs and all metrics sent to Log Analytics |

When the WAF blocks a request, it returns HTTP 403 and logs the event to Log Analytics. The WAF log entries include the matched rule ID, the request URI, and the action taken.

### 2.7 Log Analytics Workspace

| Property | Value |
|---|---|
| Bicep Module | `infra/modules/monitoring.bicep` |
| SKU | PerGB2018 |
| Retention | 30 days |

### 2.8 Application Insights

| Property | Value |
|---|---|
| Bicep Module | `infra/modules/monitoring.bicep` |
| Type | Web |
| Backed By | Log Analytics Workspace |
| Sampling | Enabled (excludes Request type) |

---

## 3. Observability and Diagnostics

All diagnostic settings are defined in `infra/modules/diagnostics.bicep`. Every resource sends logs and metrics to the shared Log Analytics workspace.

| Resource | Log Categories Enabled | Metrics |
|---|---|---|
| Web App | AppServiceHTTPLogs, AppServiceConsoleLogs, AppServiceAppLogs, AppServicePlatformLogs | AllMetrics |
| Function App | FunctionAppLogs | AllMetrics |
| Key Vault | AuditEvent | AllMetrics |
| SQL Database | Errors | Basic |
| Storage Account (Blob) | StorageRead, StorageWrite, StorageDelete | Transaction |
| Application Gateway | allLogs (categoryGroup) | AllMetrics |

### Key Telemetry Signals to Monitor

| Signal | Source | Meaning |
|---|---|---|
| Spike in `exceptions` table | Application Insights | Unhandled exceptions in web app or function app |
| Elevated `requests` with `resultCode >= 500` | Application Insights | Server errors |
| `dependencies` failures | Application Insights | Failed calls to SQL, Key Vault, or external services |
| `AzureDiagnostics` with `Category == "ApplicationGatewayFirewallLog"` | Log Analytics | WAF blocked requests |
| `AuditEvent` from Key Vault | Log Analytics | Secret access attempts (successful or denied) |
| `FunctionAppLogs` with `Level == "Error"` | Log Analytics | Function App errors including chaos trigger logs |
| SQL `Errors` category | Log Analytics | Database-level errors including connectivity failures |

---

## 4. Web Application Architecture (src/web/)

### 4.1 Technology Stack

- **Framework**: ASP.NET Core 8.0 (MVC pattern)
- **ORM**: Entity Framework Core with SQL Server provider
- **Authentication**: Cookie-based authentication (`CookieAuthenticationDefaults`)
  - Login path: `/Account/Login`
  - Expiration: 2 hours (sliding)
- **Session**: Cookie-based session (`.SreDemo.Session`, 30-minute idle timeout)
- **Key Vault SDK**: `Azure.Security.KeyVault.Secrets.SecretClient` via `DefaultAzureCredential`
- **Password Hashing**: BCrypt.Net
- **HTTP Client**: IHttpClientFactory pattern

### 4.2 Application Startup (Program.cs)

1. Adds Application Insights telemetry.
2. Creates `SecretClient` singleton pointing to Key Vault using `DefaultAzureCredential` (managed identity in Azure, developer credentials locally).
3. Configures EF Core `ApplicationDbContext` with SQL Server connection string from `DefaultConnection` (using Active Directory Default auth).
4. Registers cookie authentication and session middleware.
5. Registers `IHttpClientFactory` and MVC controllers with views.
6. Middleware order: ExceptionHandler, HTTPS Redirect, Static Files, Routing, Session, Authentication, Authorization.

### 4.3 Controllers

#### HomeController (Public)
- `GET /` -- Home page with embedded YouTube video and SRE Agent feature list.
- `GET /Home/AboutSre` -- Static page about Azure SRE with links to Microsoft Learn.
- `GET /content/{slug}` -- Dynamic content pages loaded from `SitePages` table by slug. Returns 404 if slug not found or page inactive.
- `GET /Home/ContentIndex` -- Lists all active site pages ordered by `SortOrder`.
- `GET /Home/Error` -- Error page with request ID for correlation.

#### AccountController (Public)
- `GET /Account/Login` -- Login form. Also retrieves the admin password from Key Vault secret `user-password-admin` and displays it as demo credentials on the login page.
- `POST /Account/Login` -- Authenticates against `Users` table using BCrypt password verification. Creates claims identity with Username, Email, DisplayName, Role. Sets session `LoginTime`.
- `GET /Account/Register` -- Registration form (creates new User accounts).
- `POST /Account/Logout` -- Signs out and clears session.

#### DashboardController (Requires Authentication)
- `GET /Dashboard` -- Server metrics dashboard: machine name, UTC time, memory usage (MB), process uptime, thread count, environment name, total user count, .NET runtime version. Shows login time from session.
- `GET /Dashboard/Profile` -- Edit form for FirstName, LastName, Email, Bio, and password reset.
- `POST /Dashboard/Profile` -- Saves profile changes, validates unique email constraint.
- `GET /Dashboard/Settings` -- Settings placeholder page.
- `GET /Dashboard/Integration` -- **Critical for SRE demos**: Tests and displays Key Vault connectivity (reads `demo-secret`) and SQL connectivity (counts users). Shows connection status and error messages when access is disrupted.

#### AdminController (Requires Authentication + Admin Role)
- `GET /Admin` -- Admin panel with a single "Trigger SQL Injection Attack" button. Only visible to users with `Role == "Admin"`.
- `POST /Admin/TriggerSqlInjection` -- Sends 5 SQL injection / XSS / path traversal patterns directly to the Application Gateway URL (`AppGatewayUrl` app setting) from the Web App. Returns JSON with `{totalPatterns, blockedCount, results[]}`. The button on the Admin page calls this endpoint via AJAX (with CSRF token). This is the **primary demo trigger** -- no Function App involvement.

#### HealthController (Public)
- `GET /Health/Probe` -- Comprehensive health check used by Application Gateway. Tests:
  1. **Managed Identity / Key Vault**: Reads `demo-secret` from Key Vault via `SecretClient`.
  2. **SQL Connectivity**: Counts rows in `Users` table via EF Core.
  3. **Function App API**: Calls `GET {FunctionAppUrl}/api/health` and checks for 200 response.
  - Returns overall health status combining all three checks.

### 4.4 Data Models

| Model | File | Purpose |
|---|---|---|
| `User` | `Models/User.cs` | User entity: Id, Username (unique), Email (unique), PasswordHash (BCrypt), FirstName, LastName, DisplayName, Bio, Role ("Admin"/"User"), CreatedAt, LastLoginAt |
| `SitePage` | `Models/SitePage.cs` | CMS content: Id, Slug (unique), Title, Content (HTML), Summary, Category, SortOrder, IsActive, CreatedAt, UpdatedAt |
| `DashboardViewModel` | `Models/DashboardViewModel.cs` | Server metrics for dashboard display |
| `IntegrationViewModel` | `Models/IntegrationViewModel.cs` | Key Vault and SQL connectivity status |
| `HealthProbeViewModel` | `Models/HealthProbeViewModel.cs` | Health check results for all three subsystems |
| `LoginViewModel` | `Models/LoginViewModel.cs` | Login form binding |
| `RegisterViewModel` | `Models/RegisterViewModel.cs` | Registration form binding |
| `ProfileEditViewModel` | `Models/ProfileEditViewModel.cs` | Profile edit form binding |
| `ErrorViewModel` | `Models/ErrorViewModel.cs` | Error page with RequestId |

### 4.5 Database Context

`Data/ApplicationDbContext.cs` defines:
- `DbSet<User> Users` with unique indexes on Username and Email.
- `DbSet<SitePage> SitePages` with unique index on Slug.

`Data/DbInitializer.cs` seeds users (reading passwords from Key Vault) and site pages on first run.

---

## 5. Function App API -- Chaos Engineering Endpoints (src/api/)

The Function App serves two purposes:
1. Health check endpoint for monitoring.
2. Chaos engineering endpoints for triggering demo failure scenarios.

All endpoints use `AuthLevel.ANONYMOUS` and are HTTP-triggered.

### 5.1 Health and Observability

| Endpoint | Method | Description |
|---|---|---|
| `/api/health` | GET | Returns `{"status":"healthy","timestamp":...}` with HTTP 200 |

### 5.2 Application Fault Injection

| Endpoint | Method | Parameters | Failure Mode |
|---|---|---|---|
| `/api/trigger-exception` | POST | `type` = null_reference, division, timeout, memory, key_error, general | Throws unhandled exceptions of various types. Generates entries in Application Insights `exceptions` table. |
| `/api/trigger-slow-response` | POST | `delay` (seconds, max 230) | Blocks the response for the specified duration. Creates latency anomalies in Application Insights `requests` table. |
| `/api/trigger-memory-leak` | POST | `size` (MB, max 500) | Allocates byte arrays to simulate memory pressure. Visible in process memory metrics. |
| `/api/trigger-cpu-spike` | POST | `duration` (seconds, max 60) | Runs CPU-intensive computation loop. Visible in CPU utilization metrics. |
| `/api/trigger-dependency-failure` | POST | (none) | Attempts HTTP request to non-existent service. Creates failed dependency entries in Application Insights. |
| `/api/trigger-error-storm` | POST | `count` (max 200) | Logs burst of `ERROR` level messages with correlation IDs. Visible in `FunctionAppLogs` and Application Insights `traces`. |
| `/api/trigger-log-flood` | POST | `count` (max 5000), `level` | Floods logs at specified level. Tests log pipeline capacity. |

### 5.3 RBAC / Access Chaos (Managed Identity Disruption)

These endpoints modify actual Azure RBAC assignments and firewall rules, creating real production-like failures.

| Endpoint | Method | What It Does | Expected Web App Impact |
|---|---|---|---|
| `/api/revoke-keyvault-access` | POST | Removes the Web App's `Key Vault Secrets User` role assignment from the Key Vault. | Web App can no longer read secrets from Key Vault. The `/Dashboard/Integration` page shows Key Vault disconnected. The `/Health/Probe` endpoint reports managed identity unhealthy. Login page cannot display demo credentials. |
| `/api/restore-keyvault-access` | POST | Re-creates the `Key Vault Secrets User` role assignment for the Web App managed identity. Uses deterministic UUID (uuid5) to avoid duplicate assignments. | Web App regains access to Key Vault secrets. All pages resume normal operation. |
| `/api/revoke-sql-access` | POST | Deletes the SQL Server firewall rule `AllowAllAzureIps`. | Web App cannot connect to Azure SQL. All pages that query the database fail. The `/Health/Probe` endpoint reports SQL unhealthy. Dashboard, Content pages, Login all break. |
| `/api/restore-sql-access` | POST | Re-creates the `AllowAllAzureIps` firewall rule (0.0.0.0 -- 0.0.0.0). | Web App regains SQL connectivity. |
| `/api/trigger-waf-sql-injection` | POST | Sends 5 malicious request patterns (SQL injection, XSS, path traversal) through the Application Gateway URL. | WAF blocks the requests (HTTP 403). Generates WAF firewall log entries in Log Analytics. Does not directly impact the web app, but creates security telemetry signals. |

**Environment variables required by chaos endpoints** (set automatically via Bicep):
- `AZURE_SUBSCRIPTION_ID` -- The subscription ID.
- `RESOURCE_GROUP_NAME` -- The resource group name.
- `WEBAPP_PRINCIPAL_ID` -- The Web App managed identity principal ID.
- `KeyVaultName` -- The Key Vault name.
- `SQL_SERVER_NAME` -- The SQL Server name (without `.database.windows.net`).
- `APP_GATEWAY_URL` -- The Application Gateway HTTP URL for WAF testing.

---

## 6. RBAC Role Assignments Summary

| Principal | Role | Scope | Purpose |
|---|---|---|---|
| Web App Managed Identity | Key Vault Secrets User | Key Vault | Read secrets (connection strings, demo secret, passwords) |
| Web App Managed Identity | SQL DB Contributor | SQL Server | Azure RBAC level SQL access |
| Web App Managed Identity | db_owner | SQL Database (sredemodb) | Database-level read/write (set via T-SQL) |
| Function App Managed Identity | Key Vault Secrets User | Key Vault | Read secrets |
| Function App Managed Identity | User Access Administrator | Resource Group | Manage role assignments for chaos scenarios |
| Function App Managed Identity | SQL Server Contributor | Resource Group | Manage SQL firewall rules for chaos scenarios |
| Deployer (Entra ID user) | Key Vault Secrets Officer | Key Vault | Write passwords during postprovision |
| Deployer (Entra ID user) | SQL Entra AD Admin | SQL Server | Create database users during postprovision |

---

## 7. Chaos Scenario Playbook for SRE Agent

### Scenario 1: Key Vault Access Revocation

**Trigger**: POST to `/api/revoke-keyvault-access`

**What happens at the Azure level**: The Web App's `Key Vault Secrets User` role assignment is deleted from the Key Vault.

**Symptoms SRE Agent should detect**:
- Application Insights `exceptions`: `Azure.RequestFailedException` or `Azure.Identity.AuthenticationFailedException` from the Web App when trying to read Key Vault secrets.
- Key Vault `AuditEvent` logs: Access denied events for the Web App's managed identity.
- Health probe failures at `/Health/Probe` -- managed identity check fails.
- Application Gateway may start flagging the backend as unhealthy if the health probe returns non-200.
- Web App `AppServiceAppLogs`: Error-level log entries from `HealthController`, `DashboardController`, `AccountController` about failed Key Vault reads.

**Root cause**: Missing RBAC role assignment -- `Key Vault Secrets User` role removed from Web App managed identity on the Key Vault.

**Remediation**: Restore the `Key Vault Secrets User` role assignment for the Web App managed identity on the Key Vault. Or call POST `/api/restore-keyvault-access`.

---

### Scenario 2: SQL Database Access Revocation

**Trigger**: POST to `/api/revoke-sql-access`

**What happens at the Azure level**: The SQL Server firewall rule `AllowAllAzureIps` is deleted, blocking all Azure service connections.

**Symptoms SRE Agent should detect**:
- Application Insights `exceptions`: `Microsoft.Data.SqlClient.SqlException` with connection timeout or network unreachable errors.
- Application Insights `dependencies`: Failed SQL dependency calls with long durations (timeouts).
- Health probe failures at `/Health/Probe` -- SQL check fails.
- Web App `AppServiceAppLogs`: Error-level entries from Entity Framework about SQL connection failures.
- Dashboard, Content, Login, and Profile pages all fail or return 500 errors.

**Root cause**: SQL Server firewall rule `AllowAllAzureIps` was deleted -- Azure services can no longer reach the SQL Server.

**Remediation**: Re-create the firewall rule `AllowAllAzureIps` with start/end IP `0.0.0.0`. Or call POST `/api/restore-sql-access`.

---

### Scenario 3: WAF SQL Injection Blocking (PRIMARY DEMO SCENARIO)

**Trigger**: Click "Trigger SQL Injection Attack" on the Admin page (calls `POST /Admin/TriggerSqlInjection` on the Web App), or alternatively `POST /api/trigger-waf-sql-injection` on the Function App.

**What happens at the Azure level**: Five HTTP requests with SQL injection, XSS, and path traversal patterns are sent from the Web App through the Application Gateway.

**Symptoms SRE Agent should detect**:
- Log Analytics WAF firewall logs: `ApplicationGatewayFirewallLog` entries with `action == "Blocked"`, matched OWASP rule IDs.
- Application Gateway metrics: Increase in blocked request count.
- No direct impact on web app health -- the WAF correctly blocks the malicious requests before they reach the backend.

**Root cause**: Malicious or suspicious request patterns detected by OWASP 3.2 WAF rules.

**Analysis**: SRE Agent should classify these as security events (not application failures). The WAF is functioning as expected. Investigate the source of the injection attempts.

---

### Scenario 4: Application Exceptions

**Trigger**: POST to `/api/trigger-exception?type={type}`

**Symptoms**: Spike in Application Insights `exceptions` table. Exception types include NullReferenceError, ZeroDivisionError, TimeoutError, MemoryError, KeyError, RuntimeError.

---

### Scenario 5: Latency Injection

**Trigger**: POST to `/api/trigger-slow-response?delay={seconds}`

**Symptoms**: Requests in Application Insights with abnormally high duration. May trigger timeout alerts.

---

### Scenario 6: Resource Pressure (Memory / CPU)

**Trigger**: POST to `/api/trigger-memory-leak?size={mb}` or `/api/trigger-cpu-spike?duration={seconds}`

**Symptoms**: Elevated memory consumption or CPU utilization in App Service metrics. May trigger autoscale alerts or performance degradation.

---

### Scenario 7: Error Storm

**Trigger**: POST to `/api/trigger-error-storm?count={n}`

**Symptoms**: Burst of error-level log entries in `FunctionAppLogs`. Each entry has a correlation ID (`storm_{i}`). Application Insights `traces` table shows rapid error accumulation.

---

## 8. Important URLs and Endpoints

| Endpoint | Protocol | Purpose |
|---|---|---|
| `https://{webAppName}.azurewebsites.net` | HTTPS | Direct Web App access |
| `http://{appGatewayFqdn}` | HTTP | Application Gateway (WAF-protected) frontend |
| `https://{functionAppName}.azurewebsites.net/api/{endpoint}` | HTTPS | Function App API endpoints |
| `/Health/Probe` | HTTPS | Application Gateway health probe target |
| `/Dashboard/Integration` | HTTPS | Key Vault + SQL connectivity status page |
| `/Admin` | HTTPS | Chaos trigger control panel (admin only) |

---

## 9. Key Configuration Files

| File | Purpose |
|---|---|
| `azure.yaml` | azd project definition: services (`web`=appservice/.NET, `api`=function/Python), hooks (postprovision, postup) |
| `infra/main.bicep` | Orchestrates all Bicep modules, defines outputs |
| `infra/main.parameters.json` | Parameters: `environmentName`, `location`, `sqlAadAdminObjectId`, `sqlAadAdminLogin` |
| `src/web/appsettings.json` | Web app config: logging levels, Application Insights placeholder |
| `src/web/Program.cs` | ASP.NET Core startup: DI registration, middleware pipeline |
| `src/api/function_app.py` | All Function App endpoints (health, chaos triggers) |
| `src/api/host.json` | Functions runtime config: logging, sampling, extension bundle |
| `src/api/requirements.txt` | Python dependencies |
| `scripts/postprovision.ps1` | Post-provision automation: passwords, SQL access, seed data |
| `scripts/postup.ps1` | Post-deploy display: URLs and admin credentials |

---

## 10. Naming Conventions

All Azure resource names follow this pattern:
```
{abbreviation}{resourceToken}
```

Where:
- `{abbreviation}` comes from `infra/abbreviations.json` (e.g., `kv-` for Key Vault, `sql-` for SQL Server, `app-` for Web App, `func-` for Function App).
- `{resourceToken}` is `toLower(uniqueString(subscription().id, environmentName, location))`.

---

## 11. Known Failure Signatures

When troubleshooting, look for these specific error patterns:

| Error Signature | Likely Root Cause |
|---|---|
| `Azure.RequestFailedException: Caller is not authorized` from Web App | Key Vault Secrets User role removed from Web App managed identity |
| `Microsoft.Data.SqlClient.SqlException: Cannot open server` | SQL firewall rule AllowAllAzureIps deleted |
| `Microsoft.Data.SqlClient.SqlException: Login failed for user` | Web App managed identity not added as SQL user (db_owner) |
| WAF logs with OWASP rule matches and `action=Blocked` | SQL injection or XSS patterns in requests through Application Gateway |
| Application Gateway backend unhealthy | Health probe at `/Health/Probe` failing due to Key Vault or SQL issues |
| `FunctionAppLogs` with `Error storm event` messages | Intentional chaos trigger -- not a real incident |
| `TimeoutError: Simulated database connection timeout` in Function App | Intentional chaos trigger via `/api/trigger-exception?type=timeout` |
| Elevated Function App response times (>10s) | Intentional chaos trigger via `/api/trigger-slow-response` |

---

## 12. KQL Queries for Common Investigations

### Unhandled Exceptions (Last 1 Hour)
```kql
exceptions
| where timestamp > ago(1h)
| summarize count() by type, outerMessage
| order by count_ desc
```

### Failed Dependencies (SQL, Key Vault)
```kql
dependencies
| where timestamp > ago(1h) and success == false
| summarize count() by target, type, resultCode
| order by count_ desc
```

### WAF Blocked Requests
```kql
AzureDiagnostics
| where Category == "ApplicationGatewayFirewallLog"
| where action_s == "Blocked"
| project TimeGenerated, ruleId_s, requestUri_s, message_s, hostname_s
| order by TimeGenerated desc
```

### Health Probe Failures
```kql
AppServiceHTTPLogs
| where CsUriStem == "/Health/Probe"
| where ScStatus >= 500
| project TimeGenerated, ScStatus, TimeTaken, CsHost
| order by TimeGenerated desc
```

### Function App Error Logs
```kql
FunctionAppLogs
| where Level == "Error" or Level == "Critical"
| project TimeGenerated, FunctionName, Message, ExceptionDetails
| order by TimeGenerated desc
```

### Key Vault Access Denied Events
```kql
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where ResultSignature == "Forbidden" or httpStatusCode_d == 403
| project TimeGenerated, OperationName, CallerIPAddress, identity_claim_upn_s
| order by TimeGenerated desc
```

---

## 13. Architecture Diagram

```
Internet
    |
    v
[Application Gateway WAF_v2]  <-- OWASP 3.2 Prevention Mode
    |  (HTTP :80 -> HTTPS :443)
    v
[App Service Plan B1 Linux]
    |
    +---> [Web App .NET 8]  -----> [Azure SQL (sredemodb)]
    |         |                         ^
    |         +---> [Key Vault] <-------+-- managed identity auth
    |         |                         |
    |         +---> [App Insights] ---> [Log Analytics Workspace]
    |         |
    |         +---> POST /Admin/TriggerSqlInjection
    |                   |  (sends SQL injection patterns)
    |                   v
    |              [Application Gateway WAF] ---> BLOCKED (403)
    |                   |  (WAF firewall logs)
    |                   v
    |              [Log Analytics] ---> [Azure Monitor Alert]
    |                                        |
    |                                        v
    |                                   [SRE Agent investigates]
    |
    +---> [Function App Python 3.11]
              |
              +---> Chaos: revoke/restore KV RBAC
              +---> Chaos: revoke/restore SQL firewall
              +---> Chaos: WAF SQL injection test (alternative)
              +---> Chaos: exceptions, latency, CPU, memory
              +---> [Storage Account] (WebJobs)
```

All resources send diagnostic logs and metrics to the shared Log Analytics Workspace. Application Insights is backed by the same workspace, providing unified telemetry for the Web App and Function App.
