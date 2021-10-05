#
# WARNING: THIS SCRIPT IS PROVIDED WITHOUT WARRANTY AND SUPPORT. ROBUST TESTING SHOULD BE PERFORMED.
#
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
$primarynode = "Primary Cluster Node VM Name"
$secondarynode = "Secondary Cluster Node VM Name"
$agname = "SQL Always On Availability Group short name, no domain, case sensitive"
$agfqdn = "SQL Always On Availability Group FQDN, case sensitive"
# HIDDEN_RESOURCE_GROUP_FOR_RESTORE_POINT_COLLECTIONS
$restorePointCollectionrg = "restorePointCollection rg name"

# set the recovery context to the existing vault
Set-AzRecoveryServicesVaultContext -Vault $currentvault

# Get the container & backup items details and disable protection for Azure VM Type for all cluster nodes
$container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -FriendlyName $primarynode -ResourceGroupName $currentrgvm
$currentitems = Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType AzureVM
foreach($currentitem in $currentitems){
Disable-AzRecoveryServicesBackupProtection -Item $currentitem -Force}

$container = Get-AzRecoveryServicesBackupContainer -ContainerType AzureVM -FriendlyName $secondarynode -ResourceGroupName $currentrgvm
$currentitems = Get-AzRecoveryServicesBackupItem -Container $container -WorkloadType AzureVM
foreach($currentitem in $currentitems){
Disable-AzRecoveryServicesBackupProtection -Item $currentitem -Force}

# Get the Availability Group databases & disable protection for for the availability group
$sqlagitems = Get-AzRecoveryServicesBackupItem -BackupManagementType AzureWorkload -WorkloadType MSSQL -Name $agname -VaultId $currentvault.ID
foreach($sqlagitem in $sqlagitems){
Disable-AzRecoveryServicesBackupProtection -Item $sqlagitem -VaultId $currentvault.ID -Force}

# remove restore point collections (snapshots) for Primary Node
$restorePointCollection = Get-AzResource -ResourceGroupName $restorePointCollectionrg -name *MANUALLY TYPE IN PRIMARY VM NAME KEEP STARS* -ResourceType Microsoft.Compute/restorePointCollections
$restorePointCollection | Format-Table
Read-Host -Prompt "Confirm the restorePointCollection list matches your intent, Press enter key to continue"
Remove-AzResource -ResourceId $restorePointCollection.ResourceId -Force

# remove restore point collections (snapshots) for Secondary Node
$restorePointCollection = Get-AzResource -ResourceGroupName $restorePointCollectionrg -name *MANUALLY TYPE IN SECONDARY VM NAME KEEP STARS* -ResourceType Microsoft.Compute/restorePointCollections
$restorePointCollection | Format-Table
Read-Host -Prompt "Confirm the restorePointCollection list matches your intent, Press enter key to continue"
Remove-AzResource -ResourceId $restorePointCollection.ResourceId -Force

# Move resources associated with Primary Node VM (NIC, NSG, DISK)
$resources = Get-AzResource -ResourceGroupName $currentrgvm -name *MANUALLY TYPE IN PRIMARY VM NAME KEEP STARS*
$resources | Format-Table
Read-Host -Prompt "Confirm the list of resources to move match your intent, Press enter key to continue"
Move-AzResource -DestinationResourceGroupName $newrgvm -ResourceId $Resources.ResourceId -Force

# Move resources associated with Secondary Node VM (NIC, NSG, DISK)
$resources = Get-AzResource -ResourceGroupName $currentrgvm -name *MANUALLY TYPE IN SECONDARY VM NAME KEEP STARS*
$resources | Format-Table
Read-Host -Prompt "Confirm the list of resources to move match your intent, Press enter key to continue"
Move-AzResource -DestinationResourceGroupName $newrgvm -ResourceId $Resources.ResourceId -Force

# set the recovery context to the new vault
Set-AzRecoveryServicesVaultContext -Vault $newvault

# set variable for the policy to be applied (must exist prior to execution)
$vmpolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name "POLICY NAME IN NEW VAULT"
$sqlpolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name "POLICY NAME IN NEW VAULT"

# enable protection of the newly moved VM & SQL databases to the policy defined.
Enable-AzRecoveryServicesBackupProtection -Policy $vmpolicy -Name $primarynode -ResourceGroupName $newrgvm -VaultId $newvault.ID
Enable-AzRecoveryServicesBackupProtection -Policy $vmpolicy -Name $secondarynode -ResourceGroupName $newrgvm -VaultId $newvault.ID

$primaryvmdetails = Get-AzResource -Name $primarynode -ResourceType Microsoft.Compute/virtualMachines
$secondaryvmdetails = Get-AzResource -Name $secondarynode -ResourceType Microsoft.Compute/virtualMachines

Register-AzRecoveryServicesBackupContainer -ResourceId $primaryvmdetails.ResourceId -BackupManagementType AzureWorkload -WorkloadType MSSQL -VaultId $newvault.ID -Force
Register-AzRecoveryServicesBackupContainer -ResourceId $secondaryvmdetails.ResourceId -BackupManagementType AzureWorkload -WorkloadType MSSQL -VaultId $newvault.ID -Force

Get-AzRecoveryServicesBackupProtectableItem -workloadType MSSQL -ItemType sqldatabase -VaultId $newvault.ID -ServerName $agfqdn
Read-Host -Prompt "confirm the item you wish to protect is present, Press enter key to continue"
$sqlagdbitems = Get-AzRecoveryServicesBackupProtectableItem -workloadType MSSQL -ItemType sqldatabase -VaultId $newvault.ID -ServerName $agfqdn
foreach($sqlagdbitem in $sqlagdbitems){
Enable-AzRecoveryServicesBackupProtection -ProtectableItem $sqlagdbitem -Policy $sqlpolicy}

enable autoprotection of SQL Instance
$SQLAG = Get-AzRecoveryServicesBackupProtectableItem -workloadType MSSQL -ItemType SQLAvailabilityGroup -VaultId $newvault.ID -ServerName $vmfqdn
Enable-AzRecoveryServicesBackupAutoProtection -InputItem $SQLAG -BackupManagementType AzureWorkload -WorkloadType MSSQL -Policy $sqlpolicy -VaultId $newvault.ID