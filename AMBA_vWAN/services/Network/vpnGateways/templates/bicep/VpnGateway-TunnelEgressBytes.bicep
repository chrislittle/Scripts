@description('Subscription Id to deploy the alert rule')
param subscriptionId string = subscription().subscriptionId

@description('Action Group resource id to invoke when the alert fires')
param actionGroupResourceId string

@description('Alert rule name')
param alertRuleName string = 'VPN-Gateway-TunnelEgressBytes'

@description('Alert rule description')
param alertRuleDescription string = 'Alert rule for VPN Gateway Tunnel Egress Bytes monitoring'

@description('VPN Gateway resource id to be monitored')
param vpnGatewayResourceId string

@description('Severity of the alert')
@allowed([0, 1, 2, 3, 4])
param severity int = 2

@description('Evaluation frequency for the alert in ISO 8601 duration format')
param evaluationFrequency string = 'PT5M'

@description('The alert evaluation window in ISO 8601 duration format')
param windowSize string = 'PT5M'

@description('Tags to apply to the alert rule')
param tags object = {}

@description('Enable or disable the alert rule')
param enabled bool = true

@description('Threshold mode: static (manual threshold) or intelligent (scale unit based)')
@allowed(['static', 'intelligent'])
param thresholdMode string = 'intelligent'

@description('Static threshold in bytes (used when thresholdMode is static)')
param staticThresholdBytes int = 1000000000

@description('Time period in hours for intelligent threshold calculation (default 1 hour)')
@minValue(1)
@maxValue(24)
param intelligentThresholdHours int = 1

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
var maxThroughputBytesPerSecond = maxThroughputMbps * 1000000 / 8  // Convert Mbps to bytes/sec

// Calculate expected bytes over the threshold period (assuming 70% utilization as baseline)
var baselineUtilizationPercent = 70
var expectedBytesPerPeriod = (maxThroughputBytesPerSecond * baselineUtilizationPercent / 100) * (intelligentThresholdHours * 3600)

// Use appropriate threshold based on mode
var finalThreshold = thresholdMode == 'intelligent' ? expectedBytesPerPeriod : staticThresholdBytes

// Create the metric alert rule
resource vpnGatewayTunnelEgressBytesAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: alertRuleName
  location: 'global'
  tags: tags
  properties: {
    description: thresholdMode == 'intelligent' 
      ? '${alertRuleDescription}. Intelligent threshold: ${finalThreshold} bytes over ${intelligentThresholdHours}h (${baselineUtilizationPercent}% of ${maxThroughputMbps} Mbps capacity based on ${scaleUnits} scale units)'
      : '${alertRuleDescription}. Static threshold: ${finalThreshold} bytes'
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
          name: 'TunnelEgressBytes'
          metricName: 'TunnelEgressBytes'
          metricNamespace: 'Microsoft.Network/vpnGateways'
          operator: 'GreaterThan'
          threshold: finalThreshold
          timeAggregation: 'Total'
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
output alertRuleId string = vpnGatewayTunnelEgressBytesAlert.id

@description('Name of the created alert rule')  
output alertRuleName string = vpnGatewayTunnelEgressBytesAlert.name

@description('Detected VPN Gateway scale units')
output detectedScaleUnits int = scaleUnits

@description('Calculated maximum throughput in Mbps')
output maxThroughputMbps int = maxThroughputMbps

@description('Applied threshold in bytes')
output finalThresholdBytes int = finalThreshold

@description('Threshold calculation mode used')
output thresholdModeUsed string = thresholdMode
