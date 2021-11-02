# Initial Azure Encryption at Host script. Enables Encryption at Host on VM & updates the OS & Data Disks to SSE with CMK to the Disk Encryption Set
# In this repo is a script to check Encryption At Host Compatibility ahead of any implementation.

# Set proper subscription context
set-azcontext -Subscription SubscriptionID

# Set Disk Encryption Set name and Resource Group 
$diskEncryptionSetName = "Disk Encryption Set Name"
$DESResourceGroupName = "Disk Encryption Set Resource Group Name"
$diskEncryptionSet = Get-AzDiskEncryptionSet -ResourceGroupName $DESResourceGroupName -Name $diskEncryptionSetName

# Get inventory & Confirm Report
$outputCollection = @()
$serveritems = Get-AzResource -name *INSERT NAME FILTER* -ResourceType Microsoft.Compute/virtualMachines
foreach($serveritem in $serveritems){
$VM = Get-AzVM -ResourceGroupName $serveritem.ResourceGroupName -Name $serveritem.name
$vmname = $vm.Name
$vmlocation = $vm.Location
$vmrg = $vm.ResourceGroupName
$vmsize = $vm.HardwareProfile.VmSize 
$outputCollection += New-Object PSObject -Property @{
    Name = $vmname
    Location = $vmlocation
    ResourceGroupName = $vmrg
    VMSize = $vmsize}
}

# Confirm List of Virtual Machines to Enable Encryption at Host
$outputCollection | Format-Table
Read-Host -Prompt "Confirm the list of Virtual Machines are correct for Encryption at Host, Press enter key to continue"

# Enable Encryption at host on Virtual Machine list
foreach($vmoutput in $outputCollection){
$VM = Get-AzVM -ResourceGroupName $vmoutput.ResourceGroupName -Name $vmoutput.name
Stop-AzVM -ResourceGroupName $vmoutput.ResourceGroupName -Name $vmoutput.name -Force
$vmosdisk = $vm.StorageProfile.OsDisk
$vmdatadisks = $vm.StorageProfile.DataDisks
Update-AzVM -VM $VM -ResourceGroupName $vmoutput.ResourceGroupName -EncryptionAtHost $true
New-AzDiskUpdateConfig -EncryptionType "EncryptionAtRestWithCustomerKey" -DiskEncryptionSetId $diskEncryptionSet.Id | Update-AzDisk -ResourceGroupName $vmoutput.ResourceGroupName -DiskName $vmosdisk.name
foreach($vmdatadisk in $vmdatadisks){
New-AzDiskUpdateConfig -EncryptionType "EncryptionAtRestWithCustomerKey" -DiskEncryptionSetId $diskEncryptionSet.Id | Update-AzDisk -ResourceGroupName $vmoutput.ResourceGroupName -DiskName $vmdatadisk.name}
Start-AzVM -ResourceGroupName $vmoutput.ResourceGroupName -Name $vmoutput.name
}