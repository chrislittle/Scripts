@description('Name of the alert')
@minLength(1)
param alertName string

@description('Description of alert')
param alertDescription string = 'S2S VPN Tunnel Packet Drop - Alert when tunnel egress or ingress packet drops detected'

@description('Array of Azure resource Ids. For example - /subscriptions/00000000-0000-0000-0000-0000-00000000/resourceGroup/resource-group-name/Microsoft.Network/vpnGateways/gateway-name')
@minLength(1)
param targetResourceId array

@description('Azure region in which target resources to be monitored are in (without spaces). For example: EastUS')
param targetResourceRegion string

@description('Resource type of target resources to be monitored.')
@minLength(1)
param targetResourceType string

@description('Severity of alert {0,1,2,3,4}')
@allowed([
  0
  1
  2
  3
  4
])
param alertSeverity int = 2

@description('Operator to be used in the evaluation operation')
@allowed([
  'Equals'
  'GreaterThan'
  'GreaterThanOrEqual'
  'LessThan'
  'LessThanOrEqual'
])
param operator string = 'GreaterThan'

@description('Threshold value associated with a metric trigger.')
param threshold int = 0

@description('how often the metric alert is evaluated represented in ISO 8601 duration format')
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
param windowSize string = 'PT15M'

@description('The aggregation type')
@allowed([
  'Average'
  'Minimum'
  'Maximum'
  'Total'
  'Count'
])
param timeAggregation string = 'Total'

@description('Tags of the resource.')
param tags object = {}

@description('How the data that is collected should be combined over time.')
param autoMitigate bool = true

@description('The flag which indicates whether this alert is enabled.')
param enabled bool = true

@description('the list of resource id\'s that this metric alert is scoped to.')
param scopes array = targetResourceId

// =============== //
// Resources       //
// =============== //

resource metricAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: alertName
  location: 'global'
  tags: union(tags, {
    _deployed_by_amba: 'true'
  })
  properties: {
    description: alertDescription
    scopes: scopes
    targetResourceType: targetResourceType
    targetResourceRegion: targetResourceRegion
    severity: alertSeverity
    enabled: enabled
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    autoMitigate: autoMitigate
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Tunnel Egress Packet Drop Count'
          metricName: 'TunnelEgressPacketDropCount'
          metricNamespace: 'Microsoft.Network/vpnGateways'
          dimensions: [
            {
              name: 'ConnectionName'
              operator: 'Include'
              values: ['*']
            }
            {
              name: 'RemoteIP'
              operator: 'Include'
              values: ['*']
            }
          ]
          operator: operator
          threshold: threshold
          timeAggregation: timeAggregation
          criterionType: 'StaticThresholdCriterion'
        }
        {
          name: 'Tunnel Ingress Packet Drop Count'
          metricName: 'TunnelIngressPacketDropCount'
          metricNamespace: 'Microsoft.Network/vpnGateways'
          dimensions: [
            {
              name: 'ConnectionName'
              operator: 'Include'
              values: ['*']
            }
            {
              name: 'RemoteIP'
              operator: 'Include'
              values: ['*']
            }
          ]
          operator: operator
          threshold: threshold
          timeAggregation: timeAggregation
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
  }
}

@description('The resource ID of the metric alert.')
output resourceId string = metricAlert.id

@description('The resource group the metric alert was deployed into.')
output resourceGroupName string = resourceGroup().name

@description('The name of the metric alert.')
output name string = metricAlert.name
