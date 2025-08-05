## Get App Service Quotas for a subscription ID & Region

### Login
```
Connect-AzAccount
```
Make sure to scope to the subscription you want to check

### Set Local Execution Policy to temporarily unblock script (if required)
```
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

### Run Script
```
./quota_appsvc.ps1
```


