@description('Location for SRE Agent (must be a supported region)')
@allowed(['eastus2', 'swedencentral', 'australiaeast', 'uksouth'])
param location string

@description('Tags for all resources')
param tags object

@description('Name of the SRE Agent')
param agentName string

@description('Name of the user-assigned managed identity')
param managedIdentityName string

@description('Application Insights connection string')
param applicationInsightsConnectionString string

@description('Application Insights App ID')
param applicationInsightsAppId string

@description('Object ID of the deploying user (for SRE Agent Administrator role)')
param deployerPrincipalId string

@description('Access level for the SRE Agent: High grants Contributor, Low grants Reader only')
@allowed(['High', 'Low'])
param accessLevel string = 'High'

@description('Resource group ID to monitor — Azure Monitor alerts from this group route to the agent automatically')
param managedResourceGroupId string


// Role definition IDs per access level
var roleDefinitions = {
  Low: [
    '92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Reader
    'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
  ]
  High: [
    '92aaf0da-9dab-42b6-94a3-d43ce8d16293' // Log Analytics Reader
    'acdd72a7-3385-48ef-bd42-f606fba81ae7' // Reader
    'b24988ac-6180-42a0-ab88-20f7382dd24c' // Contributor
  ]
}

// SRE Agent Administrator role definition ID
var sreAgentAdminRoleId = 'e79298df-d852-4c6d-84f9-5d13249d1e55'


// User-assigned managed identity for the SRE Agent
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: managedIdentityName
  location: location
  tags: tags
}

// Grant the managed identity RBAC roles on the resource group
resource roleAssignments 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for roleId in roleDefinitions[accessLevel]: {
  name: guid(resourceGroup().id, managedIdentity.id, roleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleId)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}]

// Deploy the SRE Agent
#disable-next-line BCP081
resource sreAgent 'Microsoft.App/agents@2025-05-01-preview' = {
  name: agentName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    knowledgeGraphConfiguration: {
      identity: managedIdentity.id
      // Azure Monitor alerts from this resource group automatically route to the agent
      managedResources: [managedResourceGroupId]
    }
    actionConfiguration: {
      accessLevel: accessLevel
      identity: managedIdentity.id
      mode: 'Review'
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: applicationInsightsAppId
        connectionString: applicationInsightsConnectionString
      }
    }
  }
  dependsOn: [
    roleAssignments
  ]
}

// Grant deploying user the SRE Agent Administrator role on the agent resource
resource sreAgentAdminRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sreAgent.id, deployerPrincipalId, sreAgentAdminRoleId)
  scope: sreAgent
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sreAgentAdminRoleId)
    principalId: deployerPrincipalId
    principalType: 'User'
  }
}

// Grant managed identity SRE Agent Administrator on the agent so the config script can call the agent ARM API
resource managedIdentitySreAgentAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sreAgent.id, managedIdentity.id, sreAgentAdminRoleId)
  scope: sreAgent
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sreAgentAdminRoleId)
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// NOTE: GitHub code integration, knowledge documents, and the SRE incident
// action group (AAD webhook) are configured post-provision via the
// configure-sre-agent.ps1 script. The ARM resource types for agent child
// resources (integrations, knowledgeDocuments) and AAD-authenticated webhooks
// are not reliably deployable through Bicep — matching the pattern used by
// the official microsoft/sre-agent sample.

output agentName string = sreAgent.name
output agentId string = sreAgent.id
output agentPortalUrl string = 'https://sre.azure.com'
output managedIdentityPrincipalId string = managedIdentity.properties.principalId
output managedIdentityClientId string = managedIdentity.properties.clientId
output managedIdentityName string = managedIdentity.name

