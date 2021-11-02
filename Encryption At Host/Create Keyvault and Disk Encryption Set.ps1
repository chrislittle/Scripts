# Set proper subscription context
set-azcontext -Subscription SubscriptionID

# set variables
$ResourceGroupName="ResourceGroupName"
$LocationName="Azure Region"
$keyVaultName="KeyVaultName"
$keyName="KeyName"
$keyDestination="HSM or Software"
$diskEncryptionSetName="DiskEncryptionSetName"


# Create an instance of Azure Key Vault and encryption key
$keyVault = New-AzKeyVault -Name $keyVaultName `
-ResourceGroupName $ResourceGroupName `
-Location $LocationName `
-EnablePurgeProtection

# Give your user account permissions to manage secrets in Key Vault
Set-AzKeyVaultAccessPolicy -VaultName $keyVaultName -UserPrincipalName "user@domain.com" -PermissionsToKeys all

# Adding a key to Key Vault
$key = Add-AzKeyVaultKey -VaultName $keyVaultName `
-Name $keyName `
-Destination $keyDestination

# Create an instance of a DiskEncryptionSet. You can set RotationToLatestKeyVersionEnabled equal to $true to enable automatic rotation of the key. 
# When you enable automatic rotation, the system will automatically update all managed disks, snapshots, and images referencing the disk encryption
# set to use the new version of the key within one hour.
$desConfig=New-AzDiskEncryptionSetConfig -Location $LocationName `
-SourceVaultId $keyVault.ResourceId `
-KeyUrl $key.Key.Kid `
-IdentityType SystemAssigned `
-RotationToLatestKeyVersionEnabled $true
  
$des=New-AzDiskEncryptionSet -Name $diskEncryptionSetName `
-ResourceGroupName $ResourceGroupName `
-InputObject $desConfig

# Grant the DiskEncryptionSet resource access to the key vault
Set-AzKeyVaultAccessPolicy -VaultName $keyVaultName -ObjectId $des.Identity.PrincipalId -PermissionsToKeys wrapkey,unwrapkey,get
