@description('Name of the SQL Server')
param sqlServerName string

@description('Principal ID to grant SQL DB Contributor role')
param principalId string

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' existing = {
  name: sqlServerName
}

// SQL DB Contributor role
resource sqlRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: sqlServer
  name: guid(sqlServer.id, principalId, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
