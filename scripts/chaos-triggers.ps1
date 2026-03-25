<#
.SYNOPSIS
    SRE Agent Demo - Chaos Trigger Script

.DESCRIPTION
    Triggers controlled incidents to test Azure SRE Agent detection and remediation.
    Reads resource names from the azd environment so no hardcoded values are needed.

    Available triggers:
      1) SQL Injection Attack - Sends SQL injection patterns through the App Gateway WAF
      2) SQL Firewall Rule Removal - Removes App Service outbound IP firewall rules from SQL Server

.PARAMETER Trigger
    Which chaos trigger to run: SqlInjection, SqlFirewall, or All.

.EXAMPLE
    .\scripts\chaos-triggers.ps1 -Trigger SqlInjection
    .\scripts\chaos-triggers.ps1 -Trigger SqlFirewall
    .\scripts\chaos-triggers.ps1 -Trigger All
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('SqlInjection', 'SqlFirewall', 'All')]
    [string]$Trigger
)

$ErrorActionPreference = 'Stop'

# ── Load azd environment values ──────────────────────────────────────────────
Write-Host "`n=== Loading azd environment ===" -ForegroundColor Cyan
$azdEnv = azd env get-values 2>$null | ConvertFrom-StringData

$rgName        = $azdEnv['AZURE_RESOURCE_GROUP']
$sqlServerName = $azdEnv['AZURE_SQL_SERVER_NAME']
$gatewayUrl    = $azdEnv['AZURE_APP_GATEWAY_URL']

if (-not $rgName -or -not $sqlServerName -or -not $gatewayUrl) {
    Write-Error "Missing azd environment values. Run 'azd env get-values' to verify AZURE_RESOURCE_GROUP, AZURE_SQL_SERVER_NAME, and AZURE_APP_GATEWAY_URL are set."
    exit 1
}

Write-Host "  Resource Group : $rgName"
Write-Host "  SQL Server     : $sqlServerName"
Write-Host "  App Gateway URL: $gatewayUrl"

# ── 1. SQL Injection Attack ──────────────────────────────────────────────────
function Invoke-SqlInjectionTrigger {
    Write-Host "`n=== Trigger: SQL Injection Attack ===" -ForegroundColor Red
    Write-Host "Sending SQL injection patterns through the App Gateway WAF..."
    Write-Host "  What happens:"
    Write-Host "    1. SQL injection payloads sent to App Gateway"
    Write-Host "    2. WAF blocks requests (HTTP 403)"
    Write-Host "    3. 'WAF Blocked Requests' alert fires (Sev 2)"
    Write-Host "    4. SRE Agent picks up the incident and investigates`n"

    $patterns = @(
        "?id=1' OR '1'='1",
        "?search='; DROP TABLE Users;--",
        "?q=1 UNION SELECT username,password FROM Users",
        "?input=<script>alert('xss')</script>",
        "?file=../../etc/passwd"
    )

    $blockedCount = 0
    foreach ($pattern in $patterns) {
        $target = "$($gatewayUrl.TrimEnd('/'))/$pattern"
        try {
            $response = Invoke-WebRequest -Uri $target -Method GET -SkipHttpErrorCheck -TimeoutSec 10 -ErrorAction SilentlyContinue
            $status = $response.StatusCode
            $blocked = $status -eq 403
            if ($blocked) { $blockedCount++ }
            $icon = if ($blocked) { "[BLOCKED]" } else { "[PASSED]" }
            $color = if ($blocked) { "Yellow" } else { "Red" }
            Write-Host "  $icon HTTP $status - $pattern" -ForegroundColor $color
        }
        catch {
            Write-Host "  [ERROR] $pattern - $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`nResult: $blockedCount/$($patterns.Count) patterns blocked by WAF." -ForegroundColor Green
    if ($blockedCount -gt 0) {
        Write-Host "Alert should fire within ~2 minutes." -ForegroundColor Green
    }
}

# ── 2. SQL Firewall Rule Removal ─────────────────────────────────────────────
function Invoke-SqlFirewallTrigger {
    Write-Host "`n=== Trigger: SQL Firewall Rule Removal ===" -ForegroundColor Yellow
    Write-Host "Removing App Service outbound IP firewall rules from SQL Server..."
    Write-Host "  What happens:"
    Write-Host "    1. Outbound IP firewall rules deleted via Azure CLI"
    Write-Host "    2. Web app loses SQL connectivity"
    Write-Host "    3. 'SQL Connectivity Failure' alert fires (Sev 1)"
    Write-Host "    4. SRE Agent picks up the incident and investigates`n"

    # List firewall rules matching AppServiceOutbound-*
    $rulesJson = az sql server firewall-rule list --resource-group $rgName --server $sqlServerName --output json 2>$null
    $rules = $rulesJson | ConvertFrom-Json | Where-Object { $_.name -like 'AppServiceOutbound-*' }

    if (-not $rules -or $rules.Count -eq 0) {
        Write-Host "  No AppServiceOutbound-* firewall rules found (already removed)." -ForegroundColor Gray
        return
    }

    Write-Host "  Found $($rules.Count) AppServiceOutbound rules to remove:"
    $deletedCount = 0
    foreach ($rule in $rules) {
        Write-Host "    Deleting $($rule.name) ($($rule.startIpAddress))..." -NoNewline
        az sql server firewall-rule delete --resource-group $rgName --server $sqlServerName --name $rule.name --yes 2>$null
        if ($LASTEXITCODE -eq 0) {
            $deletedCount++
            Write-Host " done" -ForegroundColor Green
        } else {
            Write-Host " FAILED" -ForegroundColor Red
        }
    }

    Write-Host "`nResult: Removed $deletedCount/$($rules.Count) firewall rules." -ForegroundColor Green
    Write-Host "The web app will lose SQL connectivity. Alert should fire within ~2 minutes." -ForegroundColor Yellow
}

# ── Run selected trigger(s) ──────────────────────────────────────────────────
switch ($Trigger) {
    'SqlInjection' { Invoke-SqlInjectionTrigger }
    'SqlFirewall'  { Invoke-SqlFirewallTrigger }
    'All' {
        Invoke-SqlInjectionTrigger
        Invoke-SqlFirewallTrigger
    }
}

Write-Host "`nDone.`n" -ForegroundColor Cyan
