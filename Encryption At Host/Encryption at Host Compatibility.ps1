# This script loops through all subscriptions the user has access to and outputs the list of Virtual Machines & their capabilities for supporting Encryption at Host

$outputCollection = @()
$subscriptions=Get-AzSubscription
ForEach ($sub in $subscriptions){
set-azcontext -Subscription $sub
$serveritems = Get-AzResource -ResourceType Microsoft.Compute/virtualMachines
foreach($serveritem in $serveritems){
$VM = Get-AzVM -ResourceGroupName $serveritem.ResourceGroupName -Name $serveritem.name
$vmname = $vm.Name
$vmlocation = $vm.Location
$vmsize = $vm.HardwareProfile.VmSize
$skudetails = Get-AzComputeResourceSku | Where-Object{$_.Name -eq $vmsize -and $_.Locations.Contains('northcentralus')}
$checkencryptionathost = $skudetails.capabilities | Where-Object{$_.Name -eq 'EncryptionAtHostSupported'}
$outputCollection += New-Object PSObject -Property @{
    Name = $vmname
    Location = $vmlocation
    VMSize = $vmsize
    EncryptionAtHostSupported = $checkencryptionathost.value}
    }
}
$outputCollection | Format-Table