@description('Principal ID of the Function App managed identity')
param principalId string

// User Access Administrator - allows managing role assignments (for chaos engineering)
resource uaaRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// SQL Server Contributor - allows managing SQL firewall rules (for chaos engineering)
resource sqlContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, '6d8ee4ec-f05a-4a1d-8b00-a9b17e38b437')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '6d8ee4ec-f05a-4a1d-8b00-a9b17e38b437')
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
