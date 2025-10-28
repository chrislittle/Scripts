@description('Name of the alert')
@minLength(1)
param alertName string

@description('Description of alert')
param alertDescription string = 'ExpressRoute Gateway Connection Bits Out Per Second - Monitoring egress bandwidth utilization. Alerts when bandwidth exceeds capacity thresholds. Uses real gateway scale unit detection for accurate thresholds.'

@description('Array of Azure resource Ids. For example - /subscriptions/00000000-0000-0000-0000-0000-00000000/resourceGroup/resource-group-name/Microsoft.Network/expressRouteGateways/gateway-name')
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
param alertSeverity int = 0

@description('Operator to be used in the evaluation operation')
@allowed([
  'Equals'
  'GreaterThan'
  'GreaterThanOrEqual'
  'LessThan'
  'LessThanOrEqual'
])
param operator string = 'GreaterThan'

@description('Auto-detect threshold based on actual gateway scale unit configuration. When true, threshold is calculated from the gateway minimum scale units.')
param autoDetectThreshold bool = true

@description('Manual threshold value in bits per second. Use this when autoDetectThreshold is false. For vWAN ExpressRoute Gateways: each scale unit = 1 Gbps (1,000,000,000 bps).')
param manualThreshold int = 1

@description('Percentage of maximum capacity to use as threshold when auto-detecting (e.g., 80 means alert when above 80% of capacity)')
@minValue(50)
@maxValue(95)
param thresholdPercentage int = 80

@description('how often the metric alert is evaluated represented in ISO 8601 duration format')
@allowed([
  'PT1M'
  'PT5M'
  'PT15M'
  'PT30M'
  'PT1H'
])
param evaluationFrequency string = 'PT5M'

@description('The interval of time (aggregation granularity) in ISO 8601 duration format')
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

@description('how the metric is aggregated over time')
@allowed([
  'Average'
  'Minimum'
  'Maximum'
  'Total'
  'Count'
])
param timeAggregation string = 'Average'

@description('Specifies whether the alert is enabled')
param isEnabled bool = true

// ExpressRoute Gateway SKU definitions with bandwidth capacity in Mbps
// Based on Azure documentation: https://learn.microsoft.com/en-us/azure/expressroute/expressroute-about-virtual-network-gateways

// vWAN ExpressRoute Gateways use scale units (not traditional SKUs)
// Each scale unit provides 1 Gbps bandwidth capacity
var scaleUnitCapacityMbps = 1000 // 1 Gbps per scale unit for vWAN ExpressRoute Gateways

// Reference the existing gateway to get actual scale unit configuration
resource existingGateway 'Microsoft.Network/expressRouteGateways@2023-04-01' existing = {
  name: split(targetResourceId[0], '/')[8] // Extract gateway name from resource ID
  scope: resourceGroup(split(targetResourceId[0], '/')[4]) // Extract resource group from resource ID
}

// Calculate actual capacity based on gateway configuration
// vWAN ExpressRoute Gateways use autoScaleConfiguration.bounds.min for guaranteed capacity
var actualMinScaleUnits = existingGateway.properties.autoScaleConfiguration.bounds.min
var actualMaxScaleUnits = existingGateway.properties.autoScaleConfiguration.bounds.max
var guaranteedCapacityMbps = actualMinScaleUnits * scaleUnitCapacityMbps

// Use actual gateway capacity when auto-detecting, fallback to manual threshold
var thresholdBitsPerSecond = autoDetectThreshold 
  ? (guaranteedCapacityMbps * 1000000 * thresholdPercentage / 100) // Convert Mbps to bps and apply percentage
  : manualThreshold

resource metricAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: alertName
  location: 'global'
  tags: {
    _deployed_by_amba: 'true'
  }
  properties: {
    description: alertDescription
    scopes: targetResourceId
    targetResourceType: targetResourceType
    targetResourceRegion: targetResourceRegion
    severity: alertSeverity
    enabled: isEnabled
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: '1st criterion'
          metricName: 'ERGatewayConnectionBitsOutPerSecond'
          dimensions: []
          operator: operator
          threshold: thresholdBitsPerSecond
          timeAggregation: timeAggregation
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
  }
}

output alertId string = metricAlert.id
output calculatedThreshold int = thresholdBitsPerSecond
output skuInfo object = {
  detectedMinScaleUnits: actualMinScaleUnits
  detectedMaxScaleUnits: actualMaxScaleUnits
  guaranteedCapacityMbps: guaranteedCapacityMbps
  scaleUnitCapacityMbps: scaleUnitCapacityMbps
  thresholdPercentage: thresholdPercentage
  note: 'Real SKU detection enabled. Threshold calculated from actual gateway scale units.'
}
