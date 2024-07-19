# This is a development script to repair a Windows VM in Azure following Crowdstrike documentation
# Developed by Chris Little & Wilkin Shum

#parameters
$failedvm = Read-Host -Prompt "Please input the failed VM name"
$failedvmrg = Read-Host -Prompt "Please input the resource group of the failed VM"
$failedvmsubscription = Read-Host -Prompt "Please provide the subscriptionID for the failed VM"
$username = Read-Host -Prompt "Please input a username for the recovery VM"
$password = Read-Host "Please enter a password for the recovery VM" -AsSecureString

#Set proper Subscription context
az account set --subscription $failedvmsubscription

#This command will create a copy of the OS disk for the non-functional VM, create a repair VM in a new Resource Group, and attach the OS disk copy. 
#The repair VM will be the same size and region as the non-functional VM specified.

az vm repair create -g $failedvmrg -n $failedvm --repair-username $username --repair-password $password --unlock-encrypted-vm --verbose

Read-Host -Prompt "Please RDP to the repair server & remove the CrowdStrike Files, once complete press any key to continue"

#This command will swap the repaired OS disk with the original OS disk of the VM.
az vm repair restore -g $failedvmrg -n $failedvm --verbose






