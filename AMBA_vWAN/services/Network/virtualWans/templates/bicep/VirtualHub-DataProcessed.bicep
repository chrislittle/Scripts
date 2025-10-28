@description('Action Group resource id to invoke when the alert fires')
param actionGroupResourceId string

@description('Name of the alert')
@minLength(1)
param alertName string

@description('Description of alert')
param alertDescription string = 'Virtual Hub Data Processed - Alert when hub data processing approaches capacity'

@description('Virtual Hub resource id to be monitored')
param virtualHubResourceId string

@description('Azure region in which target resources to be monitored are in (without spaces). For example: EastUS')
param targetResourceRegion string

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

@description('Number of routing infrastructure units (RIUs) for the Virtual Hub (each RIU = 1 Gbps capacity)')
@minValue(2)
@maxValue(50)
param routingInfrastructureUnits int = 2

@description('Percentage threshold for data processing utilization (default 80%)')
@minValue(1)
@maxValue(100)
param thresholdPercentage int = 80

@description('Time period in minutes for threshold calculation (default 15 minutes)')
@minValue(1)
@maxValue(1440)
param thresholdPeriodMinutes int = 15

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

// Calculate threshold based on customer-provided routing infrastructure units
// Each RIU provides 1 Gbps throughput capacity in vWAN
var maxThroughputGbps = routingInfrastructureUnits * 1  // 1 Gbps per RIU
var maxThroughputBytesPerSecond = maxThroughputGbps * 125000000  // Convert Gbps to bytes/sec
var thresholdBytesPerPeriod = (maxThroughputBytesPerSecond * thresholdPercentage / 100) * (thresholdPeriodMinutes * 60)

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
    description: '${alertDescription}. Threshold: ${thresholdBytesPerPeriod} bytes over ${thresholdPeriodMinutes}min (${thresholdPercentage}% of ${maxThroughputGbps} Gbps capacity based on ${routingInfrastructureUnits} routing infrastructure units)'
    scopes: [
      virtualHubResourceId
    ]
    targetResourceType: 'Microsoft.Network/virtualHubs'
    targetResourceRegion: targetResourceRegion
    severity: alertSeverity
    enabled: enabled
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    autoMitigate: autoMitigate
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'VirtualHubDataProcessed'
          metricName: 'VirtualHubDataProcessed'
          metricNamespace: 'Microsoft.Network/virtualHubs'
          dimensions: []
          operator: operator
          threshold: thresholdBytesPerPeriod
          timeAggregation: timeAggregation
          criterionType: 'StaticThresholdCriterion'
          skipMetricValidation: false
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroupResourceId
        webHookProperties: {}
      }
    ]
  }
}

@description('The resource ID of the metric alert.')
output resourceId string = metricAlert.id

@description('The resource group the metric alert was deployed into.')
output resourceGroupName string = resourceGroup().name

@description('The name of the metric alert.')
output name string = metricAlert.name

@description('Number of routing infrastructure units used for calculation')
output routingInfrastructureUnits int = routingInfrastructureUnits

@description('Calculated maximum throughput in Gbps')
output maxThroughputGbps int = maxThroughputGbps

@description('Applied threshold in bytes')
output thresholdBytes int = thresholdBytesPerPeriod

@description('Threshold percentage used')
output thresholdPercentage int = thresholdPercentage
