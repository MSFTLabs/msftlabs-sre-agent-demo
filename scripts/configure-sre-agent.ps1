#!/usr/bin/env pwsh
# configure-sre-agent.ps1 — Post-provision SRE Agent configuration
# Configures GitHub PAT, creates incident action group, and wires alerts.
# Knowledge files and GitHub repository URL must be configured through the
# SRE Agent portal (https://sre.azure.com) — no ARM/REST API is available.

$ErrorActionPreference = 'Stop'

$agentName   = $env:AZURE_SRE_AGENT_NAME
$rgName      = $env:AZURE_RESOURCE_GROUP
$subId       = (az account show --query id -o tsv 2>$null)
$ghToken     = $env:AZURE_GITHUB_TOKEN
$ghRepoUrl   = $env:AZURE_GITHUB_REPO_URL
$identityPid = $env:AZURE_SRE_MANAGED_IDENTITY_PRINCIPAL_ID
$tenantId    = (az account show --query tenantId -o tsv 2>$null)

if (-not $rgName) { $rgName = "rg-$($env:AZURE_ENV_NAME)" }

if (-not $agentName) {
    Write-Warning "AZURE_SRE_AGENT_NAME not set — skipping SRE Agent configuration."
    exit 0
}

$apiVersion = '2025-05-01-preview'
$agentUri   = "/subscriptions/$subId/resourceGroups/$rgName/providers/Microsoft.App/agents/${agentName}?api-version=$apiVersion"

Write-Host ""
Write-Host "=== SRE Agent Post-Provision Configuration ===" -ForegroundColor Cyan
Write-Host "  Agent:    $agentName"
Write-Host "  RG:       $rgName"
Write-Host ""

# ============================================================
# 1) Configure GitHub PAT on the SRE Agent
# ============================================================
Write-Host "--- Step 1: Configuring GitHub PAT ---" -ForegroundColor Cyan

if ($ghToken) {
    $payload = @{properties=@{gitHubConfiguration=@{patTokenOverride=$ghToken}}} | ConvertTo-Json -Depth 5 -Compress
    $tmpFile = Join-Path $env:TEMP "sre-gh-config.json"
    Set-Content -Path $tmpFile -Value $payload -Encoding utf8NoBOM
    try {
        az rest --method PATCH --uri $agentUri --body "@$tmpFile" --headers "Content-Type=application/json" -o none 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [done] GitHub PAT configured" -ForegroundColor Green
        } else {
            Write-Warning "  Failed to configure GitHub PAT"
        }
    } catch {
        Write-Warning "  GitHub PAT configuration failed: $_"
    }
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "  AZURE_GITHUB_TOKEN not set — skipping" -ForegroundColor DarkGray
}

# ============================================================
# 2) Create incident action group (Azure Monitor → SRE Agent)
# ============================================================
Write-Host ""
Write-Host "--- Step 2: Creating incident action group ---" -ForegroundColor Cyan

$agName = "ag-${agentName}-incidents"
$incidentUri = "https://management.azure.com/subscriptions/$subId/resourceGroups/$rgName/providers/Microsoft.App/agents/$agentName/incidents?api-version=$apiVersion"

if ($identityPid -and $tenantId) {
    # Delete any stale action group first to avoid AadWebhookResourceNotOwnedByCaller
    $existing = az monitor action-group list --resource-group $rgName --query "[?name=='$agName'].name" -o tsv 2>$null
    if ($existing) {
        Write-Host "  Deleting stale action group: $agName"
        az monitor action-group delete --resource-group $rgName --name $agName --yes 2>$null | Out-Null
        Start-Sleep -Seconds 10
    }

    Write-Host "  Creating action group: $agName"
    try {
        az monitor action-group create `
            --resource-group $rgName `
            --name $agName `
            --short-name "SREIncident" `
            --action webhook SREAgentIncidents "$incidentUri" `
                useaadauth=true `
                objectid=$identityPid `
                identifieruri=https://management.azure.com `
                tenantid=$tenantId `
                usecommonalertschema=true `
            -o none 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [done] Action group created" -ForegroundColor Green
        } else {
            Write-Warning "  Action group creation failed — alerts will not auto-route to SRE Agent"
        }
    } catch {
        Write-Warning "  Action group creation failed: $_"
    }

    # Wire to existing alert rule
    $agId = az monitor action-group show --resource-group $rgName --name $agName --query id -o tsv 2>$null
    if ($agId) {
        Write-Host "  Wiring action group to alert: alert-appgw-unhealthy-backend"
        try {
            az monitor metrics alert update `
                --resource-group $rgName `
                --name "alert-appgw-unhealthy-backend" `
                --add-action $agId `
                -o none 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  [done] Alert wired to SRE Agent" -ForegroundColor Green
            } else {
                Write-Warning "  Could not wire action group to alert"
            }
        } catch {
            Write-Warning "  Failed to update alert rule: $_"
        }
    }
} else {
    Write-Host "  Missing identity PID or tenant — skipping" -ForegroundColor DarkGray
}

# ============================================================
# 3) Portal-only configuration reminders
# ============================================================
Write-Host ""
Write-Host "--- Step 3: Manual configuration required (portal) ---" -ForegroundColor Yellow
if ($ghRepoUrl) {
    Write-Host "  -> GitHub repository: $ghRepoUrl" -ForegroundColor White
    Write-Host "     Add this repo in SRE Agent portal > Settings > Code integration" -ForegroundColor DarkGray
}
Write-Host "  -> Knowledge files: Upload from /knowledgeFiles in SRE Agent portal > Knowledge tab" -ForegroundColor DarkGray
Write-Host ""
Write-Host "=== SRE Agent configuration complete ===" -ForegroundColor Cyan
Write-Host ""
