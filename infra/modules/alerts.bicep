@description('Location for alert rules')
param location string

@description('Tags for all resources')
param tags object

@description('Application Gateway resource ID')
param appGatewayResourceId string

@description('Optional email address for alert notifications')
param notificationEmail string = ''

@description('Optional SRE Agent action group ID — when provided, Azure Monitor alerts are routed to the SRE Agent as incidents')
param sreAgentActionGroupId string = ''

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

var actionGroups = concat(
  !empty(notificationEmail) ? [{ actionGroupId: actionGroup.id }] : [],
  !empty(sreAgentActionGroupId) ? [{ actionGroupId: sreAgentActionGroupId }] : []
)

// ============================================================
// Application Gateway Unhealthy Backend (Sev 1)
// Fires when health probes report backend instances as down.
// This is the primary alert for the demo — when SQL public
// network access is disabled, the health probe fails and the
// AppGW returns 502 Bad Gateway.
// ============================================================
resource appGwHealthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-appgw-unhealthy-backend'
  location: 'global'
  tags: tags
  properties: {
    description: 'Application Gateway reports unhealthy backend hosts. The Web App health probe at /Health/Probe is failing — likely caused by SQL connectivity loss (public network access disabled).'
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
