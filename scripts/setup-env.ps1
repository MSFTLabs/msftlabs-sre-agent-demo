#!/usr/bin/env pwsh
# setup-env.ps1 - Initializes the azd environment (.azure/<envName>/.env)
# Equivalent to 'azd init' + populating all required values from Azure CLI.
# Prompts for environment name, subscription, and location.

$ErrorActionPreference = 'Stop'

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  MSFTLabs SRE Demo - Environment Setup"   -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================
# 1) Verify Azure CLI is logged in
# ============================================================
Write-Host "=== Checking Azure CLI login ===" -ForegroundColor Cyan

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Error "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
}

Write-Host "  Logged in as: $($account.user.name)" -ForegroundColor Green

# ============================================================
# 2) Prompt for environment name
# ============================================================
Write-Host ""
$envName = Read-Host "Enter a new environment name"
if (-not $envName) {
    Write-Error "Environment name is required."
    exit 1
}
if ($envName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$') {
    Write-Error "Environment name must start with a letter or number and contain only letters, numbers, and hyphens (max 63 chars)."
    exit 1
}

$projectRoot = Split-Path $PSScriptRoot -Parent
$envDir = Join-Path $projectRoot ".azure" $envName
if (Test-Path $envDir) {
    Write-Warning "Environment '$envName' already exists at $envDir"
    $overwrite = Read-Host "  Overwrite? (y/N)"
    if ($overwrite -ne 'y') {
        Write-Host "  Aborted." -ForegroundColor Yellow
        exit 0
    }
}

# ============================================================
# 3) Select Azure subscription
# ============================================================
Write-Host ""
Write-Host "=== Select Azure subscription ===" -ForegroundColor Cyan

$subscriptions = az account list --query "[?state=='Enabled']" --output json 2>$null | ConvertFrom-Json
if (-not $subscriptions -or $subscriptions.Count -eq 0) {
    Write-Error "No enabled Azure subscriptions found."
    exit 1
}

Write-Host ""
for ($i = 0; $i -lt $subscriptions.Count; $i++) {
    $current = if ($subscriptions[$i].isDefault) { " (current)" } else { "" }
    Write-Host "  [$($i + 1)] $($subscriptions[$i].name) ($($subscriptions[$i].id))$current"
}
Write-Host ""

$defaultIndex = ($subscriptions | ForEach-Object { $_.isDefault }).IndexOf($true) + 1
if ($defaultIndex -le 0) { $defaultIndex = 1 }

$subChoice = Read-Host "Select a subscription (default: $defaultIndex)"
if (-not $subChoice) { $subChoice = $defaultIndex }
$subIndex = [int]$subChoice - 1
if ($subIndex -lt 0 -or $subIndex -ge $subscriptions.Count) {
    Write-Error "Invalid selection."
    exit 1
}

$subscriptionId   = $subscriptions[$subIndex].id
$subscriptionName = $subscriptions[$subIndex].name
$tenantId         = $subscriptions[$subIndex].tenantId

az account set --subscription $subscriptionId 2>$null
Write-Host "  Using: $subscriptionName ($subscriptionId)" -ForegroundColor Green

# ============================================================
# 4) Verify Owner role on subscription
# ============================================================
Write-Host ""
Write-Host "=== Verifying subscription permissions ===" -ForegroundColor Cyan

$userObjectId = az ad signed-in-user show --query id -o tsv 2>$null
$userLogin    = az ad signed-in-user show --query userPrincipalName -o tsv 2>$null
if (-not $userObjectId -or -not $userLogin) {
    Write-Error "Could not detect signed-in user. Ensure you are logged in with 'az login'."
    exit 1
}

# Check for Owner role (built-in role definition ID: 8e3af657-a8ff-443c-a75c-2fe8c4bcb635)
$ownerAssignment = az role assignment list `
    --assignee $userObjectId `
    --scope "/subscriptions/$subscriptionId" `
    --role "Owner" `
    --query "[0].id" -o tsv 2>$null

if (-not $ownerAssignment) {
    Write-Host ""
    Write-Error "You do not have the Owner role on subscription '$subscriptionName'.`nOwner is required for this deployment (creates role assignments, SQL Entra admin, etc.).`nRequest Owner access and try again."
    exit 1
}

Write-Host "  Owner role confirmed" -ForegroundColor Green
Write-Host "  User:      $userLogin"
Write-Host "  Object ID: $userObjectId"

# ============================================================
# 5) Select Azure location
# ============================================================
Write-Host ""
Write-Host "=== Select Azure location ===" -ForegroundColor Cyan

$defaultLocation = "centralus"
$location = Read-Host "Enter an Azure location (default: $defaultLocation)"
if (-not $location) { $location = $defaultLocation }

# Validate the location exists
$validLocations = az account list-locations --query "[?metadata.regionType=='Physical'].name" -o json 2>$null | ConvertFrom-Json
if ($location -notin $validLocations) {
    Write-Error "Invalid location '$location'. Run 'az account list-locations -o table' to see available locations."
    exit 1
}

Write-Host "  Location: $location" -ForegroundColor Green

# ============================================================
# 6) Create .azure/<envName>/.env
# ============================================================
Write-Host ""
Write-Host "=== Creating azd environment ===" -ForegroundColor Cyan

if (-not (Test-Path $envDir)) {
    New-Item -ItemType Directory -Path $envDir -Force | Out-Null
}

$envContent = @"
AZURE_ENV_NAME="$envName"
AZURE_LOCATION="$location"
AZURE_SUBSCRIPTION_ID="$subscriptionId"
AZURE_PRINCIPAL_ID="$userObjectId"
AZURE_AAD_ADMIN_LOGIN="$userLogin"
"@

$envFilePath = Join-Path $envDir ".env"
Set-Content -Path $envFilePath -Value $envContent -Encoding UTF8

# Create the config.json to mark this as the default environment
$configPath = Join-Path $projectRoot ".azure" "config.json"
$configJson = @{ defaultEnvironment = $envName } | ConvertTo-Json
Set-Content -Path $configPath -Value $configJson -Encoding UTF8

Write-Host "  [done] Created $envFilePath" -ForegroundColor Green
Write-Host "  [done] Set '$envName' as default environment" -ForegroundColor Green

# ============================================================
# Summary
# ============================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Environment setup complete!"              -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Environment:     $envName"
Write-Host "  Subscription:    $subscriptionName"
Write-Host "  Location:        $location"
Write-Host "  User:            $userLogin"
Write-Host "  Principal ID:    $userObjectId"
Write-Host ""
Write-Host "  Run 'azd up' to provision and deploy." -ForegroundColor Cyan
Write-Host ""
