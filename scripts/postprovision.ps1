#!/usr/bin/env pwsh
# postprovision.ps1 - Adds deployer firewall rule, grants web app db_owner, seeds data
# Runs automatically after 'azd provision'
# SQL Entra admin and RG Owner are set in Bicep (MCAPS policy requires Entra-only auth at creation)

$ErrorActionPreference = 'Stop'

$sqlServerName = $env:AZURE_SQL_SERVER_NAME
$sqlDbName     = $env:AZURE_SQL_DATABASE_NAME
$webAppName    = $env:AZURE_WEBAPP_NAME
$rgName        = $env:AZURE_RESOURCE_GROUP
if (-not $rgName) { $rgName = "rg-$($env:AZURE_ENV_NAME)" }

if (-not $sqlServerName) { Write-Error "AZURE_SQL_SERVER_NAME not set."; exit 1 }
if (-not $sqlDbName)     { Write-Error "AZURE_SQL_DATABASE_NAME not set."; exit 1 }
if (-not $webAppName)    { Write-Error "AZURE_WEBAPP_NAME not set."; exit 1 }

$sqlFqdn = "${sqlServerName}.database.windows.net"

# ============================================================
# 1) Add temporary SQL firewall rule for deployer IP
# ============================================================
Write-Host ""
Write-Host "=== Step 1: Adding SQL firewall rule for deployer ===" -ForegroundColor Cyan

$myIp = $null
try {
    $myIp = (Invoke-RestMethod -Uri "https://api.ipify.org" -TimeoutSec 10).Trim()
} catch {
    try { $myIp = (Invoke-RestMethod -Uri "https://ifconfig.me/ip" -TimeoutSec 10).Trim() } catch { }
}

if ($myIp) {
    Write-Host "  Public IP: $myIp"
    az sql server firewall-rule create --resource-group $rgName --server $sqlServerName `
        --name postprovision-deployer --start-ip-address $myIp --end-ip-address $myIp -o none 2>$null
    Write-Host "  [done] Firewall rule added" -ForegroundColor Green
} else {
    Write-Warning "  Could not detect public IP. SQL operations may fail if your IP is not allowed."
}

# ============================================================
# 2) Grant Web App managed identity SQL access (db_owner)
# ============================================================
Write-Host ""
Write-Host "=== Step 2: Granting Web App managed identity SQL access ===" -ForegroundColor Cyan

$token = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv 2>$null
if (-not $token) {
    Write-Error "Could not obtain SQL access token."
    exit 1
}

try {
    $conn = New-Object System.Data.SqlClient.SqlConnection
    $conn.ConnectionString = "Server=tcp:${sqlFqdn},1433;Initial Catalog=${sqlDbName};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
    $conn.AccessToken = $token
    $conn.Open()

    $cmd = $conn.CreateCommand()
    $cmd.CommandText = @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = '$webAppName')
BEGIN
    CREATE USER [$webAppName] FROM EXTERNAL PROVIDER;
    ALTER ROLE db_owner ADD MEMBER [$webAppName];
END
"@
    $cmd.ExecuteNonQuery() | Out-Null
    $conn.Close()
    Write-Host "  [done] '$webAppName' added as db_owner in $sqlDbName" -ForegroundColor Green
} catch {
    Write-Warning "  SQL user provisioning failed: $_"
    Write-Warning "  Skipping seed step - database may be empty."
    exit 0
}

# ============================================================
# 3) Create schema and seed data via .NET seed tool
# ============================================================
Write-Host ""
Write-Host "=== Step 3: Creating schema and seeding database ===" -ForegroundColor Cyan

# Refresh token (may have expired during steps above)
$token = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv 2>$null

$seedDir = Join-Path $PSScriptRoot "seed-db"
Push-Location $seedDir
try {
    dotnet run --no-launch-profile -- $sqlFqdn $sqlDbName $token
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Database seed failed (exit code $LASTEXITCODE) - app will start with an empty database."
    }
} finally {
    Pop-Location
}

# ============================================================
# 4) Clean up firewall rules
# ============================================================
Write-Host ""
Write-Host "=== Step 4: Cleaning up firewall rules ===" -ForegroundColor Cyan

# Remove temp deployer rule
az sql server firewall-rule delete --resource-group $rgName --server $sqlServerName `
    --name postprovision-deployer -o none 2>$null
Write-Host "  [done] Deployer firewall rule removed" -ForegroundColor Green

# Remove "Allow Azure services" blanket rule if it exists (we use per-IP rules instead)
az sql server firewall-rule delete --resource-group $rgName --server $sqlServerName `
    --name AllowAllWindowsAzureIps -o none 2>$null
Write-Host "  [done] AllowAllWindowsAzureIps rule removed (using per-IP rules only)" -ForegroundColor Green

Write-Host ""
Write-Host "Post-provision: SQL setup complete." -ForegroundColor Green
Write-Host ""

# ============================================================
# 5) Configure SRE Agent (knowledge files, GitHub, incidents)
# ============================================================
$sreScript = Join-Path $PSScriptRoot "configure-sre-agent.ps1"
if (Test-Path $sreScript) {
    & $sreScript
} else {
    Write-Warning "configure-sre-agent.ps1 not found — skipping SRE Agent configuration"
}

Write-Host ""
Write-Host "Post-provision complete." -ForegroundColor Green
Write-Host ""
