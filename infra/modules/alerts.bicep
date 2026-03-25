@description('Location for alert rules')
param location string

@description('Tags for all resources')
param tags object

@description('Application Insights resource ID')
param applicationInsightsId string

@description('Log Analytics workspace resource ID')
param logAnalyticsWorkspaceId string

@description('Application Gateway resource ID')
param appGatewayResourceId string

@description('Optional email address for alert notifications')
param notificationEmail string = ''

// ============================================================
// Action Group (created only when an email is provided)
// ============================================================
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (!empty(notificationEmail)) {
  name: 'ag-sre-demo'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'SREDemo'
    enabled: true
    emailReceivers: [
      {
        name: 'DemoAdmin'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

var actionGroups = !empty(notificationEmail) ? [{ actionGroupId: actionGroup.id }] : []

// ============================================================
// Alert 1: Key Vault Access Failure (Sev 1)
// Fires when the Web App cannot read Key Vault secrets
// ============================================================
resource kvAccessAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-keyvault-access-failure'
  location: location
  tags: tags
  properties: {
    displayName: 'SRE Demo: Key Vault Access Failure'
    description: 'Web App managed identity failed to read Key Vault secrets. Likely cause: Key Vault Secrets User role assignment removed.'
    severity: 1
    enabled: false
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [applicationInsightsId]
    criteria: {
      allOf: [
        {
          query: '''
            exceptions
            | where type contains "RequestFailed" or type contains "AuthenticationFailed"
            | where outerMessage contains "Forbidden" or outerMessage contains "Unauthorized" or outerMessage contains "KeyVault"
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [for ag in actionGroups: ag.actionGroupId]
    }
  }
}

// ============================================================
// Alert 2: SQL Connectivity Failure (Sev 1)
// Fires when SQL dependency calls from the Web App fail
// ============================================================
resource sqlFailureAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-sql-connectivity-failure'
  location: location
  tags: tags
  properties: {
    displayName: 'SRE Demo: SQL Connectivity Failure'
    description: 'Web App is failing to connect to Azure SQL Database. Likely cause: SQL firewall rule AllowAllAzureIps deleted or managed identity access revoked.'
    severity: 1
    enabled: false
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [applicationInsightsId]
    criteria: {
      allOf: [
        {
          query: '''
            dependencies
            | where type == "SQL" and success == false
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 3
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [for ag in actionGroups: ag.actionGroupId]
    }
  }
}

// ============================================================
// Alert 3: WAF Security Events (Sev 2)
// Fires when the Application Gateway WAF blocks requests
// ============================================================
resource wafBlockAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-waf-blocked-requests'
  location: location
  tags: tags
  properties: {
    displayName: 'SRE Demo: WAF Blocked Requests Detected'
    description: 'Application Gateway WAF blocked requests matching OWASP rules. Investigate for potential attack or false positives.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [logAnalyticsWorkspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            AzureDiagnostics
            | where Category == "ApplicationGatewayFirewallLog"
            | where action_s == "Blocked"
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 1
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [for ag in actionGroups: ag.actionGroupId]
    }
  }
}

// ============================================================
// Alert 4: Exception Spike (Sev 2)
// Fires when unhandled exceptions exceed normal baseline
// ============================================================
resource exceptionSpikeAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-exception-spike'
  location: location
  tags: tags
  properties: {
    displayName: 'SRE Demo: Exception Rate Spike'
    description: 'Abnormally high number of unhandled exceptions detected across the application.'
    severity: 2
    enabled: false
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [applicationInsightsId]
    criteria: {
      allOf: [
        {
          query: '''
            exceptions
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 1
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [for ag in actionGroups: ag.actionGroupId]
    }
  }
}

// ============================================================
// Alert 5: Function App Error Storm (Sev 2)
// Fires when the Function App generates a burst of errors
// ============================================================
resource funcErrorStormAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-function-error-storm'
  location: location
  tags: tags
  properties: {
    displayName: 'SRE Demo: Function App Error Storm'
    description: 'High volume of error-level log entries detected from the Function App.'
    severity: 2
    enabled: false
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [logAnalyticsWorkspaceId]
    criteria: {
      allOf: [
        {
          query: '''
            FunctionAppLogs
            | where Level == "Error" or Level == "Critical"
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 1
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [for ag in actionGroups: ag.actionGroupId]
    }
  }
}

// ============================================================
// Alert 6: Application Gateway Unhealthy Backend (Sev 1)
// Fires when health probes report backend instances as down
// ============================================================
resource appGwHealthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-appgw-unhealthy-backend'
  location: 'global'
  tags: tags
  properties: {
    description: 'Application Gateway reports unhealthy backend hosts. The Web App health probe at /Health/Probe is failing.'
    severity: 1
    enabled: true
    scopes: [appGatewayResourceId]
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'UnhealthyHostCount'
          metricName: 'UnhealthyHostCount'
          operator: 'GreaterThan'
          threshold: 0
          timeAggregation: 'Average'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [for ag in actionGroups: {
      actionGroupId: ag.actionGroupId
    }]
  }
}
