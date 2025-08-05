param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$true)]
    [string]$Region
)

# Set the API version
$apiVersion = "2023-12-01"

# Construct the REST API URL
$uri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.Web/locations/$Region/usages?api-version=$apiVersion"

# Get Azure access token (requires Az.Accounts module and login)
$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com/").Token

# Make the REST API call
$response = Invoke-RestMethod -Uri $uri -Method Get -Headers @{
    Authorization = "Bearer $token"
    "Content-Type" = "application/json"
}

# Output the response
$response.value | Format-Table `
    name, currentValue, limit, unit, displayName -AutoSize

