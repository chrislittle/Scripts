# Azure Virtual WAN Monitor Baseline Alerts (AMBA)

This repository contains Bicep templates for monitoring Azure Virtual WAN components following the Azure Monitor Baseline Alerts (AMBA) patterns and best practices from Microsoft documentation.

## Overview

Azure Virtual WAN (vWAN) is a networking service that brings many networking, security, and routing functionalities together to provide a single operational interface. Proper monitoring is crucial to ensure optimal performance, security, and availability.

These alert templates are based on the [Azure Virtual WAN monitoring best practices](https://learn.microsoft.com/en-us/azure/virtual-wan/monitor-virtual-wan#monitoring-azure-virtual-wan---best-practices) and follow the standardized AMBA template structure.

## Available Alert Templates

### ✅ Virtual Hubs (2 templates)
- **BGP Peer Status**: Monitors BGP connectivity between virtual hub router and gateways (Severity 1)
- **Virtual Hub Data Processed**: Monitors data processing capacity utilization (Severity 3)

### ✅ Site-to-Site VPN Gateways (6 templates)
- **Tunnel Average Bandwidth**: Monitors tunnel bandwidth utilization with intelligent scale unit detection
- **Activity Log Delete**: VPN Gateway deletion activity log monitoring
- **Tunnel Egress Bytes**: Monitors tunnel egress traffic volume
- **BGP Peer Status**: Monitors BGP peer connectivity status (Severity 1)
- **Tunnel Packet Drop Count**: Monitors tunnel egress/ingress packet drops (Severity 2)
- **Tunnel Disconnect Events**: Log-based alert for tunnel disconnections (Severity 1)

### ✅ ExpressRoute Gateways (3 templates)
- **CPU Utilization**: Monitors gateway CPU performance (Severity 2)
- **Connection Bits In Per Second**: Monitors ingress bandwidth to Azure (Severity 0)
- **Connection Bits Out Per Second**: Monitors egress bandwidth from Azure (Severity 0)

### ✅ Azure Firewall (1 template)
- **SNAT Port Utilization**: Monitors SNAT port exhaustion risk (Severity 1)

**Total: 12 production-ready alert templates**

## Project Structure

```text
AMBA_vWAN/
├── services/Network/
│   ├── virtualWans/templates/bicep/          # Virtual Hub alerts (2 templates)
│   ├── vpnGateways/templates/bicep/          # S2S VPN alerts (6 templates)
│   ├── expressRouteGateways/templates/bicep/ # ExpressRoute alerts (3 templates)
│   └── azureFirewalls/templates/bicep/       # Firewall alerts (1 template)
├── deploy-alerts.ps1                         # Interactive PowerShell deployment script
└── README.md                                # This documentation
```

## Alert Severity Levels

| Severity | Description | Examples |
|----------|-------------|----------|
| 0 | Critical | Service completely unavailable |
| 1 | Error | BGP peer down, SNAT port exhaustion |
| 2 | Warning | Packet drops, bandwidth utilization |
| 3 | Informational | Route changes, capacity monitoring |
| 4 | Verbose | Debug scenarios |

## Deployment Options

### 🎯 Interactive Deployment (Recommended)

The PowerShell deployment script includes an interactive mode that guides you through the entire process:

```powershell
# Launch interactive mode - perfect for first-time users
.\deploy-alerts.ps1 -Interactive

# Interactive mode with What-If (test without deploying - FAST!)
.\deploy-alerts.ps1 -Interactive -WhatIf
```

**Interactive features:**
- **Multi-subscription support**: Automatically discovers and lets you select from available subscriptions
- **Resource discovery**: Scans selected subscriptions for Virtual WAN components
- **Alert type selection**: Choose specific alert types or deploy all
- **Configuration wizard**: Guided setup for resource groups and Log Analytics workspaces
- **Deployment confirmation**: Review all settings before deployment
- **Progress tracking**: Real-time deployment status with colored output
- **Fast WhatIf mode**: Skips resource discovery for instant deployment preview

## 🚀 Performance Optimization

### WhatIf Mode (Configuration Preview)

The `-WhatIf` mode shows available templates and configuration without scanning for actual resources:

```powershell
# Configuration preview - shows what COULD be deployed if resources exist
.\deploy-alerts.ps1 -Interactive -WhatIf

# Result: Instant preview of available templates and configuration
```

**WhatIf Benefits:**
- ✅ **No Resource Scanning**: No Azure CLI calls or authentication required
- ✅ **Instant Preview**: Shows configuration and available templates immediately
- ✅ **Configuration Validation**: Verify settings before actual deployment
- ✅ **Perfect for Planning**: Plan deployments without Azure access

**Important**: WhatIf shows *available* templates, not what will actually be deployed. Actual deployment only deploys alerts for resources that exist in your subscriptions.

### Actual Deployment (Resource Discovery and Selective Deployment)

Real deployments scan for vWAN resources and deploy only matching alert templates:

```powershell
# Scans subscriptions and deploys alerts only for discovered vWAN resources
.\deploy-alerts.ps1 -Interactive

# Behavior: Only deploys alerts if matching resource types are found
```

**Deployment Logic:**
- **Resource Discovery**: Scans subscriptions for Virtual Hubs, VPN Gateways, ExpressRoute Gateways, Firewalls
- **Selective Deployment**: Only deploys alert templates for discovered resource types
- **Zero Resources = Zero Alerts**: If no vWAN resources exist, no alerts are deployed
- **Template Matching**: Virtual Hub templates deploy only if Virtual Hubs exist, etc.

### 🚀 Automated Deployment Script

For automated scenarios, use command-line parameters:

```powershell
# Interactive mode with guided setup (recommended)
.\deploy-alerts.ps1 -Interactive

# Deploy all alerts with new action group for notifications
.\deploy-alerts.ps1 `
  -SubscriptionIds "12345678-1234-1234-1234-123456789012" `
  -AlertTypes "All" `
  -ActionGroupName "ag-vwan-alerts" `
  -EmailAddresses "admin@contoso.com","ops@contoso.com" `
  -SmsNumbers "+12345678901"

# Deploy specific alerts using existing action group
.\deploy-alerts.ps1 -AlertTypes "VirtualHub","S2SVPN" -UseExistingActionGroup

# Full configuration with Log Analytics workspace and action group
.\deploy-alerts.ps1 `
  -SubscriptionIds "12345678-1234-1234-1234-123456789012" `
  -AlertTypes "All" `
  -ResourceGroup "rg-vwan-monitoring" `
  -LogAnalyticsWorkspace "/subscriptions/.../workspaces/law-vwan-monitoring" `
  -ActionGroupName "ag-vwan-notifications" `
  -EmailAddresses "team@contoso.com" `
  -WebhookUrls "https://hooks.slack.com/services/..."

# Deploy across multiple subscriptions (creates action groups per subscription in interactive mode)
.\deploy-alerts.ps1 -SubscriptionIds "sub1-guid","sub2-guid" -AlertTypes "All" -Interactive

# Test deployment without making changes (What-If mode - FAST!)
.\deploy-alerts.ps1 -Interactive -WhatIf
```

**Available Alert Types:**
- `VirtualHub` - Virtual Hub BGP and capacity alerts (2 templates)
- `S2SVPN` - Site-to-Site VPN connectivity and performance alerts (6 templates - AMBA compliant)
- `ExpressRoute` - ExpressRoute Gateway performance alerts (3 templates)
- `Firewall` - Azure Firewall security alerts (1 template)
- `All` - Deploy all available alert types (12 templates)

## Alert Templates

### 📁 Template Organization

Alert templates use descriptive naming conventions:

- **Virtual Hub Alerts**:
  - `VirtualHub-BGPPeerStatus.bicep` - BGP peer connectivity monitoring
  - `VirtualHub-DataProcessed.bicep` - Data processing capacity monitoring
- **VPN Gateway Alerts** (AMBA Compliant):
  - `VpnGateway-TunnelAverageBandwidth.bicep` - Tunnel bandwidth utilization with intelligent vWAN scale unit detection
  - `VpnGateway-ActivityLogDelete.bicep` - VPN Gateway deletion activity log monitoring  
  - `VpnGateway-TunnelEgressBytes.bicep` - Tunnel egress traffic volume monitoring
  - `VpnGateway-BGPPeerStatus.bicep` - VPN BGP peer status monitoring
  - `VpnGateway-TunnelPacketDropCount.bicep` - Tunnel packet drop monitoring
  - `VpnGateway-TunnelDisconnectLog.bicep` - Tunnel disconnect log alerts
- **ExpressRoute Gateway Alerts**:
  - `ExpressRouteGateway-CPUUtilization.bicep` - Gateway CPU monitoring
  - `ExpressRouteGateway-ConnectionBitsInPerSecond.bicep` - Ingress bandwidth monitoring
  - `ExpressRouteGateway-ConnectionBitsOutPerSecond.bicep` - Egress bandwidth monitoring
- **Azure Firewall Alerts**:
  - `AzureFirewall-SNATPortUtilization.bicep` - SNAT port utilization monitoring

### 📋 Individual Alert Deployment

Deploy a single alert using Azure CLI:

```powershell
# Deploy Virtual Hub BGP Peer Status alert
az deployment group create `
  --resource-group "rg-vwan-monitoring" `
  --template-file "services/Network/virtualWans/templates/bicep/VirtualHub-BGPPeerStatus.bicep" `
  --parameters `
    alertName="vhub-bgp-peer-status-alert" `
    targetResourceId='["/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-vwan/providers/Microsoft.Network/virtualHubs/vhub-prod-eastus"]' `
    targetResourceRegion="EastUS" `
    targetResourceType="Microsoft.Network/virtualHubs"
```

### PowerShell Deployment

```powershell
# Deploy S2S VPN Tunnel Packet Drop alert
New-AzResourceGroupDeployment `
  -ResourceGroupName "rg-vwan-monitoring" `
  -TemplateFile "services/Network/vpnGateways/templates/bicep/VpnGateway-TunnelPacketDropCount.bicep" `
  -alertName "s2s-tunnel-packet-drop-alert" `
  -targetResourceId @("/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-vwan/providers/Microsoft.Network/vpnGateways/vpngw-prod-eastus") `
  -targetResourceRegion "EastUS" `
  -targetResourceType "Microsoft.Network/vpnGateways"
```

### Bicep Parameters File Examples

**💡 Tip**: Use the interactive deployment script (`.\deploy-alerts.ps1 -Interactive`) for easier deployment instead of creating these parameter files manually.

Create parameter files (`.bicepparam`) for manual alert deployment:

#### Virtual Hub BGP Alert Example

```bicep
using '../services/Network/virtualWans/templates/bicep/VirtualHub-BGPPeerStatus.bicep'

param alertName = 'vhub-bgp-peer-status-prod'
param alertDescription = 'Virtual Hub BGP Peer Status - Production Environment'
param targetResourceId = [
  '/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-vwan-prod/providers/Microsoft.Network/virtualHubs/vhub-prod-eastus'
  '/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-vwan-prod/providers/Microsoft.Network/virtualHubs/vhub-prod-westus'
]
param targetResourceRegion = 'EastUS'
param targetResourceType = 'Microsoft.Network/virtualHubs'
param alertSeverity = 1
param threshold = 1
param isEnabled = true
param tags = {
  Environment: 'Production'
  Owner: 'NetworkTeam'
  CostCenter: 'IT-001'
}
```

#### Virtual Hub Data Processed Alert Example

```bicep
using '../services/Network/virtualWans/templates/bicep/VirtualHub-DataProcessed.bicep'

param alertName = 'vhub-data-processed-prod'
param alertDescription = 'Virtual Hub Data Processing Capacity Alert'
param virtualHubResourceId = '/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-vwan-prod/providers/Microsoft.Network/virtualHubs/vhub-prod-eastus'
param targetResourceRegion = 'EastUS'
param routingInfrastructureUnits = 5  // Set to your actual RIUs
param thresholdPercentage = 80
param alertSeverity = 3
param tags = {
  Environment: 'Production'
  Owner: 'NetworkTeam'
}
```

#### Common Parameters

All alert templates share these core parameters:

- **alertName** - Unique name for the alert
- **targetResourceId** - Array of resource IDs to monitor  
- **targetResourceRegion** - Azure region (no spaces, e.g., "EastUS")
- **targetResourceType** - Resource type (e.g., "Microsoft.Network/virtualHubs")
- **alertSeverity** - Alert severity level (0-4)
- **tags** - Resource tags for organization

Log-based alerts also require:

- **workspaceId** - Log Analytics workspace resource ID

#### Deploy with Parameters File

```powershell
# Deploy using parameter file
az deployment group create `
  --resource-group "rg-vwan-monitoring" `
  --parameters vhub-bgp-alert.bicepparam
```

### Log Alert Deployment (Requires Log Analytics Workspace)

```powershell
# Deploy S2S VPN Tunnel Disconnect log alert
az deployment group create `
  --resource-group "rg-vwan-monitoring" `
  --template-file "services/Network/vpnGateways/templates/bicep/TunnelDisconnectLog_7890123a-4567-8901-0123-9012345678ab.bicep" `
  --parameters `
    alertName="s2s-tunnel-disconnect-log-alert" `
    workspaceId="/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-vwan-monitoring" `
    alertSeverity=1
```

## Action Groups & Notifications

The deployment script supports comprehensive action group configuration for alert notifications.

### Automated Action Group Setup

- **Interactive Mode**: Guides you through creating new or selecting existing action groups
- **New Action Groups**: Configure email, SMS, and webhook notifications during deployment
- **Existing Action Groups**: Select from available action groups in your subscription
- **Multi-Subscription**: Creates action groups per subscription or configures centrally

### Notification Options

- **Email**: Multiple email addresses for team notifications
- **SMS**: Phone numbers with country codes (e.g., +12345678901)
- **Webhooks**: Integration with Slack, Teams, or custom endpoints
- **Skip Option**: Deploy alerts without notifications for testing

### Non-Interactive Configuration

```powershell
# New action group with multiple notification types
.\deploy-alerts.ps1 `
  -ActionGroupName "ag-vwan-prod" `
  -EmailAddresses "admin@contoso.com","security@contoso.com" `
  -SmsNumbers "+12345678901","+19876543210" `
  -WebhookUrls "https://hooks.slack.com/services/..."

# Use existing action group
.\deploy-alerts.ps1 -UseExistingActionGroup
```

## Configuration & Best Practices

### Default Thresholds

- **BGP Peer Status**: `< 1` (peer down) - Severity 1
- **SNAT Port Utilization**: `> 95%` - Severity 1
- **Packet Drop Count**: `> 0` (any drops) - Severity 2
- **CPU Utilization**: `> 80%` - Severity 2
- **ExpressRoute Bandwidth**: `< 10%` of gateway capacity - Severity 0

### ExpressRoute Gateway Bandwidth Monitoring

The ExpressRoute Gateway bandwidth alerts monitor ingress and egress traffic with **intelligent threshold detection** based on actual gateway configuration.

#### Real SKU Detection

The bandwidth alerts automatically detect the actual gateway scale unit configuration:

- **Auto-Detection**: Queries the deployed gateway's `autoScaleConfiguration` to get min/max scale units
- **Guaranteed Capacity**: Uses minimum scale units for threshold calculation (guaranteed baseline)
- **Dynamic Thresholds**: Automatically calculates appropriate thresholds based on actual capacity

#### vWAN ExpressRoute Gateway Architecture

**Scale Unit Model**
| Scale Units | Bandwidth per Unit | Example Capacity | 10% Threshold |
|-------------|-------------------|------------------|---------------|
| 2 units (min) | 1 Gbps | 2 Gbps guaranteed | 200 Mbps |
| 5 units (min) | 1 Gbps | 5 Gbps guaranteed | 500 Mbps |
| 10 units (min) | 1 Gbps | 10 Gbps guaranteed | 1 Gbps |

**Auto-Scaling Configuration**
- **Minimum Scale Units**: Guaranteed baseline capacity used for alert thresholds
- **Maximum Scale Units**: Auto-scale ceiling (gateway can scale up based on demand)
- **Capacity per Unit**: 1 Gbps bandwidth per scale unit

#### Configuration Options

- **Auto-Detection (Recommended)**: `autoDetectThreshold: true` - Uses actual gateway min scale units
- **Manual Thresholds**: `autoDetectThreshold: false` + `manualThreshold: <value>` for custom settings
- **Percentage-Based**: Configure alert when bandwidth drops below percentage of guaranteed capacity

**Example Auto-Detected Thresholds:**
- Gateway with 2 min scale units: 10% threshold = 200 Mbps
- Gateway with 5 min scale units: 10% threshold = 500 Mbps  
- Gateway with 10 min scale units: 10% threshold = 1 Gbps

### Timing Configuration

- **Critical alerts**: PT5M evaluation, PT15M window
- **Performance alerts**: PT5M evaluation, PT15M window
- **Capacity alerts**: PT15M evaluation, PT30M window

## Prerequisites

1. **Azure Virtual WAN**: Deployed and configured
2. **Resource Permissions**: Contributor or Monitoring Contributor role on target resources
3. **Log Analytics Workspace**: Required for log-based alerts
4. **Diagnostic Settings**: Configured for log-based monitoring

### Enable Diagnostic Settings for VPN Gateways

```powershell
# Enable diagnostic logs for S2S VPN Gateway
az monitor diagnostic-settings create `
  --name "vpngw-diagnostics" `
  --resource "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-vwan/providers/Microsoft.Network/vpnGateways/vpngw-prod-eastus" `
  --workspace "/subscriptions/12345678-1234-1234-1234-123456789012/resourceGroups/rg-monitoring/providers/Microsoft.OperationalInsights/workspaces/law-vwan-monitoring" `
  --logs '[
    {
      "category": "GatewayDiagnosticLog",
      "enabled": true
    },
    {
      "category": "TunnelDiagnosticLog", 
      "enabled": true
    },
    {
      "category": "RouteDiagnosticLog",
      "enabled": true
    },
    {
      "category": "IKEDiagnosticLog",
      "enabled": true
    }
  ]' `
  --metrics '[
    {
      "category": "AllMetrics",
      "enabled": true
    }
  ]'
```

## Troubleshooting & Best Practices

### Deployment Best Practices

1. **Start with Critical Alerts**: Deploy BGP peer status and tunnel disconnect alerts first
2. **Test in Development**: Validate thresholds to reduce noise before production deployment
3. **Group Resources**: Use consistent resource groups and tagging for easier management

### Common Issues

- **Slow Resource Discovery**: If you don't have vWAN resources, use `-WhatIf` mode for fast testing
- **Empty Subscription Performance**: Azure CLI network commands are slow on subscriptions without vWAN resources  
- **Insufficient Permissions**: Ensure Contributor or Monitoring Contributor role on target resources
- **Resource Not Found**: Verify resource IDs are correct and resources exist
- **Log Analytics Required**: Ensure workspace exists for log-based alerts
- **Diagnostic Settings**: Enable diagnostic settings for log-based monitoring

### Performance Troubleshooting

**Issue**: Script runs very slowly during resource discovery  
**Cause**: Azure CLI network commands enumerate all regions even for empty subscriptions  
**Solution**: Use `-WhatIf` mode for testing, or ensure you have actual vWAN resources deployed  

**Issue**: WhatIf mode takes 30+ seconds  
**Cause**: Using an older version without performance optimization  
**Solution**: The current version skips resource discovery in WhatIf mode for instant results

### Validation Commands

```powershell
# Check alert rule status
az monitor metrics alert show --name "vhub-bgp-peer-status-alert" --resource-group "rg-monitoring"

# View alert history  
az monitor activity-log list --resource-group "rg-monitoring" --start-time "2024-01-01T00:00:00Z"
```

## References & Support

### Documentation

- [Azure Virtual WAN Monitoring Best Practices](https://learn.microsoft.com/en-us/azure/virtual-wan/monitor-virtual-wan)
- [Azure Monitor Baseline Alerts (AMBA)](https://aka.ms/amba)
- [Azure Monitor Alerts Overview](https://learn.microsoft.com/en-us/azure/azure-monitor/alerts/alerts-overview)

### Contributing

Follow AMBA naming conventions (`MetricName_GUID.bicep`), include proper parameter validation, and test templates before submission.

## License

This project follows the same license as the Azure Monitor Baseline Alerts project.
