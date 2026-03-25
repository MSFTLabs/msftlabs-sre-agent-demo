@description('Location for all resources')
param location string

@description('Tags for all resources')
param tags object

@description('Name of the SQL Server')
param sqlServerName string

@description('Name of the SQL Database')
param sqlDatabaseName string

@description('Object ID of the Entra admin (auto-set by preprovision hook)')
param aadAdminObjectId string

@description('UPN of the Entra admin (auto-set by preprovision hook)')
param aadAdminLogin string

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: sqlServerName
  location: location
  tags: tags
  properties: {
    version: '12.0'
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: 'User'
      login: aadAdminLogin
      sid: aadAdminObjectId
      tenantId: subscription().tenantId
      azureADOnlyAuthentication: true
    }
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
  name: sqlDatabaseName
  location: location
  tags: tags
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
}

// Enable auditing
resource sqlAudit 'Microsoft.Sql/servers/auditingSettings@2023-08-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
  }
}

// Enable Advanced Threat Protection
resource sqlThreatProtection 'Microsoft.Sql/servers/advancedThreatProtectionSettings@2023-08-01-preview' = {
  parent: sqlServer
  name: 'Default'
  properties: {
    state: 'Enabled'
  }
}

output sqlServerName string = sqlServer.name
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName
output sqlDatabaseName string = sqlDatabase.name
