@description('Subscription Id to deploy the alert rule')
param subscriptionId string = subscription().subscriptionId

@description('Action Group resource id to invoke when the alert fires')
param actionGroupResourceId string

@description('Alert rule name')
param alertRuleName string = 'VPN-Gateway-Delete-ActivityLog'

@description('Alert rule description')
param alertRuleDescription string = 'Activity Log Alert for VPN Gateway Delete operations'

@description('Tags to apply to the alert rule')
param tags object = {}

@description('Enable or disable the alert rule')
param enabled bool = true

@description('Resource Group name to scope the alert (optional - leave empty for subscription-wide)')
param targetResourceGroup string = ''

// Determine the scope - either subscription or resource group
var alertScope = empty(targetResourceGroup) ? '/subscriptions/${subscriptionId}' : '/subscriptions/${subscriptionId}/resourceGroups/${targetResourceGroup}'

// Create the activity log alert rule
resource vpnGatewayDeleteAlert 'Microsoft.Insights/activityLogAlerts@2020-10-01' = {
  name: alertRuleName
  location: 'global'
  tags: tags
  properties: {
    description: alertRuleDescription
    enabled: enabled
    scopes: [
      alertScope
    ]
    condition: {
      allOf: [
        {
          field: 'category'
          equals: 'Administrative'
        }
        {
          field: 'resourceType'
          equals: 'Microsoft.Network/vpnGateways'
        }
        {
          field: 'operationName'
          equals: 'Microsoft.Network/vpnGateways/delete'
        }
        {
          field: 'status'
          containsAny: [
            'succeeded'
          ]
        }
      ]
    }
    actions: {
      actionGroups: [
        {
          actionGroupId: actionGroupResourceId
          webhookProperties: {}
        }
      ]
    }
  }
}

@description('Resource ID of the created alert rule')
output alertRuleId string = vpnGatewayDeleteAlert.id

@description('Name of the created alert rule')  
output alertRuleName string = vpnGatewayDeleteAlert.name

@description('Scope of the alert monitoring')
output alertScope string = alertScope
