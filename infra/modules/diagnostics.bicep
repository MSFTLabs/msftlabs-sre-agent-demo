@description('Log Analytics workspace ID')
param logAnalyticsWorkspaceId string

@description('Web App name')
param webAppName string

@description('SQL Server name')
param sqlServerName string

@description('SQL Database name')
param sqlDatabaseName string

// Existing resource references
resource webApp 'Microsoft.Web/sites@2023-12-01' existing = {
  name: webAppName
}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' existing = {
  name: sqlServerName
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' existing = {
  parent: sqlServer
  name: sqlDatabaseName
}

// Web App diagnostic settings
resource webAppDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: webApp
  name: 'webAppDiagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'AppServiceHTTPLogs', enabled: true }
      { category: 'AppServiceConsoleLogs', enabled: true }
      { category: 'AppServiceAppLogs', enabled: true }
      { category: 'AppServicePlatformLogs', enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics', enabled: true }
    ]
  }
}

// SQL Database diagnostic settings
resource sqlDatabaseDiag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: sqlDatabase
  name: 'sqlDatabaseDiagnostics'
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'Errors', enabled: true }
    ]
    metrics: [
      { category: 'Basic', enabled: true }
    ]
  }
}
