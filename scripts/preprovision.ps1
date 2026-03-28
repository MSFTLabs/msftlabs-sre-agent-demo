#!/usr/bin/env pwsh
# preprovision.ps1 - Auto-detects deploying user identity for SQL Entra-only admin
# Runs automatically before 'azd provision'

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "=== Pre-provision: Detecting deployer identity ===" -ForegroundColor Cyan

# Get the signed-in user's object ID and UPN
$userObjectId = az ad signed-in-user show --query id -o tsv 2>$null
$userLogin = az ad signed-in-user show --query userPrincipalName -o tsv 2>$null

if (-not $userObjectId -or -not $userLogin) {
    Write-Error "Could not detect signed-in user. Ensure you are logged in with 'az login'."
    exit 1
}

Write-Host "  User:      $userLogin"
Write-Host "  Object ID: $userObjectId"

# Set azd environment variables (consumed by main.parameters.json)
azd env set AZURE_PRINCIPAL_ID $userObjectId
azd env set AZURE_AAD_ADMIN_LOGIN $userLogin

Write-Host "  [done] AZURE_PRINCIPAL_ID and AZURE_AAD_ADMIN_LOGIN set" -ForegroundColor Green
Write-Host ""

# ── Clean up SRE Agent incident action group ─────────────────────────────────
# The action group uses AAD-authenticated webhooks. Azure registers an AAD app
# behind the scenes and ties ownership to the original caller. On re-deployment
# the same caller may get a different token issuer context, causing:
#   AadWebhookResourceNotOwnedByCaller
# Fix: delete the action group before provisioning so it is recreated cleanly.

$envName = azd env get-value AZURE_ENV_NAME 2>$null
$rgName  = "rg-$envName"

$rgExists = az group exists --name $rgName 2>$null
if ($rgExists -eq 'true') {
    Write-Host "=== Pre-provision: Cleaning up SRE Agent action groups ===" -ForegroundColor Cyan

    $actionGroups = az monitor action-group list `
        --resource-group $rgName `
        --query "[?starts_with(name, 'ag-sre-') && ends_with(name, '-incidents')].name" `
        --output tsv 2>$null

    if ($actionGroups) {
        foreach ($ag in ($actionGroups -split "`n" | Where-Object { $_ -ne '' })) {
            Write-Host "  Deleting action group: $ag"
            az monitor action-group delete --resource-group $rgName --name $ag --yes 2>$null | Out-Null
        }
        Write-Host "  [done] Action group(s) removed — will be recreated by deployment" -ForegroundColor Green
    } else {
        Write-Host "  No SRE Agent action groups found — nothing to clean up" -ForegroundColor DarkGray
    }
    Write-Host ""
}
