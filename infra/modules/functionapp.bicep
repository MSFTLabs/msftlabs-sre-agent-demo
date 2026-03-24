@description('Location for all resources')
param location string

@description('Tags for all resources')
param tags object

@description('Name of the Function App')
param functionAppName string

@description('Name of the Storage Account')
param storageAccountName string

@description('Resource ID of the shared App Service Plan')
param appServicePlanId string

@description('Application Insights connection string')
param applicationInsightsConnectionString string

@description('Key Vault name')
param keyVaultName string

@description('Web App managed identity principal ID')
param webAppPrincipalId string

@description('SQL Server name')
param sqlServerName string

@description('Application Gateway URL')
param appGatewayUrl string

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: functionAppName
  location: location
  tags: union(tags, { 'azd-service-name': 'api' })
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'Python|3.11'
      alwaysOn: true
      ftpsState: 'Disabled'
      appSettings: [
        { name: 'AzureWebJobsStorage', value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}' }
        { name: 'AzureWebJobsFeatureFlags', value: 'EnableWorkerIndexing' }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: applicationInsightsConnectionString }
        { name: 'KeyVaultName', value: keyVaultName }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'true' }
        { name: 'AZURE_SUBSCRIPTION_ID', value: subscription().subscriptionId }
        { name: 'RESOURCE_GROUP_NAME', value: resourceGroup().name }
        { name: 'WEBAPP_PRINCIPAL_ID', value: webAppPrincipalId }
        { name: 'SQL_SERVER_NAME', value: sqlServerName }
        { name: 'APP_GATEWAY_URL', value: appGatewayUrl }
      ]
    }
  }
}

output functionAppName string = functionApp.name
output functionAppUrl string = 'https://${functionApp.properties.defaultHostName}'
output functionAppPrincipalId string = functionApp.identity.principalId
