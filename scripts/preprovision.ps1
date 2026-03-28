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
