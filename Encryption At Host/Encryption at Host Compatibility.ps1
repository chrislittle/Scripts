# This script loops through all subscriptions the user has access to and outputs the list of Virtual Machines & their capabilities for supporting Encryption at Host

$subscriptions=Get-AzSubscription
ForEach ($sub in $subscriptions){
set-azcontext -Subscription $sub
$outputCollection = @()
$serveritems = Get-AzResource -ResourceType Microsoft.Compute/virtualMachines
foreach($serveritem in $serveritems){
$VM = Get-AzVM -ResourceGroupName $serveritem.ResourceGroupName -Name $serveritem.name
$vmname = $vm.Name
$vmlocation = $vm.Location
$vmsize = $vm.HardwareProfile.VmSize
$skudetails = Get-AzComputeResourceSku | where{$_.Name -eq $vmsize -and $_.Locations.Contains('northcentralus')}
$checkencryptionathost = $skudetails.capabilities | where{$_.Name -eq 'EncryptionAtHostSupported'}
$outputCollection += New-Object PSObject -Property @{
    Name = $vmname
    Location = $vmlocation
    VMSize = $vmsize
    EncryptionAtHostSupported = $checkencryptionathost.value}
}
    }