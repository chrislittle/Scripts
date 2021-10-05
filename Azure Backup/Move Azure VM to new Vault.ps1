#
# WARNING: THIS SCRIPT IS PROVIDED WITHOUT WARRANTY AND SUPPORT. ROBUST TESTING SHOULD BE PERFORMED.
#
# This script moves an Azure Virtual Machine to a new recovery services vault. This does not support workload types such as MSSQL, it only functions for Azure VM type.
# 
# General Notes
# - Move-AzResource events on a resource group are blocking, new resource deployments will fail validation until move is complete
# - This script assumes the new Recovery Services Vault & Policy is created ahead of time
# - There is a hidden resource group that stores restorePointCollections (snapshots) that must be found & input into this script. Its not dynamic to find these automatically.


# Set proper subscription context
set-azcontext -Subscription SubscriptionID

# Set general variables
$currentrgvault = "CURRENT VAULT RESOURCE GROUP"
$currentrgvm = "CURRENT VM RESOURCE GROUP"
$newrgvault = "NEW VAULT RESOURCE GROUP"
$newrgvm = "NEW VM RESOURCE GROUP"
$currentvault = Get-AzRecoveryServicesVault -ResourceGroupName $currentrgvault -Name "CURRENT VAULT NAME"
$newvault = Get-AzRecoveryServicesVault -ResourceGroupName $newrgvault -Name "NEW VAULT NAME"
$vmname = "VM NAME"
# HIDDEN_RESOURCE_GROUP_FOR_RESTORE_POINT_COLLECTIONS
$restorePointCollectionrg = "restorePointCollection rg name"

# set the recovery context to the existing vault
Set-AzRecoveryServicesVaultContext -Vault $currentvault

# Get the container & backup items details and disable protection for Azure VM Type
$container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -FriendlyName $vmname
$currentitems = Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType AzureVM
foreach($currentitem in $currentitems){
Disable-AzRecoveryServicesBackupProtection -Item $currentitem -Force}

# remove restore point collections (snapshots)
$restorePointCollection = Get-AzResource -ResourceGroupName $restorePointCollectionrg -name *MANUALLY TYPE IN VM NAME KEEP STARS* -ResourceType Microsoft.Compute/restorePointCollections
$restorePointCollection | Format-Table
Read-Host -Prompt "Confirm the restorePointCollection list matches your intent, Press enter key to continue"
Remove-AzResource -ResourceId $restorePointCollection.ResourceId -Force

# Move resources associated with VM (NIC, NSG, DISK)
$resources = Get-AzResource -ResourceGroupName $currentrgvm -name *MANUALLY TYPE IN VM NAME KEEP STARS*
$resources | Format-Table
Read-Host -Prompt "Confirm the list of resources to move match your intent, Press enter key to continue"
Move-AzResource -DestinationResourceGroupName $newrgvm -ResourceId $Resources.ResourceId -Force

# set the recovery context to the new vault
Set-AzRecoveryServicesVaultContext -Vault $newvault

# set variable for the policy to be applied (must exist prior to execution)
$newvmpolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name "POLICY NAME IN NEW VAULT"

# enable protection of the newly moved VM to the policy defined.
Enable-AzRecoveryServicesBackupProtection -Policy $newvmpolicy -Name $vmname -ResourceGroupName $newrgvm -VaultId $newvault.ID

