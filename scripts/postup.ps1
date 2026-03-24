#!/usr/bin/env pwsh
# postup.ps1 - Displays WebApp URL and Admin credentials after 'azd up'

$kvName     = $env:AZURE_KEY_VAULT_NAME
$webAppUrl  = $env:AZURE_WEBAPP_URL
$gatewayUrl = $env:AZURE_APP_GATEWAY_URL

if (-not $kvName) {
    Write-Warning "AZURE_KEY_VAULT_NAME not set - cannot retrieve admin credentials."
    exit 0
}

$adminPassword = $null
try {
    $adminPassword = az keyvault secret show --vault-name $kvName --name "user-password-admin" --query "value" -o tsv 2>$null
} catch { }

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  MSFTLabs SRE Demo - Deployment Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

if ($webAppUrl) {
    Write-Host "  Web App URL:       $webAppUrl" -ForegroundColor White
}
if ($gatewayUrl) {
    Write-Host "  App Gateway URL:   $gatewayUrl" -ForegroundColor White
}

Write-Host ""
Write-Host "  Admin Login" -ForegroundColor Yellow
Write-Host "  ───────────────────────────" -ForegroundColor DarkGray
Write-Host "  Username:          admin" -ForegroundColor White

if ($adminPassword) {
    Write-Host "  Password:          $adminPassword" -ForegroundColor White
} else {
    Write-Host "  Password:          (could not retrieve - check KV access)" -ForegroundColor Red
}

Write-Host ""
Write-Host "  Key Vault:         $kvName" -ForegroundColor DarkGray
Write-Host "  All user passwords stored as: user-password-{username}" -ForegroundColor DarkGray
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
