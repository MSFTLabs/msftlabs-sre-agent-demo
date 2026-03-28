#!/usr/bin/env pwsh
# postup.ps1 - Displays deployment URLs after 'azd up'

$gatewayUrl = $env:AZURE_APP_GATEWAY_URL
$gatewayIp  = $env:AZURE_APP_GATEWAY_IP
$webAppUrl  = $env:AZURE_WEBAPP_URL

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  MSFTLabs SRE Demo - Deployment Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

if ($gatewayUrl) {
    Write-Host "  Application URL:   $gatewayUrl" -ForegroundColor Green
} elseif ($webAppUrl) {
    Write-Host "  Application URL:   $webAppUrl" -ForegroundColor Green
}
if ($gatewayIp) {
    Write-Host "  Public IP:         $gatewayIp" -ForegroundColor White
}
if ($webAppUrl) {
    Write-Host "  Web App URL:       $webAppUrl" -ForegroundColor White
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
