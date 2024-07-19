# This is a development script to repair a Windows VM in Azure following the CrowdStrike Incident
# Developed by Chris Little, Wilkin Shum & Chad Schultz

#parameters
$failedvm = Read-Host -Prompt "Please input the failed VM name"
$failedvmrg = Read-Host -Prompt "Please input the resource group of the failed VM"
$failedvmsubscription = Read-Host -Prompt "Please provide the subscriptionID for the failed VM"
$username = Read-Host -Prompt "Please input a username for the recovery VM"
$password = Read-Host "Please enter a password for the recovery VM" -AsSecureString

#generate random RG & VM recovery name
$guid = [guid]::NewGuid().ToString()
$randomStringVM = "rvm" + $guid.Substring(0, 10)
$randomStringRG = "rrg" + $guid.Substring(0, 10)

#Add VM repair extension
az extension add -n vm-repair

#Set proper Subscription context
az account set --subscription $failedvmsubscription

#This command will create a copy of the OS disk for the non-functional VM, create a repair VM in a new Resource Group, and attach the OS disk copy. 
#The repair VM will be the same size and region as the non-functional VM specified.

az vm repair create -g $failedvmrg -n $failedvm --repair-username $username --repair-password $password --repair-vm-name $randomStringVM --repair-group-name $randomStringRG --unlock-encrypted-vm --verbose

Read-Host -Prompt "Press any key to Remove CrowdStrike Files...."

#Remove CrowdStrike Files
az vm repair run -g $failedvmrg -n $failedvm --run-on-repair --custom-script-file ./repairfalcon.ps1 --verbose

Read-Host -Prompt "Press any key to swap the repaired OS disk to the original VM...."

#This command will swap the repaired OS disk with the original OS disk of the VM.
az vm repair restore -g $failedvmrg -n $failedvm --verbose






