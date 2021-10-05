# WARNING: THIS SCRIPT IS PROVIDED WITHOUT WARRANTY AND SUPPORT. ROBUST TESTING SHOULD BE PERFORMED.

SAMPLE POWERSHELL SCRIPTS FOR MOVING MSSQL & AzureVM Workload Types to new Vaults. In order to move workloads to new vaults these scripts include a resource mover command to shift the workloads to a new resource group. This is a requirement to change vaults and can impact RBAC & other governance components when not planned properly.

* Move Azure VM to new vault.ps1 - Moves (while retaining existing data) an Azure VM to a new recovery services vault. This script is not for use with workloads being protected such as MSSQL. **(QA PERFORMED)**
* Move Azure SQL Standalone VM to new Vault.ps1 - Moves (while retaining existing data) a stand alone MS SQL Azure VM to a new recovery services vault. This script is capable of moving both Azure VM backup and MS SQL database configurations. **(QA PERFORMED)**
* Move Azure SQL AOAG VM to new Vault.ps1 - Moves (while retaining existing data) MS SQL Always On Availability Group databases & Azure VM to a new recovery services vault. This script is capable of moving both Azure VM backup and MS SQL Cluster (AOAG) database configurations. Out of the box two node clusters are in the script and can be expanded as necessary. **(QA PERFORMED)**
