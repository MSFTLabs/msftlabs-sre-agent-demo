#!/usr/bin/env pwsh
# postup.ps1 - Displays Application Gateway URL after 'azd up'

$gatewayUrl = $env:AZURE_APP_GATEWAY_URL
$gatewayIp  = $env:AZURE_APP_GATEWAY_IP

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  MSFTLabs SRE Demo - Deployment Complete" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

if ($gatewayUrl) {
    Write-Host "  Application URL:   $gatewayUrl" -ForegroundColor Green
}
if ($gatewayIp) {
    Write-Host "  Public IP:         $gatewayIp" -ForegroundColor White
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
