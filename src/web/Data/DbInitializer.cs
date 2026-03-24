using Azure.Security.KeyVault.Secrets;
using SreDemo.Web.Models;

namespace SreDemo.Web.Data;

public static class DbInitializer
{
    // Usernames for all demo accounts - passwords are stored in Key Vault
    // as secrets named user-password-{username}
    public static readonly string[] Usernames =
    [
        "admin", "jmorales", "akovacs", "schen", "bmurphy",
        "pnakamura", "dwilliams", "lpetrova", "rsingh", "efischer", "okim"
    ];

    public static void Initialize(ApplicationDbContext context, SecretClient? secretClient, ILogger? logger = null)
    {
        context.Database.EnsureCreated();

        if (!context.Users.Any())
            SeedUsers(context, secretClient, logger);

        if (!context.SitePages.Any())
            SeedPages(context);
    }

    private static string ReadPasswordFromKeyVault(SecretClient? secretClient, string username, ILogger? logger)
    {
        if (secretClient == null)
        {
            logger?.LogWarning("No SecretClient configured - generating local dev password for {Username}", username);
            return $"LocalDev!{username}2026#";
        }

        try
        {
            var secret = secretClient.GetSecret($"user-password-{username}");
            return secret.Value.Value;
        }
        catch (Exception ex)
        {
            logger?.LogWarning(ex, "Could not read password from Key Vault for {Username} - using fallback", username);
            return $"LocalDev!{username}2026#";
        }
    }

    private static void SeedUsers(ApplicationDbContext context, SecretClient? secretClient, ILogger? logger)
    {
        var users = new List<User>
        {
            new()
            {
                Username = "admin", Email = "admin@msftlabs.org",
                FirstName = "SRE", LastName = "Administrator",
                DisplayName = "SRE Administrator", Role = "Admin",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(ReadPasswordFromKeyVault(secretClient, "admin", logger)),
                Bio = "Platform reliability engineer and demo environment administrator."
            },
            new()
            {
                Username = "jmorales", Email = "jmorales@msftlabs.org",
                FirstName = "Juan", LastName = "Morales",
                DisplayName = "Juan Morales", Role = "User",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(ReadPasswordFromKeyVault(secretClient, "jmorales", logger)),
                Bio = "Cloud solutions architect focused on resilience patterns."
            },
            new()
            {
                Username = "akovacs", Email = "akovacs@msftlabs.org",
                FirstName = "Andrea", LastName = "Kovacs",
                DisplayName = "Andrea Kovacs", Role = "User",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(ReadPasswordFromKeyVault(secretClient, "akovacs", logger)),
                Bio = "Site reliability engineer specializing in observability."
            },
            new()
            {
                Username = "schen", Email = "schen@msftlabs.org",
                FirstName = "Sophia", LastName = "Chen",
                DisplayName = "Sophia Chen", Role = "User",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(ReadPasswordFromKeyVault(secretClient, "schen", logger)),
                Bio = "DevOps lead with deep experience in incident management."
            },
            new()
            {
                Username = "bmurphy", Email = "bmurphy@msftlabs.org",
                FirstName = "Brian", LastName = "Murphy",
                DisplayName = "Brian Murphy", Role = "User",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(ReadPasswordFromKeyVault(secretClient, "bmurphy", logger)),
                Bio = "Infrastructure engineer working on Azure landing zones."
            },
            new()
            {
                Username = "pnakamura", Email = "pnakamura@msftlabs.org",
                FirstName = "Priya", LastName = "Nakamura",
                DisplayName = "Priya Nakamura", Role = "User",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(ReadPasswordFromKeyVault(secretClient, "pnakamura", logger)),
                Bio = "Application performance analyst and monitoring specialist."
            },
            new()
            {
                Username = "dwilliams", Email = "dwilliams@msftlabs.org",
                FirstName = "Daniel", LastName = "Williams",
                DisplayName = "Daniel Williams", Role = "User",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(ReadPasswordFromKeyVault(secretClient, "dwilliams", logger)),
                Bio = "Security-focused SRE with background in threat modeling."
            },
            new()
            {
                Username = "lpetrova", Email = "lpetrova@msftlabs.org",
                FirstName = "Lena", LastName = "Petrova",
                DisplayName = "Lena Petrova", Role = "User",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(ReadPasswordFromKeyVault(secretClient, "lpetrova", logger)),
                Bio = "Database reliability engineer managing SQL and Cosmos DB fleets."
            },
            new()
            {
                Username = "rsingh", Email = "rsingh@msftlabs.org",
                FirstName = "Raj", LastName = "Singh",
                DisplayName = "Raj Singh", Role = "User",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(ReadPasswordFromKeyVault(secretClient, "rsingh", logger)),
                Bio = "Automation engineer building self-healing infrastructure."
            },
            new()
            {
                Username = "efischer", Email = "efischer@msftlabs.org",
                FirstName = "Ema", LastName = "Fischer",
                DisplayName = "Ema Fischer", Role = "User",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(ReadPasswordFromKeyVault(secretClient, "efischer", logger)),
                Bio = "Capacity planning lead focused on cost-effective scaling."
            },
            new()
            {
                Username = "okim", Email = "okim@msftlabs.org",
                FirstName = "Oliver", LastName = "Kim",
                DisplayName = "Oliver Kim", Role = "User",
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(ReadPasswordFromKeyVault(secretClient, "okim", logger)),
                Bio = "Incident responder and chaos engineering practitioner."
            }
        };

        context.Users.AddRange(users);
        context.SaveChanges();
    }

    private static void SeedPages(ApplicationDbContext context)
    {
        var pages = new List<SitePage>
        {
            new()
            {
                Slug = "monitoring-fundamentals",
                Title = "Monitoring Fundamentals with Azure Monitor",
                Category = "SRE Concepts",
                SortOrder = 1,
                Summary = "Understanding the pillars of observability through Azure Monitor, Application Insights, and Log Analytics.",
                Content = @"<h3>Observability as an SRE Discipline</h3>
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

<p>These metrics form the foundation of service-level indicators (SLIs) that map directly to service-level objectives (SLOs) -- the quantitative reliability targets that SRE teams track and defend.</p>"
            },
            new()
            {
                Slug = "incident-response",
                Title = "Incident Response and Automated Remediation",
                Category = "SRE Concepts",
                SortOrder = 2,
                Summary = "How Azure SRE Agent automates the detection, diagnosis, and resolution of production incidents.",
                Content = @"<h3>The Incident Lifecycle</h3>
<p>Every production incident follows a predictable lifecycle: detection, triage, diagnosis, mitigation, resolution, and post-incident review. Traditional SRE practices rely heavily on human operators at each stage. Azure SRE Agent introduces intelligent automation that accelerates each phase while keeping human engineers informed and in control.</p>

<h4>Detection</h4>
<p>Azure SRE Agent continuously monitors telemetry streams from Application Insights, Azure Monitor, and Log Analytics. When anomalies are detected -- such as a sudden spike in error rates, increased latency beyond threshold, or resource exhaustion patterns -- the agent correlates signals across multiple data sources to reduce false positives.</p>

<h4>Diagnosis</h4>
<p>Once an incident is confirmed, the agent performs automated root-cause analysis. It examines recent deployments, configuration changes, dependency health, and infrastructure metrics. The agent builds a causal chain linking the observed symptoms to likely root causes, significantly reducing the mean time to identify (MTTI) the problem.</p>

<h4>Remediation</h4>
<p>For known failure modes, the agent can execute pre-approved remediation actions: restarting unhealthy instances, scaling out resources, rolling back deployments, or toggling feature flags. Each automated action is logged and auditable, ensuring compliance and traceability.</p>

<h4>Continuous Improvement</h4>
<p>After resolution, the agent contributes to post-incident reviews by summarizing the timeline, actions taken, and impact metrics. This data feeds back into the system, improving future detection accuracy and expanding the library of automated remediation playbooks.</p>"
            },
            new()
            {
                Slug = "managed-identity-security",
                Title = "Managed Identity and Zero-Trust Access",
                Category = "Security",
                SortOrder = 3,
                Summary = "Securing Azure resource access with managed identities and the principle of least privilege.",
                Content = @"<h3>Passwordless Authentication with Managed Identity</h3>
<p>Azure Managed Identity eliminates the need for applications to store and manage credentials. When enabled on an Azure resource such as App Service or Azure Functions, the platform automatically provisions an identity in Microsoft Entra ID. The application authenticates to other Azure services using this identity without any secrets in code or configuration.</p>

<h4>System-Assigned vs. User-Assigned</h4>
<p>System-assigned managed identities are tied to the lifecycle of the Azure resource. When the resource is deleted, the identity is automatically cleaned up. User-assigned identities are standalone Azure resources that can be shared across multiple services, offering more flexibility in complex architectures.</p>

<h4>Key Vault Integration</h4>
<p>This demo application uses a system-assigned managed identity to access Azure Key Vault secrets. The identity is granted the <em>Key Vault Secrets User</em> role through Azure RBAC, following the principle of least privilege. If this role assignment is removed, the application immediately loses the ability to read secrets -- a scenario this demo uses to validate SRE Agent detection capabilities.</p>

<h4>SQL Database Access via Entra</h4>
<p>Similarly, the web application connects to Azure SQL Database using Active Directory Default authentication. The managed identity is registered as a database user with appropriate permissions. Disrupting this access (for example, by removing a firewall rule) creates a detectable failure that demonstrates how SRE Agent identifies and helps resolve connectivity issues.</p>

<h4>SRE Impact</h4>
<p>When managed identity access is disrupted, the failure manifests differently depending on the affected resource. Key Vault failures may cause secret retrieval errors, while SQL connectivity issues result in database timeout exceptions. Azure SRE Agent correlates these symptoms with identity and access changes to quickly pinpoint the root cause.</p>"
            },
            new()
            {
                Slug = "waf-and-network-security",
                Title = "Web Application Firewall and Network Protection",
                Category = "Security",
                SortOrder = 4,
                Summary = "How Azure Application Gateway WAF protects applications and generates signals for SRE monitoring.",
                Content = @"<h3>Application Gateway with WAF</h3>
<p>Azure Application Gateway is a layer-7 load balancer that provides SSL termination, cookie-based session affinity, URL-based routing, and integrated web application firewall (WAF) capabilities. WAF protects applications against common exploits such as SQL injection, cross-site scripting, and other OWASP Top 10 threats.</p>

<h4>WAF Policy Configuration</h4>
<p>This demo environment deploys an Application Gateway WAF v2 with OWASP 3.2 managed rule sets in Prevention mode. In Prevention mode, detected attacks are blocked and logged rather than simply detected. Every blocked request generates an entry in the WAF logs that flows to the Log Analytics workspace, creating a rich signal for SRE monitoring.</p>

<h4>SQL Injection Detection</h4>
<p>SQL injection attacks attempt to manipulate database queries by injecting malicious SQL statements through user input. The WAF rule set identifies patterns such as <code>OR 1=1</code>, <code>UNION SELECT</code>, and comment-based injection attempts. When these patterns are detected in requests routed through the Application Gateway, the WAF returns an HTTP 403 (Forbidden) response and logs the event.</p>

<h4>SRE Monitoring Signals</h4>
<p>WAF logs provide critical security telemetry for SRE teams. A sudden increase in blocked requests may indicate an active attack, while patterns of blocked legitimate requests suggest overly aggressive rules or application code that inadvertently triggers WAF rules. The Azure SRE Agent can correlate WAF block events with application error patterns to distinguish between security incidents and false-positive tuning issues.</p>

<h4>Demo Scenario</h4>
<p>The chaos engineering API includes an endpoint that sends SQL injection patterns through the Application Gateway. This validates that the WAF is actively blocking threats and that the resulting log entries are visible in Log Analytics -- confirming the full observability pipeline from attack detection through alert generation.</p>"
            },
            new()
            {
                Slug = "chaos-engineering",
                Title = "Chaos Engineering for Reliability Validation",
                Category = "SRE Concepts",
                SortOrder = 5,
                Summary = "Proactively testing system resilience through controlled failure injection.",
                Content = @"<h3>Principles of Chaos Engineering</h3>
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
<p>Azure SRE Agent observes the effects of chaos experiments in real time. When a fault is injected, the agent should detect the resulting anomaly, diagnose the cause, and either recommend or execute remediation. This closed-loop validation proves the agent's effectiveness against known failure modes before trusting it with novel incidents.</p>"
            },
            new()
            {
                Slug = "service-level-objectives",
                Title = "Service-Level Objectives and Error Budgets",
                Category = "SRE Concepts",
                SortOrder = 6,
                Summary = "Defining and tracking reliability targets with SLOs and error budgets.",
                Content = @"<h3>SLIs, SLOs, and Error Budgets</h3>
<p>Service-level objectives (SLOs) are the quantitative targets for system reliability that bridge the gap between engineering teams and business stakeholders. They answer the question: How reliable does this service need to be?</p>

<h4>Service-Level Indicators</h4>
<p>SLIs are the metrics that measure specific aspects of service quality. Common SLIs include availability (successful requests / total requests), latency (percentage of requests completed within a threshold), and correctness (percentage of responses returning correct results). Choosing the right SLIs requires understanding what matters most to users.</p>

<h4>Defining Objectives</h4>
<p>An SLO sets a target value for an SLI over a specific time window. For example: 99.9% of HTTP requests will return a successful response within 500ms, measured over a rolling 30-day window. This target acknowledges that 100% reliability is neither achievable nor cost-effective.</p>

<h4>Error Budgets</h4>
<p>The error budget is the complement of the SLO -- the acceptable amount of unreliability within the measurement window. A 99.9% SLO allows approximately 43 minutes of downtime per month. When the error budget is healthy, teams can invest in feature development and experimentation. When the budget is depleted, the focus shifts entirely to reliability improvements.</p>

<h4>Azure SRE Agent and SLOs</h4>
<p>Azure SRE Agent can track error budget consumption in real time by monitoring the SLIs defined through Application Insights and Azure Monitor. When budget burn rate accelerates beyond normal patterns, the agent alerts the team and can take protective actions such as halting deployments or scaling resources to preserve remaining budget.</p>"
            }
        };

        context.SitePages.AddRange(pages);
        context.SaveChanges();
    }
}
