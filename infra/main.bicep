targetScope = 'subscription'

@description('Name of the environment')
param environmentName string

@description('Primary location for all resources')
param location string

@description('Object ID of the deploying user (auto-set by preprovision hook)')
param sqlAadAdminObjectId string

@description('UPN of the deploying user (auto-set by preprovision hook)')
param sqlAadAdminLogin string

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = { 'azd-env-name': environmentName }
var rgName = 'rg-${environmentName}'

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

// Monitoring: Log Analytics + Application Insights
module monitoring 'modules/monitoring.bicep' = {
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    logAnalyticsName: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
    applicationInsightsName: '${abbrs.insightsComponents}${resourceToken}'
  }
}

// SQL Server + Database (Entra-only auth required by MCAPS policy at creation time)
module sql 'modules/sql.bicep' = {
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    sqlServerName: '${abbrs.sqlServers}${resourceToken}'
    sqlDatabaseName: 'sredemodb'
    aadAdminObjectId: sqlAadAdminObjectId
    aadAdminLogin: sqlAadAdminLogin
  }
}

// Key Vault with secrets
module keyVault 'modules/keyvault.bicep' = {
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    keyVaultName: '${abbrs.keyVaultVaults}${resourceToken}'
    sqlServerFqdn: sql.outputs.sqlServerFqdn
    sqlDatabaseName: 'sredemodb'
    appInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
  }
}

// App Service Plan + Web App
module appService 'modules/appservice.bicep' = {
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    appServicePlanName: '${abbrs.webServerFarms}${resourceToken}'
    webAppName: '${abbrs.webSitesAppService}${resourceToken}'
    keyVaultName: keyVault.outputs.keyVaultName
    applicationInsightsConnectionString: monitoring.outputs.applicationInsightsConnectionString
    sqlServerName: sql.outputs.sqlServerName
    sqlDatabaseName: 'sredemodb'
    appGatewayUrl: 'http://${toLower('${abbrs.networkApplicationGateways}${resourceToken}')}.${location}.cloudapp.azure.com'
  }
}

// Application Gateway with WAF
module appGateway 'modules/appgateway.bicep' = {
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    vnetName: '${abbrs.networkVirtualNetworks}${resourceToken}'
    publicIpName: '${abbrs.networkPublicIPAddresses}${resourceToken}'
    wafPolicyName: '${abbrs.networkApplicationGatewayWebApplicationFirewallPolicies}${resourceToken}'
    appGatewayName: '${abbrs.networkApplicationGateways}${resourceToken}'
    webAppFqdn: appService.outputs.webAppFqdn
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
  }
}

// Key Vault RBAC: grant Web App access to secrets
module webKvAccess 'modules/keyvault-access.bicep' = {
  scope: resourceGroup
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    principalId: appService.outputs.webAppPrincipalId
  }
}

// Key Vault RBAC: grant deploying user Secrets Officer (for postprovision password seeding)
module deployerKvOfficer 'modules/keyvault-officer.bicep' = {
  scope: resourceGroup
  params: {
    keyVaultName: keyVault.outputs.keyVaultName
    principalId: sqlAadAdminObjectId
  }
}

// SQL RBAC: grant Web App managed identity db access
module webSqlAccess 'modules/sql-access.bicep' = {
  scope: resourceGroup
  params: {
    sqlServerName: sql.outputs.sqlServerName
    principalId: appService.outputs.webAppPrincipalId
  }
}

// Owner on RG for deployer (required for SRE Agent portal to list the resource group)
module deployerRgOwner 'modules/deployer-rg-owner.bicep' = {
  scope: resourceGroup
  params: {
    principalId: sqlAadAdminObjectId
  }
}

// SRE Agent alert rules
module alerts 'modules/alerts.bicep' = {
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    applicationInsightsId: monitoring.outputs.applicationInsightsId
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    appGatewayResourceId: appGateway.outputs.appGatewayId
  }
}

// Diagnostic settings for all resources → Log Analytics
module diagnostics 'modules/diagnostics.bicep' = {
  scope: resourceGroup
  params: {
    logAnalyticsWorkspaceId: monitoring.outputs.logAnalyticsWorkspaceId
    webAppName: appService.outputs.webAppName
    keyVaultName: keyVault.outputs.keyVaultName
    sqlServerName: sql.outputs.sqlServerName
    sqlDatabaseName: 'sredemodb'
    storageAccountName: '${abbrs.storageStorageAccounts}${resourceToken}'
  }
}

output AZURE_RESOURCE_GROUP string = resourceGroup.name
output AZURE_WEBAPP_NAME string = appService.outputs.webAppName
output AZURE_WEBAPP_URL string = appService.outputs.webAppUrl
output AZURE_KEY_VAULT_NAME string = keyVault.outputs.keyVaultName
output AZURE_SQL_SERVER_NAME string = sql.outputs.sqlServerName
output AZURE_SQL_SERVER_FQDN string = sql.outputs.sqlServerFqdn
output AZURE_SQL_DATABASE_NAME string = sql.outputs.sqlDatabaseName
output AZURE_APP_GATEWAY_URL string = 'http://${appGateway.outputs.appGatewayFqdn}'
output AZURE_APP_GATEWAY_IP string = appGateway.outputs.appGatewayPublicIp
