#!/usr/bin/env pwsh
# trigger-incident.ps1 — Disables SQL public network access to trigger an
# Azure Monitor alert, then tracks the SRE Agent auto-detecting the incident
# via webhook, investigating, and remediating — printing timestamped status
# for each lifecycle stage.

param(
    [string]$EnvName,
    [string]$SreAgentName = 'msftlabs-sre-agent'
)

$ErrorActionPreference = 'Stop'

# ============================================================
# Load azd environment
# ============================================================
if ($EnvName) { azd env select $EnvName 2>$null }

function Get-AzdValue([string]$key) {
    $val = azd env get-value $key 2>$null
    if (-not $val) { Write-Error "Missing azd env value: $key"; exit 1 }
    return $val.Trim()
}

$subId   = Get-AzdValue 'AZURE_SUBSCRIPTION_ID'
$rg      = Get-AzdValue 'AZURE_RESOURCE_GROUP'
$sqlName = Get-AzdValue 'AZURE_SQL_SERVER_NAME'
$webUrl  = Get-AzdValue 'AZURE_WEBAPP_URL'

$probeUrl  = "$webUrl/Health/Probe"
$alertName = 'alert-appgw-unhealthy-backend'

# ============================================================
# Helpers
# ============================================================
function Write-Stage([string]$msg, [string]$color = 'Cyan') {
    $ts = (Get-Date).ToUniversalTime().ToString('HH:mm:ss UTC')
    Write-Host "  [$ts] $msg" -ForegroundColor $color
}

function Get-SqlPublicAccess {
    (az sql server show --name $sqlName --resource-group $rg `
        --subscription $subId --query publicNetworkAccess -o tsv 2>$null).Trim()
}

function Get-ProbeStatus {
    try {
        $r = Invoke-WebRequest -Uri $probeUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        return [int]$r.StatusCode
    } catch {
        if ($_.Exception.Response) { return [int]$_.Exception.Response.StatusCode }
        return 0
    }
}

function Get-AlertState {
    $url = "https://management.azure.com/subscriptions/$subId/providers/Microsoft.AlertsManagement/alerts?api-version=2019-03-01&targetResourceGroup=$rg&monitorCondition=Fired"
    $result = az rest --method GET --url $url 2>$null | ConvertFrom-Json
    if (-not $result -or -not $result.value) { return '' }
    $match = $result.value | Where-Object {
        $_.properties.essentials.alertRule -match $alertName -and
        $_.properties.essentials.startDateTime -gt $script:breakTime.ToString('o')
    }
    if ($match) { return 'Fired' }
    return ''
}

# ============================================================
# Pre-flight checks
# ============================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Yellow
Write-Host "  SRE Agent Incident Trigger" -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "  SQL Server:     $sqlName" -ForegroundColor DarkGray
Write-Host "  Resource Group: $rg" -ForegroundColor DarkGray
Write-Host "  Health Probe:   $probeUrl" -ForegroundColor DarkGray
Write-Host "  SRE Agent:      $SreAgentName" -ForegroundColor DarkGray
Write-Host ""

$currentAccess = Get-SqlPublicAccess
if ($currentAccess -eq 'Disabled') {
    Write-Host "  SQL public access is already Disabled." -ForegroundColor Red
    Write-Host "  Re-enable first: az sql server update --name $sqlName --resource-group $rg --set publicNetworkAccess=Enabled" -ForegroundColor DarkGray
    exit 1
}

$probe = Get-ProbeStatus
if ($probe -ne 200) {
    Write-Host "  Health probe is already unhealthy (HTTP $probe) — fix the app first." -ForegroundColor Red
    exit 1
}

Write-Stage "Pre-flight PASSED — app healthy, SQL public access Enabled" "Green"
Write-Host ""

# ============================================================
# Stage 1: Disable SQL public network access
# ============================================================
Write-Host "--- STAGE 1: Triggering incident ---------------------------" -ForegroundColor Magenta

Write-Stage "Disabling SQL public network access..." "Yellow"
az sql server update --name $sqlName --resource-group $rg --subscription $subId `
    --set publicNetworkAccess=Disabled -o none 2>$null

$script:breakTime = (Get-Date).ToUniversalTime()
Write-Stage "SQL publicNetworkAccess = Disabled" "Red"

# ============================================================
# Stage 2: Wait for health probe to fail
# ============================================================
Write-Host ""
Write-Host "--- STAGE 2: Waiting for health probe failure --------------" -ForegroundColor Magenta

$maxWait = 180; $elapsed = 0
while ($elapsed -lt $maxWait) {
    $status = Get-ProbeStatus
    if ($status -ne 200) {
        Write-Stage "Health probe FAILED (HTTP $status)" "Red"
        break
    }
    Write-Stage "Probe still passing (HTTP $status)... waiting" "DarkGray"
    Start-Sleep -Seconds 10; $elapsed += 10
}
if ($elapsed -ge $maxWait) { Write-Stage "Timed out after ${maxWait}s" "Yellow" }

# ============================================================
# Stage 3: Wait for Azure Monitor alert to fire
# ============================================================
Write-Host ""
Write-Host "--- STAGE 3: Waiting for Azure Monitor alert ---------------" -ForegroundColor Magenta
Write-Stage "Alert evaluates every 1 min / 5 min window — may take several minutes" "DarkGray"

$alertFired = $false
$maxWait = 600; $elapsed = 0
while ($elapsed -lt $maxWait) {
    $state = Get-AlertState
    if ($state -eq 'Fired') {
        Write-Stage "ALERT FIRED: $alertName" "Red"
        $alertFired = $true
        break
    }
    $min = [math]::Floor($elapsed / 60); $sec = $elapsed % 60
    Write-Stage "Alert not yet fired... (${min}m ${sec}s)" "DarkGray"
    Start-Sleep -Seconds 30; $elapsed += 30
}
if (-not $alertFired) {
    Write-Stage "Alert not detected via API after ${maxWait}s — proceeding anyway" "Yellow"
}

# ============================================================
# Stage 4: Wait for SRE Agent to auto-detect the incident
# ============================================================
Write-Host ""
Write-Host "--- STAGE 4: Waiting for SRE Agent auto-detection ----------" -ForegroundColor Magenta

Write-Stage "Looking up SRE Agent endpoint..." "DarkGray"
$agentUrl = "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.App/agents/${SreAgentName}?api-version=2026-01-01"
$agent = az rest --method GET --url $agentUrl 2>$null | ConvertFrom-Json

$incidentDetected = $false
if ($agent -and $agent.properties.agentEndpoint) {
    $endpoint = $agent.properties.agentEndpoint
    Write-Stage "Agent endpoint: $endpoint" "DarkGray"
    Write-Stage "Portal: https://sre.azure.com" "DarkGray"
    Write-Stage "Polling for auto-detected incident (via Azure Monitor webhook)..." "Cyan"

    $maxWait = 600; $elapsed = 0
    while ($elapsed -lt $maxWait) {
        $incidents = az rest --method GET `
            --url "$endpoint/api/v1/incidents?status=active" `
            --headers "Content-Type=application/json" `
            --resource "https://azuresre.ai" 2>$null | ConvertFrom-Json
        if ($incidents) {
            $match = @($incidents | Where-Object {
                $_.createdAt -gt $script:breakTime.ToString('o') -or
                $_.title -match 'unhealthy|appgw'
            })
            if ($match.Count -gt 0) {
                $inc = $match[0]
                Write-Stage "INCIDENT AUTO-DETECTED by SRE Agent" "Green"
                Write-Stage "  Title:  $($inc.title)" "White"
                Write-Stage "  ID:     $($inc.id)" "DarkGray"
                Write-Stage "  Status: $($inc.status)" "White"
                $incidentDetected = $true
                break
            }
        }
        $min = [math]::Floor($elapsed / 60); $sec = $elapsed % 60
        Write-Stage "No incident detected yet... (${min}m ${sec}s)" "DarkGray"
        Start-Sleep -Seconds 15; $elapsed += 15
    }
    if (-not $incidentDetected) {
        Write-Stage "Incident not auto-detected after $([math]::Floor($maxWait/60))m" "Yellow"
        Write-Stage "Check Triggers + Response Plans in the SRE Agent portal" "Yellow"
    }
} else {
    Write-Stage "Could not resolve SRE Agent — check it exists in $rg" "Yellow"
}

# ============================================================
# Stage 5: Wait for SRE Agent remediation
# ============================================================
Write-Host ""
Write-Host "--- STAGE 5: Waiting for SRE Agent remediation -------------" -ForegroundColor Magenta
Write-Stage "Polling SQL publicNetworkAccess every 15s..." "Cyan"

$remediated = $false
$maxWait = 900; $elapsed = 0
while ($elapsed -lt $maxWait) {
    $access = Get-SqlPublicAccess
    if ($access -eq 'Enabled') {
        Write-Stage "SRE Agent REMEDIATED — publicNetworkAccess = Enabled" "Green"
        $remediated = $true
        break
    }
    $min = [math]::Floor($elapsed / 60)
    Write-Stage "SQL still Disabled — agent working... (${min}m)" "DarkGray"
    Start-Sleep -Seconds 15; $elapsed += 15
}
if (-not $remediated) {
    Write-Stage "Timed out after $([math]::Floor($maxWait/60))m — check SRE Agent portal" "Yellow"
}

# ============================================================
# Stage 6: Verify recovery
# ============================================================
Write-Host ""
Write-Host "--- STAGE 6: Verifying recovery ----------------------------" -ForegroundColor Magenta

$recovered = $false
$maxWait = 120; $elapsed = 0
while ($elapsed -lt $maxWait) {
    $status = Get-ProbeStatus
    if ($status -eq 200) {
        Write-Stage "Health probe RECOVERED (HTTP 200)" "Green"
        $recovered = $true
        break
    }
    Write-Stage "Probe returning HTTP $status... waiting" "DarkGray"
    Start-Sleep -Seconds 10; $elapsed += 10
}

$totalTime = [math]::Round(((Get-Date).ToUniversalTime() - $script:breakTime).TotalSeconds)

# ============================================================
# Summary
# ============================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor $(if ($recovered) { 'Green' } else { 'Yellow' })
Write-Host "  Incident Lifecycle Complete" -ForegroundColor $(if ($recovered) { 'Green' } else { 'Yellow' })
Write-Host "==========================================" -ForegroundColor $(if ($recovered) { 'Green' } else { 'Yellow' })
Write-Host ""
Write-Host "  Total time:          $([math]::Floor($totalTime/60))m $($totalTime%60)s" -ForegroundColor White
Write-Host "  Alert fired:         $(if ($alertFired) { 'Yes' } else { 'Not detected' })" -ForegroundColor White
Write-Host "  Auto-detected:       $(if ($incidentDetected) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "  Agent remediated:    $(if ($remediated) { 'Yes' } else { 'No' })" -ForegroundColor White
Write-Host "  SQL public access:   $(Get-SqlPublicAccess)" -ForegroundColor White
Write-Host "  Health probe:        HTTP $(Get-ProbeStatus)" -ForegroundColor White
Write-Host ""
