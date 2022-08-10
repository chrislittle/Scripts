# This script loops through all subscriptions in an Azure AD tenant and outputs the PrivateDNS Zone Configurations into CSV

$outputCollection = @()
$CurrentContext = Get-AzContext
$Subscriptions = Get-AzSubscription -TenantId $CurrentContext.Tenant.Id
ForEach ($sub in $subscriptions){
set-azcontext -Subscription $sub
$privatednszoneitems = Get-AzResource -ResourceType Microsoft.Network/privateDnsZones
foreach($privatednszoneitem in $privatednszoneitems){
$privatednszonelinks = Get-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $privatednszoneitem.ResourceGroupName -ZoneName $privatednszoneitem.Name
foreach($privatednszonelink in $privatednszonelinks){
$Name = $privatednszonelink.Name
$ResourceGroupName = $privatednszonelink.ResourceGroupName
$ZoneName = $privatednszonelink.ZoneName
$ResourceId = $privatednszonelink.ResourceId
$VirtualNetworkId = $privatednszonelink.VirtualNetworkId
$outputCollection += New-Object PSObject -Property @{
    SubscriptionID = $sub
    PrivateDNSZoneVirtualNetworkLinkName = $Name
    ResourceGroupName = $ResourceGroupName
    ZoneName = $ZoneName
    ResourceId = $ResourceId
    VirtualNetworkId = $VirtualNetworkId}
        }
    }
}

$outputCollection | Format-Table

# export to CSV, comment out if not required
$outputCollection | Export-Csv -Path ./PrivateDNSZoneReport.csv
