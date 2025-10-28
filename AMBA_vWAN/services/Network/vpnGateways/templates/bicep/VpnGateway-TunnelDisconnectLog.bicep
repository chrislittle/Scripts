@description('Location for the alert.')
@minLength(1)
param location string = resourceGroup().location

@description('Name of the alert')
@minLength(1)
param alertName string

@description('Description of alert')
param alertDescription string = 'S2S VPN Tunnel Disconnect Events - Log Alert for tunnel disconnection events'

@description('Specifies whether the alert is enabled')
param isEnabled bool = true

@description('Specifies whether to check linked storage and fail creation if the storage was not found')
param checkWorkspaceAlertsStorageConfigured bool = false

@description('Full Resource ID of the Log Analytics workspace emitting the log that will be used for the comparison.')
@minLength(1)
param workspaceId string

@description('Severity of alert {0,1,2,3,4}')
@allowed([
  0
  1
  2
  3
  4
])
param alertSeverity int = 1

@description('how often the alert is evaluated represented in ISO 8601 duration format')
@allowed([
  'PT1M'
  'PT5M'
  'PT15M'
  'PT30M'
  'PT1H'
])
param evaluationFrequency string = 'PT5M'

@description('The period of time (in ISO 8601 duration format) that is used to monitor alert activity based on the threshold.')
@allowed([
  'PT1M'
  'PT5M'
  'PT15M'
  'PT30M'
  'PT1H'
  'PT6H'
  'PT12H'
  'P1D'
])
param windowSize string = 'PT5M'

@description('Tags of the resource.')
param tags object = {}

@description('How the data that is collected should be combined over time.')
param autoMitigate bool = true

// =============== //
// Variables       //
// =============== //

var query = 'AzureDiagnostics | where Category == "TunnelDiagnosticLog" | where OperationName == "TunnelDisconnected"'

// =============== //
// Resources       //
// =============== //

resource scheduledQueryRule 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: alertName
  location: location
  tags: union(tags, {
    _deployed_by_amba: 'true'
  })
  properties: {
    description: alertDescription
    displayName: alertName
    severity: alertSeverity
    enabled: isEnabled
    scopes: [
      workspaceId
    ]
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    autoMitigate: autoMitigate
    checkWorkspaceAlertsStorageConfigured: checkWorkspaceAlertsStorageConfigured
    criteria: {
      allOf: [
        {
          query: query
          timeAggregation: 'Count'
          dimensions: []
          resourceIdColumn: '_ResourceId'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
  }
}

@description('The resource ID of the scheduled query rule.')
output resourceId string = scheduledQueryRule.id

@description('The resource group the scheduled query rule was deployed into.')
output resourceGroupName string = resourceGroup().name

@description('The name of the scheduled query rule.')
output name string = scheduledQueryRule.name

// =============== //
