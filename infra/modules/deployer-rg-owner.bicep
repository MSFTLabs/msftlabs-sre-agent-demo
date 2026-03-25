@description('Object ID of the deploying user')
param principalId string

// Owner built-in role
var ownerRoleId = '8e3af657-a8ff-443c-a75c-2fe8c4bcb635'

resource ownerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, ownerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', ownerRoleId)
    principalId: principalId
    principalType: 'User'
  }
}
