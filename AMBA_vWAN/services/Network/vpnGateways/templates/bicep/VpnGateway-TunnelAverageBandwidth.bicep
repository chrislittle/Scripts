@description('Subscription Id to deploy the alert rule')
param subscriptionId string = subscription().subscriptionId

@description('Action Group resource id to invoke when the alert fires')
param actionGroupResourceId string

@description('Alert rule name')
param alertRuleName string = 'VPN-Gateway-TunnelAverageBandwidth'

@description('Alert rule description')
param alertRuleDescription string = 'Alert rule for VPN Gateway Tunnel Average Bandwidth utilization'

@description('VPN Gateway resource id to be monitored')
param vpnGatewayResourceId string

@description('Severity of the alert')
@allowed([0, 1, 2, 3, 4])
param severity int = 0

@description('Evaluation frequency for the alert in ISO 8601 duration format')
param evaluationFrequency string = 'PT1M'

@description('The alert evaluation window in ISO 8601 duration format')
param windowSize string = 'PT5M'

@description('Tags to apply to the alert rule')
param tags object = {}

@description('Enable or disable the alert rule')
param enabled bool = true

@description('Percentage threshold for tunnel bandwidth utilization (default 80%)')
@minValue(1)
@maxValue(100)
param thresholdPercentage int = 80

// Extract gateway name and resource group from the resource ID
var gatewayName = split(vpnGatewayResourceId, '/')[8]
var gatewayResourceGroup = split(vpnGatewayResourceId, '/')[4]

// Reference to existing VPN Gateway to detect scale units
resource existingGateway 'Microsoft.Network/vpnGateways@2023-09-01' existing = {
  name: gatewayName
  scope: resourceGroup(subscriptionId, gatewayResourceGroup)
}

// Calculate intelligent threshold based on VPN Gateway scale units
// Each scale unit provides 500 Mbps bandwidth in vWAN
var scaleUnits = existingGateway.properties.vpnGatewayScaleUnit
var maxThroughputMbps = scaleUnits * 500
var thresholdMbps = (maxThroughputMbps * thresholdPercentage) / 100
var thresholdBytesPerSecond = thresholdMbps * 1000000 / 8  // Convert Mbps to bytes per second

// Create the metric alert rule
resource vpnGatewayTunnelBandwidthAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: alertRuleName
  location: 'global'
  tags: tags
  properties: {
    description: '${alertRuleDescription}. Threshold: ${thresholdBytesPerSecond} bytes/sec (${thresholdPercentage}% of ${maxThroughputMbps} Mbps capacity based on ${scaleUnits} scale units)'
    severity: severity
    enabled: enabled
    scopes: [
      vpnGatewayResourceId
    ]
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'TunnelAverageBandwidth'
          metricName: 'TunnelAverageBandwidth'
          metricNamespace: 'Microsoft.Network/vpnGateways'
          operator: 'GreaterThan'
          threshold: thresholdBytesPerSecond
          timeAggregation: 'Average'
          dimensions: []
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
    autoMitigate: false
  }
}

@description('Resource ID of the created alert rule')
output alertRuleId string = vpnGatewayTunnelBandwidthAlert.id

@description('Name of the created alert rule')  
output alertRuleName string = vpnGatewayTunnelBandwidthAlert.name

@description('Detected VPN Gateway scale units')
output detectedScaleUnits int = scaleUnits

@description('Calculated maximum throughput in Mbps')
output maxThroughputMbps int = maxThroughputMbps

@description('Applied threshold in bytes per second')
output thresholdBytesPerSecond int = thresholdBytesPerSecond
