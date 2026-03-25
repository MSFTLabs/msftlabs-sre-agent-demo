using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;

// Usage: dotnet run -- <sqlFqdn> <dbName> <accessToken> <kvName>
// Reads passwords from Key Vault via az CLI, hashes with BCrypt, creates schema and seeds data.

if (args.Length < 4)
{
    Console.Error.WriteLine("Usage: dotnet run -- <sqlFqdn> <dbName> <accessToken> <kvName>");
    return 1;
}

var sqlFqdn = args[0];
var dbName = args[1];
var accessToken = args[2];
var kvName = args[3];

var connStr = $"Server=tcp:{sqlFqdn},1433;Initial Catalog={dbName};Encrypt=True;TrustServerCertificate=False;Connection Timeout=60;";

using var conn = new SqlConnection(connStr);
conn.AccessToken = accessToken;
conn.Open();
Console.WriteLine($"Connected to {sqlFqdn}/{dbName}");

// ---------- Create schema ----------
ExecuteNonQuery(conn, @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'Users')
CREATE TABLE [Users] (
    [Id]          INT            IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [Username]    NVARCHAR(50)   NOT NULL,
    [Email]       NVARCHAR(256)  NOT NULL,
    [PasswordHash] NVARCHAR(MAX) NOT NULL,
    [FirstName]   NVARCHAR(50)   NOT NULL DEFAULT '',
    [LastName]    NVARCHAR(50)   NOT NULL DEFAULT '',
    [DisplayName] NVARCHAR(100)  NOT NULL DEFAULT '',
    [Bio]         NVARCHAR(500)  NOT NULL DEFAULT '',
    [Role]        NVARCHAR(20)   NOT NULL DEFAULT 'User',
    [CreatedAt]   DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    [LastLoginAt] DATETIME2      NULL
);
");

ExecuteNonQuery(conn, @"
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Users_Username')
    CREATE UNIQUE INDEX IX_Users_Username ON [Users]([Username]);
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Users_Email')
    CREATE UNIQUE INDEX IX_Users_Email ON [Users]([Email]);
");

ExecuteNonQuery(conn, @"
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'SitePages')
CREATE TABLE [SitePages] (
    [Id]        INT            IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [Slug]      NVARCHAR(100)  NOT NULL,
    [Title]     NVARCHAR(200)  NOT NULL,
    [Content]   NVARCHAR(MAX)  NOT NULL,
    [Summary]   NVARCHAR(500)  NOT NULL DEFAULT '',
    [Category]  NVARCHAR(50)   NOT NULL DEFAULT 'General',
    [SortOrder] INT            NOT NULL DEFAULT 0,
    [IsActive]  BIT            NOT NULL DEFAULT 1,
    [CreatedAt] DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME(),
    [UpdatedAt] DATETIME2      NULL
);
");

ExecuteNonQuery(conn, @"
IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_SitePages_Slug')
    CREATE UNIQUE INDEX IX_SitePages_Slug ON [SitePages]([Slug]);
");

Console.WriteLine("Schema created.");

// ---------- Seed users ----------
if (CountRows(conn, "Users") == 0)
{
    Console.WriteLine("Seeding users...");
    var users = new (string username, string email, string first, string last, string display, string role, string bio)[]
    {
        ("admin",      "admin@msftlabs.org",      "SRE",     "Administrator", "SRE Administrator",  "Admin", "Platform reliability engineer and demo environment administrator."),
        ("jmorales",   "jmorales@msftlabs.org",   "Juan",    "Morales",       "Juan Morales",        "User",  "Cloud solutions architect focused on resilience patterns."),
        ("akovacs",    "akovacs@msftlabs.org",    "Andrea",  "Kovacs",        "Andrea Kovacs",       "User",  "Site reliability engineer specializing in observability."),
        ("schen",      "schen@msftlabs.org",      "Sophia",  "Chen",          "Sophia Chen",         "User",  "DevOps lead with deep experience in incident management."),
        ("bmurphy",    "bmurphy@msftlabs.org",    "Brian",   "Murphy",        "Brian Murphy",        "User",  "Infrastructure engineer working on Azure landing zones."),
        ("pnakamura",  "pnakamura@msftlabs.org",  "Priya",   "Nakamura",      "Priya Nakamura",      "User",  "Application performance analyst and monitoring specialist."),
        ("dwilliams",  "dwilliams@msftlabs.org",  "Daniel",  "Williams",      "Daniel Williams",     "User",  "Security-focused SRE with background in threat modeling."),
        ("lpetrova",   "lpetrova@msftlabs.org",   "Lena",    "Petrova",       "Lena Petrova",        "User",  "Database reliability engineer managing SQL and Cosmos DB fleets."),
        ("rsingh",     "rsingh@msftlabs.org",     "Raj",     "Singh",         "Raj Singh",           "User",  "Automation engineer building self-healing infrastructure."),
        ("efischer",   "efischer@msftlabs.org",   "Ema",     "Fischer",       "Ema Fischer",         "User",  "Capacity planning lead focused on cost-effective scaling."),
        ("okim",       "okim@msftlabs.org",       "Oliver",  "Kim",           "Oliver Kim",          "User",  "Incident responder and chaos engineering practitioner."),
    };

    foreach (var u in users)
    {
        var password = ReadPassword(kvName, u.username);
        var hash = BCrypt.Net.BCrypt.HashPassword(password);
        InsertUser(conn, u.username, u.email, hash, u.first, u.last, u.display, u.role, u.bio);
        Console.WriteLine($"  [seeded] {u.username}");
    }
}
else
{
    Console.WriteLine("Users table already has data - skipping user seed.");
}

// ---------- Seed site pages ----------
if (CountRows(conn, "SitePages") == 0)
{
    Console.WriteLine("Seeding site pages...");
    var pages = GetSitePages();
    foreach (var p in pages)
    {
        InsertPage(conn, p.slug, p.title, p.content, p.summary, p.category, p.sortOrder);
        Console.WriteLine($"  [seeded] {p.slug}");
    }
}
else
{
    Console.WriteLine("SitePages table already has data - skipping page seed.");
}

Console.WriteLine("Database seed complete.");
return 0;

// ========== Helpers ==========

static string ReadPassword(string kvName, string username)
{
    var secretName = $"user-password-{username}";
    var psi = new System.Diagnostics.ProcessStartInfo
    {
        FileName = System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(
                       System.Runtime.InteropServices.OSPlatform.Windows) ? "cmd.exe" : "az",
        Arguments = System.Runtime.InteropServices.RuntimeInformation.IsOSPlatform(
                        System.Runtime.InteropServices.OSPlatform.Windows)
            ? $"/c az keyvault secret show --vault-name {kvName} --name {secretName} --query value -o tsv"
            : $"keyvault secret show --vault-name {kvName} --name {secretName} --query value -o tsv",
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        UseShellExecute = false
    };
    using var proc = System.Diagnostics.Process.Start(psi)!;
    var output = proc.StandardOutput.ReadToEnd().Trim();
    proc.WaitForExit();
    if (proc.ExitCode != 0 || string.IsNullOrEmpty(output))
    {
        Console.WriteLine($"  [warn] Could not read KV secret for {username}, using fallback");
        return $"LocalDev!{username}2026#";
    }
    return output;
}

static void ExecuteNonQuery(SqlConnection conn, string sql)
{
    using var cmd = conn.CreateCommand();
    cmd.CommandText = sql;
    cmd.CommandTimeout = 60;
    cmd.ExecuteNonQuery();
}

static int CountRows(SqlConnection conn, string table)
{
    using var cmd = conn.CreateCommand();
    cmd.CommandText = $"SELECT COUNT(*) FROM [{table}]";
    return (int)cmd.ExecuteScalar()!;
}

static void InsertUser(SqlConnection conn, string username, string email, string hash,
    string first, string last, string display, string role, string bio)
{
    using var cmd = conn.CreateCommand();
    cmd.CommandText = @"INSERT INTO [Users] ([Username],[Email],[PasswordHash],[FirstName],[LastName],[DisplayName],[Role],[Bio])
                        VALUES (@u,@e,@h,@f,@l,@d,@r,@b)";
    cmd.Parameters.AddWithValue("@u", username);
    cmd.Parameters.AddWithValue("@e", email);
    cmd.Parameters.AddWithValue("@h", hash);
    cmd.Parameters.AddWithValue("@f", first);
    cmd.Parameters.AddWithValue("@l", last);
    cmd.Parameters.AddWithValue("@d", display);
    cmd.Parameters.AddWithValue("@r", role);
    cmd.Parameters.AddWithValue("@b", bio);
    cmd.ExecuteNonQuery();
}

static void InsertPage(SqlConnection conn, string slug, string title, string content,
    string summary, string category, int sortOrder)
{
    using var cmd = conn.CreateCommand();
    cmd.CommandText = @"INSERT INTO [SitePages] ([Slug],[Title],[Content],[Summary],[Category],[SortOrder])
                        VALUES (@s,@t,@c,@sm,@cat,@so)";
    cmd.Parameters.AddWithValue("@s", slug);
    cmd.Parameters.AddWithValue("@t", title);
    cmd.Parameters.AddWithValue("@c", content);
    cmd.Parameters.AddWithValue("@sm", summary);
    cmd.Parameters.AddWithValue("@cat", category);
    cmd.Parameters.AddWithValue("@so", sortOrder);
    cmd.ExecuteNonQuery();
}

static List<(string slug, string title, string content, string summary, string category, int sortOrder)> GetSitePages()
{
    return new()
    {
        ("monitoring-fundamentals",
         "Monitoring Fundamentals with Azure Monitor",
         @"<h3>Observability as an SRE Discipline</h3>
<p>Effective site reliability engineering starts with comprehensive observability. Azure Monitor provides a unified platform for collecting, analyzing, and acting on telemetry data from cloud and on-premises environments. The three pillars of observability -- metrics, logs, and traces -- give SRE teams the visibility required to maintain service-level objectives.</p>

<h4>Application Insights</h4>
<p>Application Insights, a feature of Azure Monitor, provides application performance management (APM) capabilities. It automatically detects performance anomalies and includes analytics tools to help diagnose issues and understand user behavior. For .NET applications, the SDK instruments incoming requests, outgoing dependency calls, exceptions, and custom telemetry.</p>

<h4>Log Analytics Workspace</h4>
<p>Log Analytics collects and organizes log and performance data from monitored resources. Data is queried using Kusto Query Language (KQL), enabling SRE teams to build dashboards, set up alerts, and perform root-cause analysis across the full application stack.</p>

<h4>Key Metrics for Reliability</h4>
<ul>
    <li><strong>Availability</strong> -- Percentage of time the service is operational and responding</li>
    <li><strong>Latency</strong> -- Time taken to process requests at various percentiles (p50, p95, p99)</li>
    <li><strong>Error Rate</strong> -- Proportion of requests resulting in errors</li>
    <li><strong>Throughput</strong> -- Number of requests processed per unit of time</li>
    <li><strong>Saturation</strong> -- Resource utilization levels for CPU, memory, disk, and network</li>
</ul>

<p>These metrics form the foundation of service-level indicators (SLIs) that map directly to service-level objectives (SLOs) -- the quantitative reliability targets that SRE teams track and defend.</p>",
         "Understanding the pillars of observability through Azure Monitor, Application Insights, and Log Analytics.",
         "SRE Concepts", 1),

        ("incident-response",
         "Incident Response and Automated Remediation",
         @"<h3>The Incident Lifecycle</h3>
<p>Every production incident follows a predictable lifecycle: detection, triage, diagnosis, mitigation, resolution, and post-incident review. Traditional SRE practices rely heavily on human operators at each stage. Azure SRE Agent introduces intelligent automation that accelerates each phase while keeping human engineers informed and in control.</p>

<h4>Detection</h4>
<p>Azure SRE Agent continuously monitors telemetry streams from Application Insights, Azure Monitor, and Log Analytics. When anomalies are detected -- such as a sudden spike in error rates, increased latency beyond threshold, or resource exhaustion patterns -- the agent correlates signals across multiple data sources to reduce false positives.</p>

<h4>Diagnosis</h4>
<p>Once an incident is confirmed, the agent performs automated root-cause analysis. It examines recent deployments, configuration changes, dependency health, and infrastructure metrics. The agent builds a causal chain linking the observed symptoms to likely root causes, significantly reducing the mean time to identify (MTTI) the problem.</p>

<h4>Remediation</h4>
<p>For known failure modes, the agent can execute pre-approved remediation actions: restarting unhealthy instances, scaling out resources, rolling back deployments, or toggling feature flags. Each automated action is logged and auditable, ensuring compliance and traceability.</p>

<h4>Continuous Improvement</h4>
<p>After resolution, the agent contributes to post-incident reviews by summarizing the timeline, actions taken, and impact metrics. This data feeds back into the system, improving future detection accuracy and expanding the library of automated remediation playbooks.</p>",
         "How Azure SRE Agent automates the detection, diagnosis, and resolution of production incidents.",
         "SRE Concepts", 2),

        ("managed-identity-security",
         "Managed Identity and Zero-Trust Access",
         @"<h3>Passwordless Authentication with Managed Identity</h3>
<p>Azure Managed Identity eliminates the need for applications to store and manage credentials. When enabled on an Azure resource such as App Service or Azure Functions, the platform automatically provisions an identity in Microsoft Entra ID. The application authenticates to other Azure services using this identity without any secrets in code or configuration.</p>

<h4>System-Assigned vs. User-Assigned</h4>
<p>System-assigned managed identities are tied to the lifecycle of the Azure resource. When the resource is deleted, the identity is automatically cleaned up. User-assigned identities are standalone Azure resources that can be shared across multiple services, offering more flexibility in complex architectures.</p>

<h4>Key Vault Integration</h4>
<p>This demo application uses a system-assigned managed identity to access Azure Key Vault secrets. The identity is granted the <em>Key Vault Secrets User</em> role through Azure RBAC, following the principle of least privilege. If this role assignment is removed, the application immediately loses the ability to read secrets -- a scenario this demo uses to validate SRE Agent detection capabilities.</p>

<h4>SQL Database Access via Entra</h4>
<p>Similarly, the web application connects to Azure SQL Database using Active Directory Default authentication. The managed identity is registered as a database user with appropriate permissions. Disrupting this access (for example, by removing a firewall rule) creates a detectable failure that demonstrates how SRE Agent identifies and helps resolve connectivity issues.</p>

<h4>SRE Impact</h4>
<p>When managed identity access is disrupted, the failure manifests differently depending on the affected resource. Key Vault failures may cause secret retrieval errors, while SQL connectivity issues result in database timeout exceptions. Azure SRE Agent correlates these symptoms with identity and access changes to quickly pinpoint the root cause.</p>",
         "Securing Azure resource access with managed identities and the principle of least privilege.",
         "Security", 3),

        ("waf-and-network-security",
         "Web Application Firewall and Network Protection",
         @"<h3>Application Gateway with WAF</h3>
<p>Azure Application Gateway is a layer-7 load balancer that provides SSL termination, cookie-based session affinity, URL-based routing, and integrated web application firewall (WAF) capabilities. WAF protects applications against common exploits such as SQL injection, cross-site scripting, and other OWASP Top 10 threats.</p>

<h4>WAF Policy Configuration</h4>
<p>This demo environment deploys an Application Gateway WAF v2 with OWASP 3.2 managed rule sets in Prevention mode. In Prevention mode, detected attacks are blocked and logged rather than simply detected. Every blocked request generates an entry in the WAF logs that flows to the Log Analytics workspace, creating a rich signal for SRE monitoring.</p>

<h4>SQL Injection Detection</h4>
<p>SQL injection attacks attempt to manipulate database queries by injecting malicious SQL statements through user input. The WAF rule set identifies patterns such as <code>OR 1=1</code>, <code>UNION SELECT</code>, and comment-based injection attempts. When these patterns are detected in requests routed through the Application Gateway, the WAF returns an HTTP 403 (Forbidden) response and logs the event.</p>

<h4>SRE Monitoring Signals</h4>
<p>WAF logs provide critical security telemetry for SRE teams. A sudden increase in blocked requests may indicate an active attack, while patterns of blocked legitimate requests suggest overly aggressive rules or application code that inadvertently triggers WAF rules. The Azure SRE Agent can correlate WAF block events with application error patterns to distinguish between security incidents and false-positive tuning issues.</p>

<h4>Demo Scenario</h4>
<p>The chaos engineering API includes an endpoint that sends SQL injection patterns through the Application Gateway. This validates that the WAF is actively blocking threats and that the resulting log entries are visible in Log Analytics -- confirming the full observability pipeline from attack detection through alert generation.</p>",
         "How Azure Application Gateway WAF protects applications and generates signals for SRE monitoring.",
         "Security", 4),

        ("chaos-engineering",
         "Chaos Engineering for Reliability Validation",
         @"<h3>Principles of Chaos Engineering</h3>
<p>Chaos engineering is the discipline of experimenting on a system to build confidence in its ability to withstand turbulent conditions. Rather than waiting for failures to occur in production, teams proactively inject faults to validate monitoring, alerting, and recovery mechanisms.</p>

<h4>Fault Injection in This Demo</h4>
<p>The Function App in this environment provides a suite of chaos engineering endpoints that simulate real-world failure modes:</p>
<ul>
    <li><strong>Exception Generation</strong> -- Triggers unhandled exceptions of various types (NullReference, DivisionByZero, Timeout, Memory) to validate Application Insights exception tracking</li>
    <li><strong>Latency Injection</strong> -- Introduces artificial delays to test performance alerting thresholds and timeout handling</li>
    <li><strong>Memory Pressure</strong> -- Allocates large memory blocks to simulate memory leaks and validate resource saturation alerts</li>
    <li><strong>CPU Saturation</strong> -- Generates CPU-intensive workloads to test compute scaling and performance degradation detection</li>
    <li><strong>Dependency Failures</strong> -- Simulates downstream service unavailability to validate circuit breaker patterns and dependency tracking</li>
    <li><strong>Error Storms</strong> -- Produces bursts of error log entries to test log pipeline capacity and anomaly detection</li>
    <li><strong>Access Revocation</strong> -- Removes managed identity role assignments to simulate security misconfigurations</li>
</ul>

<h4>Measuring Resilience</h4>
<p>Each chaos experiment has measurable outcomes: How quickly was the fault detected? Were the right alerts triggered? Did automated remediation activate? What was the impact on end users? These measurements validate the reliability posture of the system and identify gaps that require additional monitoring or automation.</p>

<h4>Integrating with SRE Agent</h4>
<p>Azure SRE Agent observes the effects of chaos experiments in real time. When a fault is injected, the agent should detect the resulting anomaly, diagnose the cause, and either recommend or execute remediation. This closed-loop validation proves the agent's effectiveness against known failure modes before trusting it with novel incidents.</p>",
         "Proactively testing system resilience through controlled failure injection.",
         "SRE Concepts", 5),

        ("service-level-objectives",
         "Service-Level Objectives and Error Budgets",
         @"<h3>SLIs, SLOs, and Error Budgets</h3>
<p>Service-level objectives (SLOs) are the quantitative targets for system reliability that bridge the gap between engineering teams and business stakeholders. They answer the question: How reliable does this service need to be?</p>

<h4>Service-Level Indicators</h4>
<p>SLIs are the metrics that measure specific aspects of service quality. Common SLIs include availability (successful requests / total requests), latency (percentage of requests completed within a threshold), and correctness (percentage of responses returning correct results). Choosing the right SLIs requires understanding what matters most to users.</p>

<h4>Defining Objectives</h4>
<p>An SLO sets a target value for an SLI over a specific time window. For example: 99.9% of HTTP requests will return a successful response within 500ms, measured over a rolling 30-day window. This target acknowledges that 100% reliability is neither achievable nor cost-effective.</p>

<h4>Error Budgets</h4>
<p>The error budget is the complement of the SLO -- the acceptable amount of unreliability within the measurement window. A 99.9% SLO allows approximately 43 minutes of downtime per month. When the error budget is healthy, teams can invest in feature development and experimentation. When the budget is depleted, the focus shifts entirely to reliability improvements.</p>

<h4>Azure SRE Agent and SLOs</h4>
<p>Azure SRE Agent can track error budget consumption in real time by monitoring the SLIs defined through Application Insights and Azure Monitor. When budget burn rate accelerates beyond normal patterns, the agent alerts the team and can take protective actions such as halting deployments or scaling resources to preserve remaining budget.</p>",
         "Defining and tracking reliability targets with SLOs and error budgets.",
         "SRE Concepts", 6),
    };
}
