# This script loops through all subscriptions in an Azure AD tenant and outputs the virtual network peerings into CSV

$outputCollection = @()
$CurrentContext = Get-AzContext
$Subscriptions = Get-AzSubscription -TenantId $CurrentContext.Tenant.Id
ForEach ($sub in $subscriptions){
set-azcontext -Subscription $sub
$vnetitems = Get-AzResource -ResourceType Microsoft.Network/virtualNetworks
foreach($vnetitem in $vnetitems){
$vnet = Get-AzVirtualNetwork -ResourceGroupName $vnetitem.ResourceGroupName -Name $vnetitem.Name
foreach($peering in $vnet.VirtualNetworkPeerings){
$vnetname = $vnet.Name
$vnetlocation = $vnet.Location
$vnetpeeringname = $peering.Name
$vnetpeeringremotenetwork = $peering.RemoteVirtualNetwork.id
$outputCollection += New-Object PSObject -Property @{
    SubscriptionID = $sub
    VirtualNetworkName = $vnetname
    Location = $vnetlocation
    VirtualNetworkPeeringName = $vnetpeeringname
    VirtualNetworkRemoteNetwork = $vnetpeeringremotenetwork}
        }
    }
}

$outputCollection | Format-Table

# export to CSV, comment out if not required
$outputCollection | Export-Csv -Path ./peeringreport.csv
