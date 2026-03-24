#!/usr/bin/env pwsh
# postprovision.ps1 - Provisions database schema, seeds data, and configures access
# Runs automatically after 'azd provision'

$ErrorActionPreference = 'Stop'

$kvName        = $env:AZURE_KEY_VAULT_NAME
$sqlServerName = $env:AZURE_SQL_SERVER_NAME
$sqlDbName     = $env:AZURE_SQL_DATABASE_NAME
$webAppName    = $env:AZURE_WEBAPP_NAME

if (-not $kvName)        { Write-Error "AZURE_KEY_VAULT_NAME not set."; exit 1 }
if (-not $sqlServerName) { Write-Error "AZURE_SQL_SERVER_NAME not set."; exit 1 }
if (-not $sqlDbName)     { Write-Error "AZURE_SQL_DATABASE_NAME not set."; exit 1 }
if (-not $webAppName)    { Write-Error "AZURE_WEBAPP_NAME not set."; exit 1 }

$sqlFqdn = "${sqlServerName}.database.windows.net"

# ============================================================
# 1) Generate random passwords for demo users → Key Vault
# ============================================================
$usernames = @('admin', 'jmorales', 'akovacs', 'schen', 'bmurphy', 'pnakamura', 'dwilliams', 'lpetrova', 'rsingh', 'efischer', 'okim')

function New-RandomPassword {
    param([int]$Length = 16)
    $upper   = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower   = 'abcdefghjkmnpqrstuvwxyz'
    $digits  = '23456789'
    $special = '!@#$&'
    $chars = @()
    $chars += $upper[(Get-Random -Maximum $upper.Length)]
    $chars += $lower[(Get-Random -Maximum $lower.Length)]
    $chars += $digits[(Get-Random -Maximum $digits.Length)]
    $chars += $special[(Get-Random -Maximum $special.Length)]
    $pool = $upper + $lower + $digits + $special
    for ($i = $chars.Count; $i -lt $Length; $i++) {
        $chars += $pool[(Get-Random -Maximum $pool.Length)]
    }
    return -join ($chars | Get-Random -Count $chars.Count)
}

Write-Host ""
Write-Host "=== Step 1: Storing demo user passwords in Key Vault: $kvName ===" -ForegroundColor Cyan
Write-Host ""

foreach ($username in $usernames) {
    $secretName = "user-password-$username"
    $existing = $null
    try { $existing = az keyvault secret show --vault-name $kvName --name $secretName --query "value" -o tsv 2>$null } catch { }
    if ($existing) {
        Write-Host "  [skip]    $secretName (already exists)" -ForegroundColor Yellow
        continue
    }
    $password = New-RandomPassword
    az keyvault secret set --vault-name $kvName --name $secretName --value $password --output none 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "  [failed]  $secretName - check Key Vault RBAC permissions"
    } else {
        Write-Host "  [created] $secretName" -ForegroundColor Green
    }
}

# ============================================================
# 2) Add temp firewall rule for deployer IP
# ============================================================
Write-Host ""
Write-Host "=== Step 2: Configuring SQL firewall for deployer ===" -ForegroundColor Cyan

# Detect current public IP
$myIp = (az rest --method get --url "https://api.ipify.org" -o tsv 2>$null)
if (-not $myIp) {
    # Fallback: try to connect and parse from error
    Write-Warning "Could not detect public IP. Attempting to add AllowAllAzure rule."
    az sql server firewall-rule create --resource-group rg-sre-demo --server $sqlServerName `
        --name AllowAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 -o none 2>$null
} else {
    Write-Host "  Deployer IP: $myIp"
    az sql server firewall-rule create --resource-group rg-sre-demo --server $sqlServerName `
        --name postprovision-deployer --start-ip-address $myIp --end-ip-address $myIp -o none 2>$null
    Write-Host "  [done] Firewall rule added" -ForegroundColor Green
}

# ============================================================
# 3) Grant Web App managed identity SQL access
# ============================================================
Write-Host ""
Write-Host "=== Step 3: Granting Web App managed identity SQL access ===" -ForegroundColor Cyan

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
}

# ============================================================
# 4) Create schema and seed data via .NET seed tool
# ============================================================
Write-Host ""
Write-Host "=== Step 4: Creating schema and seeding database ===" -ForegroundColor Cyan

# Refresh token (may have expired during steps above)
$token = az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv 2>$null

$seedDir = Join-Path $PSScriptRoot "seed-db"
Push-Location $seedDir
try {
    dotnet run --no-launch-profile -- $sqlFqdn $sqlDbName $token $kvName
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Database seed failed (exit code $LASTEXITCODE)"
    }
} finally {
    Pop-Location
}

# ============================================================
# 5) Clean up temp firewall rule
# ============================================================
Write-Host ""
Write-Host "=== Step 5: Cleaning up deployer firewall rule ===" -ForegroundColor Cyan
az sql server firewall-rule delete --resource-group rg-sre-demo --server $sqlServerName `
    --name postprovision-deployer -o none 2>$null
Write-Host "  [done] Firewall rule removed" -ForegroundColor Green

Write-Host ""
Write-Host "Post-provision complete." -ForegroundColor Green
Write-Host ""
