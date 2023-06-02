# This script loops through all subscriptions in an Azure AD tenant and outputs the ultra disk configurations

$outputCollection = @()
$CurrentContext = Get-AzContext
$Subscriptions = Get-AzSubscription -TenantId $CurrentContext.Tenant.Id
ForEach ($sub in $subscriptions){
set-azcontext -Subscription $sub
$diskitems = Get-AzResource -ResourceType Microsoft.Compute/disks
foreach($diskitem in $diskitems){
$disk = Get-AzDisk -ResourceGroupName $diskitem.ResourceGroupName -Name $diskitem.Name
if($disk.Sku.Name -eq "UltraSSD_LRS"){
$diskname = $disk.Name
$disklocation = $disk.Location
$diskrg = $disk.ResourceGroupName
$diskmgdby = $disk.ManagedBy
$disksize = $disk.DiskSizeGB
$disksku = $disk.Sku.Name
$diskIOPS = $disk.DiskIOPSReadWrite
$diskMBPS = $disk.DiskMBpsReadWrite
$diskstate = $disk.DiskState
$outputCollection += New-Object PSObject -Property @{
    SubscriptionID = $sub
    DiskName = $diskname
    DiskResourceGroup = $diskrg
    DiskLocation = $disklocation
    DiskManagedBy = $diskmgdby
    DiskSize = $disksize
    DiskSku = $disksku
    DiskIOPS = $diskIOPS
    DiskMBPS = $diskMBPS
    DiskState = $diskstate}
        }
    }
}

$outputCollection | Format-Table

# export to CSV, comment out if not required
$outputCollection | Export-Csv -Path ./ultradiskreport.csv