#!/usr/bin/env pwsh
# postprovision.ps1 - Configures deployer identity, SQL Entra admin, seeds data
# Runs automatically after 'azd provision'

$ErrorActionPreference = 'Stop'

$kvName        = $env:AZURE_KEY_VAULT_NAME
$sqlServerName = $env:AZURE_SQL_SERVER_NAME
$sqlDbName     = $env:AZURE_SQL_DATABASE_NAME
$webAppName    = $env:AZURE_WEBAPP_NAME
$rgName        = $env:AZURE_RESOURCE_GROUP
if (-not $rgName) { $rgName = "rg-$($env:AZURE_ENV_NAME)" }

if (-not $kvName)        { Write-Error "AZURE_KEY_VAULT_NAME not set."; exit 1 }
if (-not $sqlServerName) { Write-Error "AZURE_SQL_SERVER_NAME not set."; exit 1 }
if (-not $sqlDbName)     { Write-Error "AZURE_SQL_DATABASE_NAME not set."; exit 1 }
if (-not $webAppName)    { Write-Error "AZURE_WEBAPP_NAME not set."; exit 1 }

$sqlFqdn = "${sqlServerName}.database.windows.net"

# ============================================================
# 1) Detect deployer identity, set SQL Entra admin, add firewall rule
# ============================================================
Write-Host ""
Write-Host "=== Step 1: Configuring deployer identity and SQL Entra admin ===" -ForegroundColor Cyan

# Detect deployer identity
$deployerObjectId = az ad signed-in-user show --query id -o tsv 2>$null
$deployerLogin    = az ad signed-in-user show --query userPrincipalName -o tsv 2>$null
if (-not $deployerObjectId -or -not $deployerLogin) {
    Write-Error "Could not detect signed-in user. Run 'az login' first."
    exit 1
}
Write-Host "  Deployer:  $deployerLogin ($deployerObjectId)" -ForegroundColor White

# Set SQL Entra admin (Entra-only auth, no local SQL admin per MCAPS policy)
Write-Host "  Setting SQL Entra admin..."
az sql server ad-admin create --resource-group $rgName --server-name $sqlServerName `
    --display-name $deployerLogin --object-id $deployerObjectId -o none
az sql server ad-only-auth enable --resource-group $rgName --server-name $sqlServerName -o none
Write-Host "  [done] SQL Entra-only admin set: $deployerLogin" -ForegroundColor Green

# Assign deployer Key Vault Secrets Officer (needed to store passwords in Step 3)
Write-Host "  Assigning Key Vault Secrets Officer to deployer..."
$kvId = az keyvault show --name $kvName --query id -o tsv 2>$null
az role assignment create --role "Key Vault Secrets Officer" `
    --assignee-object-id $deployerObjectId --assignee-principal-type User `
    --scope $kvId -o none 2>$null
Write-Host "  [done] Key Vault Secrets Officer assigned" -ForegroundColor Green

# Assign deployer Owner on RG (for SRE Agent portal to list the resource group)
Write-Host "  Assigning Owner role on resource group..."
$rgId = az group show --name $rgName --query id -o tsv 2>$null
az role assignment create --role "Owner" `
    --assignee-object-id $deployerObjectId --assignee-principal-type User `
    --scope $rgId -o none 2>$null
Write-Host "  [done] Owner role assigned on $rgName" -ForegroundColor Green

# Detect public IP and add temporary firewall rule
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
    Write-Host "  [done] SQL firewall rule added for deployer IP" -ForegroundColor Green
} else {
    Write-Warning "  Could not detect public IP. SQL operations may fail if your IP is not allowed."
}

# ============================================================
# 2) Wait for RBAC propagation
# ============================================================
Write-Host ""
Write-Host "=== Step 2: Waiting for role assignments to propagate ===" -ForegroundColor Cyan
Write-Host "  Waiting 30 seconds for RBAC propagation..."
Start-Sleep -Seconds 30
Write-Host "  [done]" -ForegroundColor Green
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
Write-Host "=== Step 3: Storing demo user passwords in Key Vault: $kvName ===" -ForegroundColor Cyan
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
# 4) Grant Web App managed identity SQL access (db_owner)
# ============================================================
Write-Host ""
Write-Host "=== Step 4: Granting Web App managed identity SQL access ===" -ForegroundColor Cyan

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
# 5) Create schema and seed data via .NET seed tool
# ============================================================
Write-Host ""
Write-Host "=== Step 5: Creating schema and seeding database ===" -ForegroundColor Cyan

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
# 6) Clean up temp firewall rule
# ============================================================
Write-Host ""
Write-Host "=== Step 6: Cleaning up deployer firewall rule ===" -ForegroundColor Cyan
az sql server firewall-rule delete --resource-group $rgName --server $sqlServerName `
    --name postprovision-deployer -o none 2>$null
Write-Host "  [done] Firewall rule removed" -ForegroundColor Green

Write-Host ""
Write-Host "Post-provision complete." -ForegroundColor Green
Write-Host ""
