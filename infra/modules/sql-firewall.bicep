@description('Name of the SQL Server')
param sqlServerName string

@description('Comma-separated list of outbound IP addresses from the App Service')
param outboundIpAddresses string

var ipArray = union(split(outboundIpAddresses, ','), [])

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' existing = {
  name: sqlServerName
}

resource firewallRules 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = [for (ip, i) in ipArray: {
  parent: sqlServer
  name: 'AppServiceOutbound-${i}'
  properties: {
    startIpAddress: ip
    endIpAddress: ip
  }
}]
