# Azure Monitor Baseline Alerts for Azure Virtual WAN
# This script deploys AMBA alert templates for Azure Virtual WAN monitoring

param(
    [string[]]$SubscriptionIds = @(),
    [string]$ResourceGroup = "rg-vwan-monitoring",
    [string]$Location = "East US",
    [string]$LogAnalyticsWorkspace = "",
    [string[]]$AlertTypes = @(),
    [string]$ActionGroupName = "",
    [string]$ActionGroupResourceGroup = "",
    [string[]]$EmailAddresses = @(),
    [string[]]$SmsNumbers = @(),
    [string[]]$WebhookUrls = @(),
    [switch]$UseExistingActionGroup,
    [switch]$Interactive,
    [switch]$WhatIf,
    [switch]$CentralizedMonitoring,
    [switch]$Help,
    [switch]$Debug
)

# Configuration
$ErrorActionPreference = "Stop"

# Available alert types
$script:AvailableAlertTypes = @{
    "VirtualHub" = @{
        "Name" = "Virtual Hub Alerts"
        "Description" = "BGP Peer Status, Data Processing Capacity"
        "Templates" = 2
    }
    "S2SVPN" = @{
        "Name" = "Site-to-Site VPN Alerts"
        "Description" = "Tunnel Bandwidth, Activity Log, Egress Bytes, BGP Status, Packet Drops, Disconnect Events"
        "Templates" = 6
    }
    "ExpressRoute" = @{
        "Name" = "ExpressRoute Gateway Alerts"
        "Description" = "CPU Utilization, Connection Bandwidth In/Out, Performance Monitoring"
        "Templates" = 3
    }
    "Firewall" = @{
        "Name" = "Azure Firewall Alerts"
        "Description" = "SNAT Port Utilization, Security Monitoring"
        "Templates" = 1
    }
    "All" = @{
        "Name" = "All Alert Types"
        "Description" = "Deploy all available alert templates"
        "Templates" = 12
    }
}

# Help function
function Show-Help {
    Write-Host @"
Azure Monitor Baseline Alerts for Azure Virtual WAN

USAGE:
    .\deploy-alerts.ps1 [OPTIONS]

OPTIONS:
    -SubscriptionIds <string[]>    Array of Azure subscription IDs (supports multiple)
    -ResourceGroup <string>        Resource group for alerts (default: rg-vwan-monitoring)
    -Location <string>             Azure region (default: East US)  
    -LogAnalyticsWorkspace <string> Log Analytics workspace resource ID (supports cross-subscription workspaces)
    -AlertTypes <string[]>         Alert types to deploy: VirtualHub, S2SVPN, ExpressRoute, Firewall, All
    -ActionGroupName <string>      Name for new action group (use with notification parameters)
    -ActionGroupResourceGroup <string> Resource group for action group (defaults to alert resource group)
    -EmailAddresses <string[]>     Email addresses for alert notifications (comma-separated)
    -SmsNumbers <string[]>         SMS phone numbers with country code (comma-separated)
    -WebhookUrls <string[]>        Webhook URLs for notifications (comma-separated)
    -UseExistingActionGroup        Use existing action group (will prompt for selection)
    -Interactive                   Launch interactive mode for guided deployment
    -WhatIf                        Show what would be deployed without actually deploying
    -CentralizedMonitoring         Deploy all alerts to the specified Location instead of resource regions
    -Help                          Show this help message

ALERT TYPES:
    VirtualHub      - Virtual Hub BGP and data processing alerts (2 templates)
    S2SVPN          - Site-to-Site VPN connectivity and performance alerts (3 templates)
    ExpressRoute    - ExpressRoute Gateway performance and bandwidth alerts (3 templates)
    Firewall        - Azure Firewall security and performance alerts (1 template)
    All             - Deploy all available alert types (9 templates)

EXAMPLES:
    # Interactive mode (recommended for first-time users)
    .\deploy-alerts.ps1 -Interactive

    # Deploy alerts to same regions as monitored resources (default behavior)
    .\deploy-alerts.ps1 -SubscriptionIds "sub1","sub2" -AlertTypes "VirtualHub","S2SVPN"

    # Deploy all alerts to centralized location (legacy behavior)
    .\deploy-alerts.ps1 -SubscriptionIds "12345678-1234-1234-1234-123456789012" -AlertTypes "All" -Location "East US" -CentralizedMonitoring

    # Deploy with existing action group
    .\deploy-alerts.ps1 -AlertTypes "VirtualHub" -UseExistingActionGroup

    # Test deployment without making changes
    .\deploy-alerts.ps1 -Interactive -WhatIf

REQUIREMENTS:
    - Azure CLI installed and authenticated
    - Azure PowerShell module (optional, for enhanced functionality)
    - Appropriate permissions to create alerts and read vWAN resources across target subscriptions
    - Log Analytics workspace for log-based alerts (supports cross-subscription workspaces)

CROSS-SUBSCRIPTION SUPPORT:
    This script supports enterprise landing zone patterns where Log Analytics workspaces
    are in a separate management/logging subscription from the vWAN connectivity resources.
    The script will automatically discover workspaces across all accessible subscriptions.
"@
}

if ($Help) {
    Show-Help
    exit 0
}

# Logging functions
function Write-Log {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message" -ForegroundColor Blue
}

# Test Azure CLI connectivity
function Test-AzureCliConnectivity {
    param([string]$SubscriptionId)
    
    Write-Log "Testing Azure CLI connectivity..."
    try {
        # Test basic connectivity
        $currentAccount = az account show --query "user.name" --output tsv 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($currentAccount)) {
            Write-Error-Log "Azure CLI is not authenticated or not working properly."
            Write-Host "Please run 'az login' to authenticate with Azure." -ForegroundColor Yellow
            return $false
        }
        
        Write-Log "Authenticated as: $currentAccount"
        
        # Test subscription access if provided
        if (![string]::IsNullOrEmpty($SubscriptionId)) {
            $subTest = az account show --subscription $SubscriptionId --query "id" --output tsv 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($subTest)) {
                Write-Warning-Log "Cannot access subscription '$SubscriptionId'. Please check permissions."
                return $false
            }
            Write-Log "Subscription access confirmed: $SubscriptionId"
        }
        
        return $true
    }
    catch {
        Write-Error-Log "Azure CLI connectivity test failed: $($_.Exception.Message)"
        return $false
    }
}

function Write-Error-Log {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning-Log {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

# Helper function to get action group ID for a resource
function Get-ActionGroupForResource {
    param(
        [string]$ResourceId,
        [string]$DeploymentRegion = $Location
    )
    
    if (-not $script:ActionGroupIds -or $script:ActionGroupIds.Count -eq 0) {
        return ""
    }
    
    # Extract subscription ID from resource ID
    if ($ResourceId -match "/subscriptions/([^/]+)/") {
        $subscriptionId = $matches[1]
        
        # For regional deployment, look for region-specific action group first
        if (-not $CentralizedMonitoring) {
            $regionKey = "${subscriptionId}-${DeploymentRegion}"
            if ($script:ActionGroupIds.ContainsKey($regionKey)) {
                return $script:ActionGroupIds[$regionKey]
            }
        }
        
        # Fall back to subscription-level action group
        if ($script:ActionGroupIds.ContainsKey($subscriptionId)) {
            return $script:ActionGroupIds[$subscriptionId]
        }
    }
    
    # Fall back to first available action group
    $firstKey = $script:ActionGroupIds.Keys | Select-Object -First 1
    if ($firstKey) {
        return $script:ActionGroupIds[$firstKey]
    }
    
    return ""
}

function Get-UniqueRegionsForSubscription {
    param(
        [string]$SubscriptionId,
        [hashtable]$Resources
    )
    
    $regions = @()
    
    # Collect regions from all resource types for this subscription
    if ($Resources.VirtualHubs) {
        $regions += $Resources.VirtualHubs | Where-Object { $_.id -match "/subscriptions/$SubscriptionId/" } | ForEach-Object { $_.location }
    }
    if ($Resources.VpnGateways) {
        $regions += $Resources.VpnGateways | Where-Object { $_.id -match "/subscriptions/$SubscriptionId/" } | ForEach-Object { $_.location }
    }
    if ($Resources.ErGateways) {
        $regions += $Resources.ErGateways | Where-Object { $_.id -match "/subscriptions/$SubscriptionId/" } | ForEach-Object { $_.location }
    }
    if ($Resources.Firewalls) {
        $regions += $Resources.Firewalls | Where-Object { $_.id -match "/subscriptions/$SubscriptionId/" } | ForEach-Object { $_.location }
    }
    
    # Return unique regions, fallback to default location if no resources found
    $uniqueRegions = $regions | Sort-Object -Unique
    if ($uniqueRegions.Count -eq 0) {
        return @($Location)
    }
    
    return $uniqueRegions
}

function Select-NotificationTypes {
    Write-Host "`n[NOTIFY] Notification Types Selection" -ForegroundColor Cyan
    Write-Host ("=" * 40) -ForegroundColor Cyan
    Write-Host "Select the types of notifications you want to configure:" -ForegroundColor Gray
    Write-Host "You can select multiple options by entering numbers separated by commas (e.g., 1,2,3)" -ForegroundColor Gray
    
    $notificationOptions = @(
        @{ Number = 1; Name = "Email"; Description = "Email notifications to specified addresses" }
        @{ Number = 2; Name = "SMS"; Description = "Text message notifications to phone numbers" }
        @{ Number = 3; Name = "Webhook"; Description = "HTTP POST notifications to webhook URLs" }
    )
    
    Write-Host "`n[LIST] Available Notification Types:" -ForegroundColor Green
    foreach ($option in $notificationOptions) {
        Write-Host "$($option.Number). $($option.Name)" -ForegroundColor White
        Write-Host "   $($option.Description)" -ForegroundColor Gray
    }
    
    Write-Host "0. None (create action group without notifications)" -ForegroundColor Gray
    
    do {
        $selection = Read-Host "`nEnter your selection (0 or 1-3, comma-separated)"
        
        if ($selection -eq "0") {
            Write-Host "[OK] No notifications selected. Action group will be created without notifications." -ForegroundColor Yellow
            return @()
        }
        
        # Parse selection
        $selectedNumbers = @()
        $isValid = $true
        
        try {
            $inputNumbers = $selection -split ',' | ForEach-Object { $_.Trim() }
            foreach ($num in $inputNumbers) {
                $numInt = [int]$num
                if ($numInt -ge 1 -and $numInt -le $notificationOptions.Count) {
                    $selectedNumbers += $numInt
                } else {
                    $isValid = $false
                    break
                }
            }
        }
        catch {
            $isValid = $false
        }
        
        if ($isValid -and $selectedNumbers.Count -gt 0) {
            $selectedTypes = @()
            foreach ($num in $selectedNumbers) {
                $selectedTypes += ($notificationOptions | Where-Object { $_.Number -eq $num }).Name
            }
            
            Write-Host "`n[OK] Selected notification types:" -ForegroundColor Green
            foreach ($type in $selectedTypes) {
                Write-Host "   * $type" -ForegroundColor White
            }
            
            return $selectedTypes
        } else {
            Write-Host "[ERROR] Invalid selection. Please enter numbers between 1-$($notificationOptions.Count) separated by commas, or 0 for none." -ForegroundColor Red
        }
    } while ($true)
}

# Action Group functions
function Get-ActionGroupConfiguration {
    param([string]$SubscriptionId)
    
    Write-Host "`n[EMAIL] Action Group Configuration" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    
    Write-Host "`nAction groups define how you'll be notified when alerts fire."
    Write-Host "You can create a new action group or use an existing one.`n"
    
    do {
        Write-Host "Choose an option:" -ForegroundColor Yellow
        Write-Host "[1] Create new action group" -ForegroundColor White
        Write-Host "[2] Use existing action group" -ForegroundColor White
        Write-Host "[3] Skip action group (alerts won't send notifications)" -ForegroundColor Gray
        
        $choice = Read-Host "`nSelection (1-3)"
        
        switch ($choice) {
            "1" { 
                return New-ActionGroupConfiguration -SubscriptionId $SubscriptionId
            }
            "2" { 
                return Select-ExistingActionGroup -SubscriptionId $SubscriptionId
            }
            "3" { 
                Write-Warning-Log "Skipping action group configuration. Alerts will be created but won't send notifications."
                return $null
            }
            default { 
                Write-Warning-Log "Invalid selection. Please choose 1, 2, or 3."
            }
        }
    } while ($true)
}

function New-ActionGroupConfiguration {
    param([string]$SubscriptionId)
    
    Write-Host "`n[NEW] Create New Action Group" -ForegroundColor Green
    Write-Host ("=" * 40) -ForegroundColor Green
    
    # Get action group name with default
    Write-Host "`n[INPUT] Action Group Name:" -ForegroundColor Yellow
    $defaultAgName = "ag-vwan-alerts"
    $agNameInput = Read-Host "Enter action group name (default: $defaultAgName, press Enter to accept)"
    $agName = if ([string]::IsNullOrWhiteSpace($agNameInput)) { $defaultAgName } else { $agNameInput.Trim() }
    
    # Get resource group for action group with proper default handling
    Write-Host "`n[FOLDER] Resource Group:" -ForegroundColor Yellow
    $defaultRg = if ($script:TargetResourceGroup) { $script:TargetResourceGroup } else { "rg-vwan-monitoring" }
    Write-Host "Default: $defaultRg" -ForegroundColor Gray
    $agRgInput = Read-Host "Enter resource group for action group (press Enter for default)"
    $agRg = if ([string]::IsNullOrWhiteSpace($agRgInput)) { $defaultRg } else { $agRgInput.Trim() }
    
    # Select notification types
    $selectedNotificationTypes = Select-NotificationTypes
    
    # Configure selected notification types
    $notifications = @{}
    
    foreach ($notificationType in $selectedNotificationTypes) {
        switch ($notificationType) {
            "Email" {
                Write-Host "`n[EMAIL] Email Notifications Configuration" -ForegroundColor Yellow
                $emailInput = Read-Host "Enter email addresses (comma-separated)"
                if (![string]::IsNullOrWhiteSpace($emailInput)) {
                    $notifications.Emails = $emailInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^[^\s@]+@[^\s@]+\.[^\s@]+$" }
                    if ($notifications.Emails.Count -eq 0) {
                        Write-Warning-Log "No valid email addresses found."
                    } else {
                        Write-Host "[OK] Added $($notifications.Emails.Count) email recipient(s)" -ForegroundColor Green
                    }
                }
            }
            "SMS" {
                Write-Host "`n[SMS] SMS Notifications Configuration" -ForegroundColor Yellow
                Write-Host "Format: +1234567890 (include country code)" -ForegroundColor Gray
                $smsInput = Read-Host "Enter phone numbers (comma-separated)"
                if (![string]::IsNullOrWhiteSpace($smsInput)) {
                    $notifications.SMS = $smsInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^\+?[0-9]{10,15}$" }
                    if ($notifications.SMS.Count -eq 0) {
                        Write-Warning-Log "No valid phone numbers found."
                    } else {
                        Write-Host "[OK] Added $($notifications.SMS.Count) SMS recipient(s)" -ForegroundColor Green
                    }
                }
            }
            "Webhook" {
                Write-Host "`n[WEBHOOK] Webhook Notifications Configuration" -ForegroundColor Yellow
                Write-Host "Format: https://your-webhook-url.com/endpoint" -ForegroundColor Gray
                $webhookInput = Read-Host "Enter webhook URLs (comma-separated)"
                if (![string]::IsNullOrWhiteSpace($webhookInput)) {
                    $notifications.Webhooks = $webhookInput -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match "^https?://" }
                    if ($notifications.Webhooks.Count -eq 0) {
                        Write-Warning-Log "No valid webhook URLs found."
                    } else {
                        Write-Host "[OK] Added $($notifications.Webhooks.Count) webhook(s)" -ForegroundColor Green
                    }
                }
            }
        }
    }
    
    if ($notifications.Count -eq 0) {
        Write-Warning-Log "No notifications configured. Action group will be created but won't send notifications."
    } else {
        Write-Host "`n[OK] Action group configuration completed:" -ForegroundColor Green
        Write-Host "   Name: $agName" -ForegroundColor White
        Write-Host "   Resource Group: $agRg" -ForegroundColor White
        if ($notifications.Emails) { Write-Host "   Email recipients: $($notifications.Emails.Count)" -ForegroundColor White }
        if ($notifications.SMS) { Write-Host "   SMS recipients: $($notifications.SMS.Count)" -ForegroundColor White }
        if ($notifications.Webhooks) { Write-Host "   Webhooks: $($notifications.Webhooks.Count)" -ForegroundColor White }
    }
    
    return @{
        Name = $agName
        ResourceGroup = $agRg
        SubscriptionId = $SubscriptionId
        Notifications = $notifications
        IsNew = $true
    }
}

function Select-ExistingActionGroup {
    param([string]$SubscriptionId)
    
    Write-Host "`n[SEARCH] Searching for existing action groups..." -ForegroundColor Yellow
    
    try {
        $existingAGs = az monitor action-group list --subscription $SubscriptionId --query "[].{name:name, resourceGroup:resourceGroup, id:id}" | ConvertFrom-Json
        
        if ($existingAGs.Count -eq 0) {
            Write-Warning-Log "No existing action groups found in subscription. Creating a new one instead."
            return New-ActionGroupConfiguration -SubscriptionId $SubscriptionId
        }
        
        Write-Host "`n[LIST] Existing Action Groups:" -ForegroundColor Green
        Write-Host ("=" * 40) -ForegroundColor Green
        
        for ($i = 0; $i -lt $existingAGs.Count; $i++) {
            $ag = $existingAGs[$i]
            Write-Host "[$($i + 1)] $($ag.name)" -ForegroundColor Yellow
            Write-Host "     Resource Group: $($ag.resourceGroup)" -ForegroundColor Gray
        }
        
        do {
            $selection = Read-Host "`nSelect action group (1-$($existingAGs.Count))"
            $index = [int]$selection - 1
            
            if ($index -ge 0 -and $index -lt $existingAGs.Count) {
                $selectedAG = $existingAGs[$index]
                return @{
                    Name = $selectedAG.name
                    ResourceGroup = $selectedAG.resourceGroup
                    SubscriptionId = $SubscriptionId
                    Id = $selectedAG.id
                    IsNew = $false
                }
            }
            Write-Warning-Log "Invalid selection. Please choose a number between 1 and $($existingAGs.Count)."
        } while ($true)
    }
    catch {
        Write-Error-Log "Failed to retrieve existing action groups: $_"
        Write-Host "Would you like to create a new action group instead? (y/n): " -NoNewline
        $response = Read-Host
        if ($response -eq 'y' -or $response -eq 'Y') {
            return New-ActionGroupConfiguration -SubscriptionId $SubscriptionId
        }
        return $null
    }
}

function New-ActionGroup {
    param(
        [hashtable]$ActionGroupConfig,
        [string]$Region = $Location,
        [bool]$WhatIfMode = $false
    )
    
    if (-not $ActionGroupConfig.IsNew) {
        Write-Log "Using existing action group: $($ActionGroupConfig.Name)"
        return $ActionGroupConfig.Id
    }
    
    if ($WhatIfMode) {
        Write-Log "[WHAT-IF] Would create action group '$($ActionGroupConfig.Name)' in region '$Region'"
        Write-Log "[WHAT-IF] Would create resource group '$($ActionGroupConfig.ResourceGroup)' if needed"
        return "what-if-action-group-id"
    }
    
    Write-Log "Creating action group '$($ActionGroupConfig.Name)' in region '$Region'..."
    
    try {
        # Create resource group if it doesn't exist
        New-ResourceGroupIfNotExists -ResourceGroup $ActionGroupConfig.ResourceGroup -Region $Region -WhatIfMode $WhatIfMode
        
        # Build action group creation command
        $agCommand = "az monitor action-group create --name '$($ActionGroupConfig.Name)' --resource-group '$($ActionGroupConfig.ResourceGroup)' --subscription '$($ActionGroupConfig.SubscriptionId)'"
        
        # Add email notifications using the correct format
        if ($ActionGroupConfig.Notifications.Emails -and $ActionGroupConfig.Notifications.Emails.Count -gt 0) {
            $emailReceivers = @()
            for ($i = 0; $i -lt $ActionGroupConfig.Notifications.Emails.Count; $i++) {
                $email = $ActionGroupConfig.Notifications.Emails[$i]
                $emailReceivers += @{
                    name = "email-$($i + 1)"
                    emailAddress = $email
                }
            }
            # Convert to JSON format for Azure CLI
            $emailJson = ($emailReceivers | ConvertTo-Json -Compress) -replace '"', '\"'
            $agCommand += " --email-receivers '$emailJson'"
        }
        
        # Add SMS notifications using the correct format
        if ($ActionGroupConfig.Notifications.SMS -and $ActionGroupConfig.Notifications.SMS.Count -gt 0) {
            $smsReceivers = @()
            for ($i = 0; $i -lt $ActionGroupConfig.Notifications.SMS.Count; $i++) {
                $phone = $ActionGroupConfig.Notifications.SMS[$i]
                # Extract country code and number
                if ($phone -match '^\+?(\d{1,3})(\d{10,12})$') {
                    $countryCode = $matches[1]
                    $number = $matches[2]
                    $smsReceivers += @{
                        name = "sms-$($i + 1)"
                        countryCode = $countryCode
                        phoneNumber = $number
                    }
                }
            }
            if ($smsReceivers.Count -gt 0) {
                $smsJson = ($smsReceivers | ConvertTo-Json -Compress) -replace '"', '\"'
                $agCommand += " --sms-receivers '$smsJson'"
            }
        }
        
        # Add webhook notifications using the correct format
        if ($ActionGroupConfig.Notifications.Webhooks -and $ActionGroupConfig.Notifications.Webhooks.Count -gt 0) {
            $webhookReceivers = @()
            for ($i = 0; $i -lt $ActionGroupConfig.Notifications.Webhooks.Count; $i++) {
                $webhook = $ActionGroupConfig.Notifications.Webhooks[$i]
                $webhookReceivers += @{
                    name = "webhook-$($i + 1)"
                    serviceUri = $webhook
                }
            }
            $webhookJson = ($webhookReceivers | ConvertTo-Json -Compress) -replace '"', '\"'
            $agCommand += " --webhook-receivers '$webhookJson'"
        }
        
        # Execute the command
        $result = Invoke-Expression "$agCommand --query 'id' --output tsv"
        
        if ($LASTEXITCODE -eq 0 -and $result) {
            Write-Success "Action group '$($ActionGroupConfig.Name)' created successfully"
            return $result.Trim()
        } else {
            Write-Error-Log "Failed to create action group '$($ActionGroupConfig.Name)'"
            return $null
        }
    }
    catch {
        Write-Error-Log "Error creating action group: $_"
        return $null
    }
}

# Interactive menu functions
function Show-WelcomeBanner {
    Write-Host @"

╔════════════════════════════════════════════════════════════════════════════════════╗
║                Azure Monitor Baseline Alerts for Azure Virtual WAN                ║
║                                                                                    ║
║  This interactive tool will guide you through deploying monitoring alerts         ║
║  for your Azure Virtual WAN infrastructure following AMBA best practices.         ║
╚════════════════════════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan
}

function Get-UserSubscriptions {
    Write-Log "Discovering available Azure subscriptions..."
    
    try {
        $subscriptions = az account list --query "[?state=='Enabled'].{id:id, name:name, tenantId:tenantId}" | ConvertFrom-Json
        
        if (-not $subscriptions -or $subscriptions.Count -eq 0) {
            Write-Error-Log "No enabled subscriptions found. Please ensure you're logged in with appropriate permissions."
            return @()
        }
        
        Write-Host "`nAvailable Subscriptions:" -ForegroundColor Green
        Write-Host ("=" * 80) -ForegroundColor Green
        
        for ($i = 0; $i -lt $subscriptions.Count; $i++) {
            $sub = $subscriptions[$i]
            Write-Host "[$($i + 1)] $($sub.name)" -ForegroundColor Yellow
            Write-Host "     ID: $($sub.id)" -ForegroundColor Gray
            Write-Host "     Tenant: $($sub.tenantId)" -ForegroundColor Gray
            Write-Host ""
        }
        
        return $subscriptions
    }
    catch {
        Write-Error-Log "Failed to retrieve subscriptions: $_"
        return @()
    }
}

function Select-Subscriptions {
    param([array]$Subscriptions)
    
    Write-Host "Select subscriptions to deploy alerts to:" -ForegroundColor Cyan
    Write-Host "Enter numbers separated by commas (e.g., 1,3,5) or 'all' for all subscriptions" -ForegroundColor White
    
    do {
        $selection = Read-Host "Selection"
        $selectedSubs = @()
        
        if ($selection.ToLower() -eq 'all') {
            $selectedSubs = $Subscriptions
            break
        }
        
        try {
            $numbers = $selection -split ',' | ForEach-Object { [int]$_.Trim() }
            
            foreach ($num in $numbers) {
                if ($num -ge 1 -and $num -le $Subscriptions.Count) {
                    $selectedSubs += $Subscriptions[$num - 1]
                } else {
                    Write-Warning-Log "Invalid selection: $num. Please choose numbers between 1 and $($Subscriptions.Count)."
                    $selectedSubs = @()
                    break
                }
            }
            
            if ($selectedSubs.Count -gt 0) {
                break
            }
        }
        catch {
            Write-Warning-Log "Invalid input format. Please enter numbers separated by commas."
        }
    } while ($true)
    
    Write-Host "`nSelected Subscriptions:" -ForegroundColor Green
    foreach ($sub in $selectedSubs) {
        Write-Host "  • $($sub.name) ($($sub.id))" -ForegroundColor Yellow
    }
    
    return $selectedSubs
}

function Show-AlertTypeMenu {
    Write-Host "`nAvailable Alert Types:" -ForegroundColor Cyan
    Write-Host ("=" * 80) -ForegroundColor Cyan
    
    $index = 1
    foreach ($key in $script:AvailableAlertTypes.Keys) {
        $alertType = $script:AvailableAlertTypes[$key]
        Write-Host "[$index] $($alertType.Name)" -ForegroundColor Yellow
        Write-Host "    Description: $($alertType.Description)" -ForegroundColor Gray
        Write-Host "    Templates: $($alertType.Templates)" -ForegroundColor Gray
        Write-Host ""
        $index++
    }
}

function Select-AlertTypes {
    Show-AlertTypeMenu
    
    Write-Host "Select alert types to deploy:" -ForegroundColor Cyan
    Write-Host "Enter numbers separated by commas (e.g., 1,2,4) or 'all' for all types" -ForegroundColor White
    
    $alertTypeKeys = @($script:AvailableAlertTypes.Keys)
    
    do {
        $selection = Read-Host "Selection"
        $selectedTypes = @()
        
        if ($selection.ToLower() -eq 'all') {
            $selectedTypes = @("All")
            break
        }
        
        try {
            $numbers = $selection -split ',' | ForEach-Object { [int]$_.Trim() }
            
            foreach ($num in $numbers) {
                if ($num -ge 1 -and $num -le $alertTypeKeys.Count) {
                    $selectedTypes += $alertTypeKeys[$num - 1]
                } else {
                    Write-Warning-Log "Invalid selection: $num. Please choose numbers between 1 and $($alertTypeKeys.Count)."
                    $selectedTypes = @()
                    break
                }
            }
            
            if ($selectedTypes.Count -gt 0) {
                break
            }
        }
        catch {
            Write-Warning-Log "Invalid input format. Please enter numbers separated by commas."
        }
    } while ($true)
    
    Write-Host "`nSelected Alert Types:" -ForegroundColor Green
    foreach ($type in $selectedTypes) {
        $alertType = $script:AvailableAlertTypes[$type]
        Write-Host "  • $($alertType.Name)" -ForegroundColor Yellow
    }
    
    return $selectedTypes
}

function Get-ResourceGroupInput {
    param([string]$DefaultRG = "rg-vwan-monitoring")
    
    Write-Host "`n[FOLDER] Resource Group Configuration" -ForegroundColor Cyan
    Write-Host ("=" * 40) -ForegroundColor Cyan
    Write-Host "This resource group will contain the alert rules." -ForegroundColor Gray
    
    Write-Host "`nChoose an option:" -ForegroundColor Yellow
    Write-Host "[1] Use default resource group: $DefaultRG" -ForegroundColor White
    Write-Host "[2] Use existing resource group" -ForegroundColor White  
    Write-Host "[3] Specify custom resource group name" -ForegroundColor White
    
    do {
        $choice = Read-Host "`nSelection (1-3)"
        
        switch ($choice) {
            "1" { 
                Write-Host "Using default resource group: $DefaultRG" -ForegroundColor Green
                return $DefaultRG
            }
            "2" { 
                return Get-ExistingResourceGroup
            }
            "3" { 
                do {
                    $customRG = Read-Host "`nEnter custom resource group name"
                    if ([string]::IsNullOrWhiteSpace($customRG)) {
                        Write-Warning-Log "Resource group name cannot be empty."
                    } else {
                        Write-Host "Using custom resource group: $customRG" -ForegroundColor Green
                        return $customRG
                    }
                } while ($true)
            }
            default { 
                Write-Warning-Log "Invalid selection. Please choose 1, 2, or 3."
            }
        }
    } while ($true)
}

function Get-ExistingResourceGroup {
    Write-Host "`n[SEARCH] Searching for existing resource groups..." -ForegroundColor Yellow
    
    try {
        $existingRGs = az group list --query "[].{name:name, location:location}" | ConvertFrom-Json
        
        if ($existingRGs.Count -eq 0) {
            Write-Warning-Log "No existing resource groups found. Please choose option 1 or 3."
            return $null
        }
        
        Write-Host "`n[LIST] Existing Resource Groups:" -ForegroundColor Green
        Write-Host ("=" * 50) -ForegroundColor Green
        
        for ($i = 0; $i -lt $existingRGs.Count; $i++) {
            $rg = $existingRGs[$i]
            Write-Host "[$($i + 1)] $($rg.name)" -ForegroundColor Yellow
            Write-Host "     Location: $($rg.location)" -ForegroundColor Gray
        }
        
        do {
            $selection = Read-Host "`nSelect resource group (1-$($existingRGs.Count))"
            $index = [int]$selection - 1
            
            if ($index -ge 0 -and $index -lt $existingRGs.Count) {
                $selectedRG = $existingRGs[$index]
                Write-Host "Using existing resource group: $($selectedRG.name)" -ForegroundColor Green
                return $selectedRG.name
            }
            Write-Warning-Log "Invalid selection. Please choose a number between 1 and $($existingRGs.Count)."
        } while ($true)
    }
    catch {
        Write-Error-Log "Failed to retrieve existing resource groups: $_"
        Write-Host "Would you like to specify a custom name instead? (y/n): " -NoNewline
        $response = Read-Host
        if ($response -eq 'y' -or $response -eq 'Y') {
            $customRG = Read-Host "Enter resource group name"
            return $customRG
        }
        return $null
    }
}

function Test-LogAnalyticsWorkspace {
    param(
        [string]$WorkspaceId
    )
    
    if ([string]::IsNullOrEmpty($WorkspaceId)) {
        return $false
    }
    
    Write-Host "Validating Log Analytics workspace access..." -ForegroundColor Gray
    
    try {
        # Extract subscription ID from workspace resource ID
        $subscriptionId = $null
        if ($WorkspaceId -match "/subscriptions/([^/]+)/") {
            $subscriptionId = $matches[1]
        }
        
        if ($subscriptionId) {
            # Try to get workspace details to validate access
            $workspace = az monitor log-analytics workspace show --ids $WorkspaceId --output json 2>$null
            if ($LASTEXITCODE -eq 0 -and ![string]::IsNullOrEmpty($workspace)) {
                $workspaceInfo = $workspace | ConvertFrom-Json
                Write-Host "✓ Validated workspace: $($workspaceInfo.name) in subscription $($subscriptionId.Substring(0,8))..." -ForegroundColor Green
                return $true
            }
        }
        
        # Fallback: try resource show command
        $resource = az resource show --ids $WorkspaceId --output json 2>$null
        if ($LASTEXITCODE -eq 0 -and ![string]::IsNullOrEmpty($resource)) {
            $resourceInfo = $resource | ConvertFrom-Json
            Write-Host "✓ Validated workspace resource: $($resourceInfo.name)" -ForegroundColor Green
            return $true
        }
        
        Write-Warning-Log "Unable to validate workspace access. This may indicate insufficient permissions or the workspace doesn't exist."
        Write-Host "Note: Cross-subscription workspaces require appropriate RBAC permissions." -ForegroundColor Yellow
        return $false
    }
    catch {
        Write-Warning-Log "Workspace validation failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-LogAnalyticsInput {
    Write-Host "`n[DATA] Log Analytics Workspace Configuration" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host "Required for log-based alerts (S2S VPN disconnect events, etc.)" -ForegroundColor Gray
    Write-Host "Supports workspaces in any accessible subscription (landing zone pattern)" -ForegroundColor Gray
    
    # Discover available Log Analytics workspaces across all subscriptions
    Write-Host "`n[SEARCH] Discovering Log Analytics workspaces..." -ForegroundColor Yellow
    
    if ($Debug) {
        Write-Host "[DEBUG] Starting Log Analytics workspace discovery..." -ForegroundColor Magenta
        $currentSub = az account show --query "name" --output tsv 2>$null
        Write-Host "[DEBUG] Current subscription: $currentSub" -ForegroundColor Magenta
    }
    
    try {
        # Always search across ALL accessible subscriptions for Log Analytics workspaces
        # This is important for landing zone designs where workspaces are in management/logging subscriptions
        Write-Host "Searching for Log Analytics workspaces across all accessible subscriptions..." -ForegroundColor Gray
        $allWorkspaces = @()
        $workspacesBySubscription = @{}
        
        # Get current subscription list
        $subs = az account list --query "[?state=='Enabled'].{id:id, name:name}" --output json 2>$null | ConvertFrom-Json
        if (-not $subs -or $subs.Count -eq 0) {
            Write-Warning-Log "Unable to retrieve subscription list. Please check your Azure CLI authentication."
            return
        }
        
        Write-Host "Checking $($subs.Count) accessible subscription(s)..." -ForegroundColor Gray
        
        foreach ($sub in $subs) {
            try {
                if ($Debug) {
                    Write-Host "[DEBUG] Searching subscription: $($sub.name) ($($sub.id))" -ForegroundColor Magenta
                }
                
                $subWorkspacesJson = az resource list --subscription $sub.id --resource-type "Microsoft.OperationalInsights/workspaces" --query "[].{id:id, name:name, resourceGroup:resourceGroup, location:location, subscriptionId:'$($sub.id)', subscriptionName:'$($sub.name)'}" --output json 2>$null
                if ($LASTEXITCODE -eq 0 -and ![string]::IsNullOrEmpty($subWorkspacesJson)) {
                    $subWorkspaces = $subWorkspacesJson | ConvertFrom-Json
                    if ($subWorkspaces -and $subWorkspaces.Count -gt 0) {
                        $allWorkspaces += $subWorkspaces
                        $workspacesBySubscription[$sub.name] = $subWorkspaces
                        Write-Host "  ✓ Found $($subWorkspaces.Count) workspace(s) in '$($sub.name)'" -ForegroundColor Green
                        
                        if ($Debug) {
                            foreach ($ws in $subWorkspaces) {
                                Write-Host "    [DEBUG] Workspace: $($ws.name) in $($ws.resourceGroup)" -ForegroundColor Magenta
                            }
                        }
                    }
                } else {
                    if ($Debug) {
                        Write-Host "    [DEBUG] No workspaces found in $($sub.name)" -ForegroundColor Magenta
                    }
                }
            }
            catch {
                Write-Warning-Log "Failed to search subscription '$($sub.name)': $($_.Exception.Message)"
                if ($Debug) {
                    Write-Host "[DEBUG] Error details: $($_.Exception)" -ForegroundColor Magenta
                }
            }
        }
        
        $workspaces = $allWorkspaces
        
        # Show summary of discovered workspaces
        if ($workspaces -and $workspaces.Count -gt 0) {
            Write-Host "`n✓ Successfully discovered $($workspaces.Count) Log Analytics workspace(s) across $($subs.Count) subscription(s)" -ForegroundColor Green
            
            # Show unique subscription count where workspaces were found
            $workspaceSubscriptions = $workspaces | Group-Object subscriptionName | Measure-Object
            if ($workspaceSubscriptions.Count -gt 0) {
                Write-Host "  Found workspaces in $($workspaceSubscriptions.Count) subscription(s)" -ForegroundColor Gray
            }
        }
        
        if (-not $workspaces -or $workspaces.Count -eq 0) {
            Write-Warning-Log "No Log Analytics workspaces found in accessible subscriptions."
            
            # Show debugging information if Debug flag is set
            if ($Debug) {
                Write-Host "`n[DEBUG] Log Analytics Discovery Troubleshooting:" -ForegroundColor Magenta
                Write-Host "1. Check if you have any Log Analytics workspaces:" -ForegroundColor Magenta
                Write-Host "   az resource list --resource-type 'Microsoft.OperationalInsights/workspaces' --output table" -ForegroundColor Gray
                Write-Host "2. Check permissions on subscriptions" -ForegroundColor Magenta
                Write-Host "3. Verify you have Reader role on workspaces or subscriptions" -ForegroundColor Magenta
                
                # Try a simple test command
                Write-Host "`n[DEBUG] Testing basic resource list command..." -ForegroundColor Magenta
                $testResult = az resource list --resource-type "Microsoft.OperationalInsights/workspaces" --output table 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "[DEBUG] Command succeeded. Raw output:" -ForegroundColor Magenta
                    Write-Host $testResult -ForegroundColor Gray
                } else {
                    Write-Host "[DEBUG] Command failed with exit code: $LASTEXITCODE" -ForegroundColor Magenta
                }
            }
            
            Write-Host "`nOptions:" -ForegroundColor Cyan
            Write-Host "1. Skip log-based alerts (metric alerts only)" -ForegroundColor White
            Write-Host "2. Enter workspace ID manually" -ForegroundColor White
            Write-Host "3. Run debug mode for troubleshooting (restart with -Debug)" -ForegroundColor Gray
            
            $choice = Read-Host "`nSelect option (1-3)"
            
            switch ($choice) {
                "1" {
                    Write-Host "[OK] Skipping log-based alerts. Only metric alerts will be deployed." -ForegroundColor Green
                    return ""
                }
                "2" {
                    $workspace = Read-Host "Enter Log Analytics workspace resource ID"
                    return $workspace.Trim()
                }
                "3" {
                    Write-Host "[INFO] Please restart the script with the -Debug parameter:" -ForegroundColor Yellow
                    Write-Host ".\deploy-alerts.ps1 -Interactive -Debug" -ForegroundColor White
                    Write-Host "This will provide detailed troubleshooting information." -ForegroundColor Gray
                    return ""
                }
                default {
                    Write-Host "[OK] Invalid selection. Skipping log-based alerts." -ForegroundColor Yellow
                    return ""
                }
            }
        }
        
        # Display available workspaces grouped by subscription
        Write-Host "`n[LIST] Available Log Analytics Workspaces:" -ForegroundColor Green
        Write-Host "0. Skip log-based alerts (metric alerts only)" -ForegroundColor Gray
        
        # Group and display workspaces by subscription for better clarity
        $currentSubName = ""
        for ($i = 0; $i -lt $workspaces.Count; $i++) {
            $workspace = $workspaces[$i]
            
            # Show subscription header if it's different from the last one
            if ($workspace.subscriptionName -ne $currentSubName) {
                $currentSubName = $workspace.subscriptionName
                Write-Host "`n  📋 Subscription: $currentSubName" -ForegroundColor Cyan
            }
            
            Write-Host "    $($i + 1). $($workspace.name)" -ForegroundColor White
            Write-Host "       Resource Group: $($workspace.resourceGroup)" -ForegroundColor Gray
            Write-Host "       Location: $($workspace.location)" -ForegroundColor Gray
        }
        
        Write-Host "`n$($workspaces.Count + 1). Enter workspace ID manually" -ForegroundColor White
        
        # Get user selection
        $maxChoice = $workspaces.Count + 1
        do {
            $choice = Read-Host "`nSelect workspace (0-$maxChoice)"
            $choiceInt = $null
            $validChoice = [int]::TryParse($choice, [ref]$choiceInt) -and $choiceInt -ge 0 -and $choiceInt -le $maxChoice
            if (-not $validChoice) {
                Write-Host "[ERROR] Please enter a number between 0 and $maxChoice" -ForegroundColor Red
            }
        } while (-not $validChoice)
        
        switch ($choiceInt) {
            0 {
                Write-Host "[OK] Skipping log-based alerts. Only metric alerts will be deployed." -ForegroundColor Green
                return ""
            }
            { $_ -le $workspaces.Count } {
                $selectedWorkspace = $workspaces[$choiceInt - 1]
                Write-Host "[OK] Selected workspace: $($selectedWorkspace.name)" -ForegroundColor Green
                return $selectedWorkspace.id
            }
            { $_ -eq ($workspaces.Count + 1) } {
                Write-Host "`n[INPUT] Manual Entry:" -ForegroundColor Cyan
                Write-Host "Supports workspaces from any accessible subscription (including different subscription than vWAN resources)" -ForegroundColor Gray
                Write-Host "Format: /subscriptions/{sub-id}/resourceGroups/{rg-name}/providers/Microsoft.OperationalInsights/workspaces/{workspace-name}" -ForegroundColor Gray
                $workspace = Read-Host "Enter Log Analytics workspace resource ID"
                
                # Validate the manually entered workspace
                if (![string]::IsNullOrWhiteSpace($workspace)) {
                    Write-Host "Validating workspace access..." -ForegroundColor Gray
                    Test-LogAnalyticsWorkspace -WorkspaceId $workspace.Trim() | Out-Null
                }
                
                return $workspace.Trim()
            }
        }
    }
    catch {
        Write-Warning-Log "Failed to discover Log Analytics workspaces: $($_.Exception.Message)"
        Write-Host "`n[INPUT] Manual Entry Required:" -ForegroundColor Yellow
        Write-Host "Supports workspaces from any accessible subscription (including different subscription than vWAN resources)" -ForegroundColor Gray
        Write-Host "Format: /subscriptions/{sub-id}/resourceGroups/{rg-name}/providers/Microsoft.OperationalInsights/workspaces/{workspace-name}" -ForegroundColor Gray
        $workspace = Read-Host "Enter Log Analytics workspace resource ID (optional, press Enter to skip)"
        
        if ([string]::IsNullOrWhiteSpace($workspace)) {
            Write-Warning-Log "Log Analytics workspace not specified. Log-based alerts will be skipped."
            return ""
        }
        
        # Validate the manually entered workspace
        Write-Host "Validating workspace access..." -ForegroundColor Gray
        Test-LogAnalyticsWorkspace -WorkspaceId $workspace.Trim() | Out-Null
        
        return $workspace.Trim()
    }
}

# Get Virtual Hub scale unit configuration from user
function Get-VirtualHubScaleUnits {
    param([array]$VirtualHubs)
    
    if (-not $VirtualHubs -or $VirtualHubs.Count -eq 0) {
        return @{}
    }
    
    Write-Host "`n[HUB] Virtual Hub Configuration" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host "Configure routing infrastructure units (RIUs) for each Virtual Hub." -ForegroundColor Yellow
    Write-Host "Each RIU provides 1 Gbps of data processing capacity." -ForegroundColor Gray
    Write-Host "Typical values: 2-10 RIUs (default: 2)" -ForegroundColor Gray
    
    $hubScaleUnits = @{}
    
    foreach ($hub in $VirtualHubs) {
        Write-Host "`nVirtual Hub: $($hub.name) (Location: $($hub.location))" -ForegroundColor White
        
        do {
            $riuInput = Read-Host "Enter routing infrastructure units (2-50, default 2)"
            $rius = 0  # Initialize variable for [ref] usage
            
            if ([string]::IsNullOrWhiteSpace($riuInput)) {
                $rius = 2
                Write-Host "[OK] Using default: 2 RIUs" -ForegroundColor Green
                break
            }
            
            if ([int]::TryParse($riuInput.Trim(), [ref]$rius)) {
                if ($rius -ge 2 -and $rius -le 50) {
                    Write-Host "[OK] Set to $rius RIUs ($rius Gbps capacity)" -ForegroundColor Green
                    break
                } else {
                    Write-Warning-Log "RIUs must be between 2 and 50. Please try again."
                }
            } else {
                Write-Warning-Log "Invalid input. Please enter a number between 2 and 50."
            }
        } while ($true)
        
        $hubScaleUnits[$hub.id] = $rius
    }
    
    return $hubScaleUnits
}

function Confirm-Deployment {
    param(
        [array]$Subscriptions,
        [array]$AlertTypes,
        [string]$ResourceGroup,
        [string]$LogWorkspace,
        [object]$ActionGroupConfig,
        [bool]$WhatIfMode
    )
    
    Write-Host "`n" + ("=" * 80) -ForegroundColor Green
    Write-Host "DEPLOYMENT SUMMARY" -ForegroundColor Green -BackgroundColor Black
    Write-Host ("=" * 80) -ForegroundColor Green
    
    Write-Host "Subscriptions ($($Subscriptions.Count)):" -ForegroundColor Cyan
    foreach ($sub in $Subscriptions) {
        Write-Host "  • $($sub.name)" -ForegroundColor White
    }
    
    Write-Host "`nAlert Types ($($AlertTypes.Count)):" -ForegroundColor Cyan
    foreach ($type in $AlertTypes) {
        $alertType = $script:AvailableAlertTypes[$type]
        Write-Host "  • $($alertType.Name) ($($alertType.Templates) templates)" -ForegroundColor White
    }
    
    Write-Host "`nConfiguration:" -ForegroundColor Cyan
    Write-Host "  Resource Group: $ResourceGroup" -ForegroundColor White
    Write-Host "  Deployment Strategy: $(if ($CentralizedMonitoring) { "Centralized to $Location" } else { "Regional (alerts co-located with monitored resources)" })" -ForegroundColor White
    Write-Host "  Log Analytics: $(if ($LogWorkspace) { $LogWorkspace } else { 'Not configured (log alerts will be skipped)' })" -ForegroundColor White
    
    if ($ActionGroupConfig) {
        if ($ActionGroupConfig -eq "per-subscription") {
            Write-Host "  Action Groups: Will be configured per subscription" -ForegroundColor White
        } elseif ($ActionGroupConfig.GetType().Name -eq "Hashtable") {
            if ($ActionGroupConfig.IsNew) {
                Write-Host "  Action Groups: New action group '$($ActionGroupConfig.Name)' will be created" -ForegroundColor White
            } else {
                Write-Host "  Action Groups: Using existing action group '$($ActionGroupConfig.Name)'" -ForegroundColor White
            }
        }
    } else {
        Write-Host "  Action Groups: Not configured (alerts won't send notifications)" -ForegroundColor Yellow
    }
    
    Write-Host "  What-If Mode: $WhatIfMode" -ForegroundColor White
    
    Write-Host "`n" + ("=" * 80) -ForegroundColor Green
    
    do {
        $confirm = Read-Host "Proceed with deployment? (y/n)"
        $confirm = $confirm.ToLower().Trim()
        
        if ($confirm -eq 'y' -or $confirm -eq 'yes') {
            return $true
        }
        elseif ($confirm -eq 'n' -or $confirm -eq 'no') {
            return $false
        }
        else {
            Write-Warning-Log "Please enter 'y' for yes or 'n' for no."
        }
    } while ($true)
}

# Check prerequisites
function Test-Prerequisites {
    Write-Log "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    try {
        $null = az version 2>$null
    }
    catch {
        Write-Error-Log "Azure CLI is not installed. Please install it first."
        exit 1
    }
    
    # Check if logged in to Azure
    try {
        $null = az account show 2>$null
    }
    catch {
        Write-Error-Log "Not logged in to Azure. Please run 'az login' first."
        exit 1
    }
    
    # Set subscription if provided
    if ($SubscriptionId) {
        Write-Log "Setting subscription to $SubscriptionId"
        az account set --subscription $SubscriptionId
        if ($LASTEXITCODE -ne 0) {
            Write-Error-Log "Failed to set subscription to $SubscriptionId"
            exit 1
        }
    }
    
    Write-Success "Prerequisites check completed"
}

# Create resource group if it doesn't exist
function New-ResourceGroupIfNotExists {
    param(
        [string]$ResourceGroup,
        [string]$Region = $Location,
        [bool]$WhatIfMode = $false
    )
    
    Write-Log "Checking if resource group '$ResourceGroup' exists..."
    
    $groupExists = az group exists --name $ResourceGroup
    if ($groupExists -eq "false") {
        if ($WhatIfMode) {
            Write-Log "[WHAT-IF] Would create resource group '$ResourceGroup' in region '$Region'"
        } else {
            Write-Log "Creating resource group '$ResourceGroup' in region '$Region'..."
            az group create --name $ResourceGroup --location $Region --output none
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Resource group '$ResourceGroup' created in region '$Region'"
            } else {
                Write-Error-Log "Failed to create resource group '$ResourceGroup'"
                exit 1
            }
        }
    } else {
        Write-Success "Resource group '$ResourceGroup' already exists"
    }
}

# Deploy metric alerts
function Deploy-MetricAlert {
    param(
        [string]$TemplatePath,
        [string]$AlertName,
        [string]$Description,
        [string]$TargetResourceId,
        [string]$TargetResourceType,
        [string]$TargetRegion,
        [int]$Severity = 2,
        [string]$TargetResourceGroup,
        [string]$ActionGroupId = ""
    )
    
    Write-Log "Deploying metric alert: $AlertName"
    
    if ($WhatIf) {
        Write-Host "WHAT-IF: Would deploy metric alert '$AlertName' using template '$TemplatePath'" -ForegroundColor Cyan
        return $true
    }
    
    az deployment group create `
        --resource-group $TargetResourceGroup `
        --template-file $TemplatePath `
        --parameters `
            alertName="$AlertName" `
            alertDescription="$Description" `
            targetResourceId="[`"$TargetResourceId`"]" `
            targetResourceRegion="$TargetRegion" `
            targetResourceType="$TargetResourceType" `
            alertSeverity="$Severity" `
        --output none 2>$null
        
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Deployed: $AlertName"
        
        # Add action group to the alert if provided
        if (-not [string]::IsNullOrWhiteSpace($ActionGroupId)) {
            Write-Log "Adding action group to alert: $AlertName"
            az monitor metrics alert update `
                --name "$AlertName" `
                --resource-group $TargetResourceGroup `
                --add-action $ActionGroupId `
                --output none 2>$null
                
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Action group added to: $AlertName"
            } else {
                Write-Warning-Log "Failed to add action group to: $AlertName"
            }
        }
        
        return $true
    } else {
        Write-Error-Log "Failed to deploy: $AlertName"
        return $false
    }
}

# Deploy Virtual Hub Data Processed alert with scale unit configuration
function Deploy-VirtualHubDataProcessedAlert {
    param(
        [string]$AlertName,
        [string]$Description,
        [string]$VirtualHubResourceId,
        [string]$TargetRegion,
        [int]$RoutingInfrastructureUnits = 2,
        [int]$Severity = 3,
        [string]$TargetResourceGroup,
        [string]$ActionGroupId = ""
    )
    
    Write-Log "Deploying Virtual Hub Data Processed alert: $AlertName (RIUs: $RoutingInfrastructureUnits)"
    
    if ($WhatIf) {
        Write-Host "WHAT-IF: Would deploy Virtual Hub Data Processed alert '$AlertName' with $RoutingInfrastructureUnits RIUs" -ForegroundColor Cyan
        return $true
    }
    
    az deployment group create `
        --resource-group $TargetResourceGroup `
        --template-file "services/Network/virtualWans/templates/bicep/VirtualHub-DataProcessed.bicep" `
        --parameters `
            alertName="$AlertName" `
            alertDescription="$Description" `
            virtualHubResourceId="$VirtualHubResourceId" `
            targetResourceRegion="$TargetRegion" `
            routingInfrastructureUnits="$RoutingInfrastructureUnits" `
            alertSeverity="$Severity" `
        --output none 2>$null
        
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Deployed: $AlertName"
        
        # Add action group to the alert if provided
        if (-not [string]::IsNullOrWhiteSpace($ActionGroupId)) {
            Write-Log "Adding action group to alert: $AlertName"
            az monitor metrics alert update `
                --name "$AlertName" `
                --resource-group $TargetResourceGroup `
                --add-action $ActionGroupId `
                --output none 2>$null
                
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Action group added to: $AlertName"
            } else {
                Write-Warning-Log "Failed to add action group to: $AlertName"
            }
        }
        
        return $true
    } else {
        Write-Error-Log "Failed to deploy: $AlertName"
        return $false
    }
}

# Deploy log alerts
function Deploy-LogAlert {
    param(
        [string]$TemplatePath,
        [string]$AlertName,
        [string]$Description,
        [string]$WorkspaceId,
        [int]$Severity = 2,
        [string]$TargetResourceGroup,
        [string]$ActionGroupId = ""
    )
    
    if ([string]::IsNullOrEmpty($WorkspaceId)) {
        Write-Warning-Log "Skipping log alert '$AlertName' - Log Analytics workspace not specified"
        return $true
    }
    
    Write-Log "Deploying log alert: $AlertName"
    
    if ($WhatIf) {
        Write-Host "WHAT-IF: Would deploy log alert '$AlertName' using template '$TemplatePath'" -ForegroundColor Cyan
        return $true
    }
    
    az deployment group create `
        --resource-group $TargetResourceGroup `
        --template-file $TemplatePath `
        --parameters `
            alertName="$AlertName" `
            alertDescription="$Description" `
            workspaceId="$WorkspaceId" `
            alertSeverity="$Severity" `
        --output none 2>$null
        
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Deployed: $AlertName"
        
        # Add action group to the alert if provided
        if (-not [string]::IsNullOrWhiteSpace($ActionGroupId)) {
            Write-Log "Adding action group to log alert: $AlertName"
            az monitor log-analytics alert update `
                --name "$AlertName" `
                --resource-group $TargetResourceGroup `
                --add-action $ActionGroupId `
                --output none 2>$null
                
            if ($LASTEXITCODE -eq 0) {
                Write-Success "Action group added to: $AlertName"
            } else {
                Write-Warning-Log "Failed to add action group to: $AlertName"
            }
        }
        
        return $true
    } else {
        Write-Error-Log "Failed to deploy: $AlertName"
        return $false
    }
}

# Deploy activity log alerts
function Deploy-ActivityLogAlert {
    param(
        [string]$TemplatePath,
        [string]$AlertName,
        [string]$Description,
        [string]$TargetResourceGroup,
        [string]$ActionGroupId = ""
    )
    
    Write-Log "Deploying activity log alert: $AlertName"
    
    if ($WhatIf) {
        Write-Host "WHAT-IF: Would deploy activity log alert '$AlertName' using template '$TemplatePath'" -ForegroundColor Cyan
        return $true
    }
    
    az deployment group create `
        --resource-group $TargetResourceGroup `
        --template-file $TemplatePath `
        --parameters `
            alertRuleName="$AlertName" `
            alertRuleDescription="$Description" `
            actionGroupResourceId="$ActionGroupId" `
        --output none 2>$null
        
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Deployed: $AlertName"
        return $true
    } else {
        Write-Error-Log "Failed to deploy: $AlertName"
        return $false
    }
}

# Get vWAN resources across subscriptions
function Get-VwanResources {
    param([array]$SubscriptionList)
    
    # Test Azure CLI connectivity first
    if (!(Test-AzureCliConnectivity)) {
        Write-Error-Log "Azure CLI connectivity test failed. Cannot proceed with resource discovery."
        return @{
            VirtualHubs = @()
            VpnGateways = @()
            ErGateways = @()
            Firewalls = @()
        }
    }
    
    $script:AllResources = @{
        VirtualHubs = @()
        VpnGateways = @()
        ErGateways = @()
        Firewalls = @()
    }
    
    foreach ($subscription in $SubscriptionList) {
        Write-Log "Discovering vWAN resources in subscription '$($subscription.name)' ($($subscription.id))..."
        
        # Set subscription context and test connectivity
        try {
            Write-Progress -Activity "Discovering vWAN Resources" -Status "Setting subscription context..." -PercentComplete 10
            az account set --subscription $subscription.id
            
            # Quick connectivity test
            $testResult = az account show --query "id" --output tsv 2>$null
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($testResult)) {
                Write-Warning-Log "Failed to set subscription context or verify connectivity. Skipping subscription."
                continue
            }
            Write-Log "  Subscription context set successfully"
        }
        catch {
            Write-Warning-Log "Failed to set subscription context: $($_.Exception.Message). Skipping subscription."
            continue
        }
        
        try {
            # Get Virtual Hubs
            Write-Log "  Discovering Virtual Hubs..."
            try {
                Write-Progress -Activity "Discovering vWAN Resources" -Status "Scanning Virtual Hubs in $($subscription.name)..." -PercentComplete 25
                
                # Try direct command with better error handling
                $vhubsJson = $null
                $startTime = Get-Date
                
                try {
                    # Use Invoke-Expression to better handle potential hanging
                    $command = "az network vhub list --subscription '$($subscription.id)' --query `"[].{id:id, resourceGroup:resourceGroup, location:location, name:name}`" --output json"
                    if ($Debug) {
                        Write-Host "[DEBUG] Running command: $command" -ForegroundColor Magenta
                    }
                    $vhubsJson = Invoke-Expression $command 2>$null
                    $duration = (Get-Date) - $startTime
                    
                    if ($Debug) {
                        Write-Host "[DEBUG] Command completed in $($duration.TotalSeconds.ToString('F1'))s" -ForegroundColor Magenta
                        Write-Host "[DEBUG] Raw JSON output length: $($vhubsJson.Length) characters" -ForegroundColor Magenta
                        if (![string]::IsNullOrEmpty($vhubsJson)) {
                            Write-Host "[DEBUG] First 200 chars of response: $($vhubsJson.Substring(0, [Math]::Min(200, $vhubsJson.Length)))" -ForegroundColor Magenta
                        }
                    }
                    
                    if ($duration.TotalSeconds -gt 20) {
                        Write-Warning-Log "    Virtual Hub discovery took $($duration.TotalSeconds.ToString('F1'))s (unexpectedly slow)"
                    }
                }
                catch {
                    Write-Warning-Log "    Azure CLI command failed: $($_.Exception.Message)"
                }
                
                if (![string]::IsNullOrEmpty($vhubsJson) -and $vhubsJson.Trim() -ne "[]" -and $vhubsJson.Trim() -ne "null") {
                    try {
                        $vhubs = $vhubsJson | ConvertFrom-Json
                        if ($vhubs -and $vhubs.Count -gt 0) {
                            $script:AllResources.VirtualHubs += $vhubs
                            Write-Log "    Found $($vhubs.Count) Virtual Hub(s)" -ForegroundColor Green
                        } else {
                            Write-Warning-Log "    No Virtual Hubs found (empty result)"
                        }
                    }
                    catch {
                        Write-Warning-Log "    Failed to parse Virtual Hub JSON response: $($_.Exception.Message)"
                    }
                } else {
                    Write-Warning-Log "    No Virtual Hubs found (no data returned)"
                    
                    # Try fallback method using simpler query
                    Write-Log "    Trying fallback discovery method..."
                    try {
                        $fallbackJson = az network vhub list --subscription $subscription.id --output json 2>$null
                        if (![string]::IsNullOrEmpty($fallbackJson) -and $fallbackJson.Trim() -ne "[]") {
                            $fallbackHubs = $fallbackJson | ConvertFrom-Json
                            if ($fallbackHubs -and $fallbackHubs.Count -gt 0) {
                                # Convert to expected format
                                $convertedHubs = $fallbackHubs | ForEach-Object {
                                    @{
                                        id = $_.id
                                        resourceGroup = $_.resourceGroup
                                        location = $_.location
                                        name = $_.name
                                    }
                                }
                                $script:AllResources.VirtualHubs += $convertedHubs
                                Write-Log "    Fallback method found $($convertedHubs.Count) Virtual Hub(s)" -ForegroundColor Green
                            }
                        }
                    }
                    catch {
                        Write-Warning-Log "    Fallback discovery also failed: $($_.Exception.Message)"
                    }
                }
            }
            catch {
                Write-Warning-Log "    Failed to discover Virtual Hubs: $($_.Exception.Message)"
            }
            
            # Get VPN Gateways
            Write-Log "  Discovering VPN Gateways..."
            try {
                $vpnGatewaysJson = az network vpn-gateway list --subscription $subscription.id --query "[].{id:id, resourceGroup:resourceGroup, location:location, name:name}" --output json 2>$null
                if ($LASTEXITCODE -eq 0 -and ![string]::IsNullOrEmpty($vpnGatewaysJson)) {
                    $vpnGateways = $vpnGatewaysJson | ConvertFrom-Json
                    if ($vpnGateways) {
                        $script:AllResources.VpnGateways += $vpnGateways
                        Write-Log "    Found $($vpnGateways.Count) VPN Gateway(s)"
                    }
                } else {
                    Write-Warning-Log "    No VPN Gateways found or command failed"
                }
            }
            catch {
                Write-Warning-Log "    Failed to list VPN Gateways: $($_.Exception.Message)"
            }
            
            # Get ExpressRoute Gateways
            Write-Log "  Discovering ExpressRoute Gateways..."
            try {
                $erGatewaysJson = az network express-route gateway list --subscription $subscription.id --query "[].{id:id, resourceGroup:resourceGroup, location:location, name:name}" --output json 2>$null
                if ($LASTEXITCODE -eq 0 -and ![string]::IsNullOrEmpty($erGatewaysJson)) {
                    $erGateways = $erGatewaysJson | ConvertFrom-Json
                    if ($erGateways) {
                        $script:AllResources.ErGateways += $erGateways
                        Write-Log "    Found $($erGateways.Count) ExpressRoute Gateway(s)"
                    }
                } else {
                    Write-Warning-Log "    No ExpressRoute Gateways found or command failed"
                }
            }
            catch {
                Write-Warning-Log "    Failed to list ExpressRoute Gateways: $($_.Exception.Message)"
            }
            
            # Get Azure Firewalls (vWAN integrated)
            Write-Log "  Discovering Azure Firewalls..."
            try {
                $firewallsJson = az network firewall list --subscription $subscription.id --query "[?virtualHub].{id:id, resourceGroup:resourceGroup, location:location, name:name, virtualHub:virtualHub}" --output json 2>$null
                if ($LASTEXITCODE -eq 0 -and ![string]::IsNullOrEmpty($firewallsJson)) {
                    $firewalls = $firewallsJson | ConvertFrom-Json
                    if ($firewalls) {
                        $script:AllResources.Firewalls += $firewalls
                        Write-Log "    Found $($firewalls.Count) Azure Firewall(s)"
                    }
                } else {
                    Write-Warning-Log "    No Azure Firewalls found or command failed"
                }
            }
            catch {
                Write-Warning-Log "    Failed to list Azure Firewalls: $($_.Exception.Message)"
            }
            
        }
        catch {
            Write-Warning-Log "Failed to discover resources in subscription '$($subscription.name)': $_"
        }
    }
    
    # Count and display resources
    $hubCount = $script:AllResources.VirtualHubs.Count
    $vpnCount = $script:AllResources.VpnGateways.Count
    $erCount = $script:AllResources.ErGateways.Count
    $fwCount = $script:AllResources.Firewalls.Count
    $totalCount = $hubCount + $vpnCount + $erCount + $fwCount
    
    Write-Log "Resource Discovery Summary:"
    Write-Host "  Virtual Hubs: $hubCount" -ForegroundColor $(if ($hubCount -gt 0) { "Green" } else { "Gray" })
    Write-Host "  VPN Gateways: $vpnCount" -ForegroundColor $(if ($vpnCount -gt 0) { "Green" } else { "Gray" })
    Write-Host "  ER Gateways: $erCount" -ForegroundColor $(if ($erCount -gt 0) { "Green" } else { "Gray" })
    Write-Host "  Firewalls: $fwCount" -ForegroundColor $(if ($fwCount -gt 0) { "Green" } else { "Gray" })
    Write-Host "  Total Resources: $totalCount" -ForegroundColor $(if ($totalCount -gt 0) { "Cyan" } else { "Red" })
    
    if ($totalCount -eq 0) {
        Write-Warning-Log "No vWAN resources found in the selected subscriptions. Please verify:"
        Write-Host "  • Subscriptions contain Virtual WAN resources" -ForegroundColor Gray
        Write-Host "  • You have appropriate read permissions" -ForegroundColor Gray
        Write-Host "  • Resources are properly deployed and not in a transitional state" -ForegroundColor Gray
        
        $continue = Read-Host "`nContinue anyway? This will create an empty deployment (y/n)"
        if ($continue.ToLower() -ne 'y' -and $continue.ToLower() -ne 'yes') {
            Write-Log "Deployment cancelled by user."
            exit 0
        }
    }
    
    return $script:AllResources
}

# Deploy Virtual Hub alerts
function Deploy-VirtualHubAlerts {
    param([array]$Resources, [string]$TargetResourceGroup, [hashtable]$HubScaleUnits = @{})
    
    if (-not $Resources.VirtualHubs -or $Resources.VirtualHubs.Count -eq 0) {
        Write-Warning-Log "No Virtual Hubs found, skipping Virtual Hub alerts"
        return @{ Success = 0; Failed = 0; Skipped = 1 }
    }
    
    Write-Log "Deploying Virtual Hub alerts for $($Resources.VirtualHubs.Count) hubs..."
    
    $results = @{ Success = 0; Failed = 0; Skipped = 0 }
    
    foreach ($hub in $Resources.VirtualHubs) {
        $hubName = $hub.name
        $hubId = $hub.id
        $regionNoSpaces = $hub.location -replace ' ',''
        
        # Determine deployment region and resource group
        if ($CentralizedMonitoring) {
            $deploymentRegion = $Location
            $deploymentResourceGroup = $TargetResourceGroup
        } else {
            $deploymentRegion = $hub.location
            $deploymentResourceGroup = "$TargetResourceGroup-$regionNoSpaces"
        }
        
        Write-Host "  Processing Virtual Hub: $hubName (Region: $($hub.location))" -ForegroundColor Cyan
        if (-not $CentralizedMonitoring) {
            Write-Host "    Alerts will be deployed to: $deploymentResourceGroup in $deploymentRegion" -ForegroundColor Gray
        }
        
        # Create regional resource group if needed
        if (-not $CentralizedMonitoring) {
            New-ResourceGroupIfNotExists -ResourceGroup $deploymentResourceGroup -Region $deploymentRegion -WhatIfMode $WhatIf
        }
        
        # Get action group for this hub's subscription and region
        $actionGroupId = Get-ActionGroupForResource -ResourceId $hubId -DeploymentRegion $deploymentRegion
        
        # BGP Peer Status Alert
        $success1 = Deploy-MetricAlert `
            -TemplatePath "services/Network/virtualWans/templates/bicep/VirtualHub-BGPPeerStatus.bicep" `
            -AlertName "vhub-bgp-peer-status-$hubName" `
            -Description "Virtual Hub BGP Peer Status Alert for $hubName" `
            -TargetResourceId $hubId `
            -TargetResourceType "Microsoft.Network/virtualHubs" `
            -TargetRegion $regionNoSpaces `
            -Severity 1 `
            -TargetResourceGroup $deploymentResourceGroup `
            -ActionGroupId $actionGroupId
            
        # Data Processed Alert - get scale units for this hub
        $scaleUnits = if ($HubScaleUnits.ContainsKey($hubId)) { $HubScaleUnits[$hubId] } else { 2 }
        $success2 = Deploy-VirtualHubDataProcessedAlert `
            -AlertName "vhub-data-processed-$hubName" `
            -Description "Virtual Hub Data Processed Alert for $hubName" `
            -VirtualHubResourceId $hubId `
            -TargetRegion $regionNoSpaces `
            -RoutingInfrastructureUnits $scaleUnits `
            -Severity 3 `
            -TargetResourceGroup $deploymentResourceGroup `
            -ActionGroupId $actionGroupId
        
        if ($success1) { $results.Success++ } else { $results.Failed++ }
        if ($success2) { $results.Success++ } else { $results.Failed++ }
    }
    
    return $results
}

# Deploy VPN Gateway alerts
function Deploy-VpnGatewayAlerts {
    param([array]$Resources, [string]$TargetResourceGroup, [string]$LogWorkspace)
    
    if (-not $Resources.VpnGateways -or $Resources.VpnGateways.Count -eq 0) {
        Write-Warning-Log "No VPN Gateways found, skipping VPN Gateway alerts"
        return @{ Success = 0; Failed = 0; Skipped = 1 }
    }
    
    Write-Log "Deploying VPN Gateway alerts for $($Resources.VpnGateways.Count) gateways..."
    
    $results = @{ Success = 0; Failed = 0; Skipped = 0 }
    
    foreach ($gateway in $Resources.VpnGateways) {
        $gatewayName = $gateway.name
        $gatewayId = $gateway.id
        $regionNoSpaces = $gateway.location -replace ' ',''
        
        # Determine deployment region and resource group
        if ($CentralizedMonitoring) {
            $deploymentRegion = $Location
            $deploymentResourceGroup = $TargetResourceGroup
        } else {
            $deploymentRegion = $gateway.location
            $deploymentResourceGroup = "$TargetResourceGroup-$regionNoSpaces"
        }
        
        Write-Host "  Processing VPN Gateway: $gatewayName (Region: $($gateway.location))" -ForegroundColor Cyan
        if (-not $CentralizedMonitoring) {
            Write-Host "    Alerts will be deployed to: $deploymentResourceGroup in $deploymentRegion" -ForegroundColor Gray
        }
        
        # Create regional resource group if needed
        if (-not $CentralizedMonitoring) {
            New-ResourceGroupIfNotExists -ResourceGroup $deploymentResourceGroup -Region $deploymentRegion -WhatIfMode $WhatIf
        }
        
        # Get action group for this gateway's subscription and region
        $actionGroupId = Get-ActionGroupForResource -ResourceId $gatewayId -DeploymentRegion $deploymentRegion
        
        # AMBA Compliant Alerts
        
        # 1. Tunnel Average Bandwidth Alert (AMBA - High Priority)
        $success1 = Deploy-MetricAlert `
            -TemplatePath "services/Network/vpnGateways/templates/bicep/VpnGateway-TunnelAverageBandwidth.bicep" `
            -AlertName "vpn-tunnel-bandwidth-$gatewayName" `
            -Description "VPN Gateway Tunnel Average Bandwidth Alert for $gatewayName (AMBA Compliant)" `
            -TargetResourceId $gatewayId `
            -TargetResourceType "Microsoft.Network/vpnGateways" `
            -TargetRegion $regionNoSpaces `
            -Severity 0 `
            -TargetResourceGroup $deploymentResourceGroup `
            -ActionGroupId $actionGroupId
            
        # 2. Activity Log Delete Alert (AMBA - Security/Governance)
        $success2 = Deploy-ActivityLogAlert `
            -TemplatePath "services/Network/vpnGateways/templates/bicep/VpnGateway-ActivityLogDelete.bicep" `
            -AlertName "vpn-gateway-delete-$gatewayName" `
            -Description "VPN Gateway Delete Activity Log Alert for $gatewayName (AMBA Compliant)" `
            -TargetResourceGroup $deploymentResourceGroup `
            -ActionGroupId $actionGroupId
            
        # 3. Tunnel Egress Bytes Alert (AMBA - Traffic Monitoring)
        $success3 = Deploy-MetricAlert `
            -TemplatePath "services/Network/vpnGateways/templates/bicep/VpnGateway-TunnelEgressBytes.bicep" `
            -AlertName "vpn-tunnel-egress-bytes-$gatewayName" `
            -Description "VPN Gateway Tunnel Egress Bytes Alert for $gatewayName (AMBA Compliant)" `
            -TargetResourceId $gatewayId `
            -TargetResourceType "Microsoft.Network/vpnGateways" `
            -TargetRegion $regionNoSpaces `
            -Severity 2 `
            -TargetResourceGroup $deploymentResourceGroup `
            -ActionGroupId $actionGroupId
        
        # Additional vWAN-Specific Alerts
        
        # 4. Tunnel Packet Drop Alert
        $success4 = Deploy-MetricAlert `
            -TemplatePath "services/Network/vpnGateways/templates/bicep/VpnGateway-TunnelPacketDropCount.bicep" `
            -AlertName "vpn-tunnel-packet-drop-$gatewayName" `
            -Description "VPN Gateway Tunnel Packet Drop Alert for $gatewayName" `
            -TargetResourceId $gatewayId `
            -TargetResourceType "Microsoft.Network/vpnGateways" `
            -TargetRegion $regionNoSpaces `
            -Severity 2 `
            -TargetResourceGroup $deploymentResourceGroup `
            -ActionGroupId $actionGroupId
            
        # 5. BGP Peer Status Alert
        $success5 = Deploy-MetricAlert `
            -TemplatePath "services/Network/vpnGateways/templates/bicep/VpnGateway-BGPPeerStatus.bicep" `
            -AlertName "vpn-bgp-peer-status-$gatewayName" `
            -Description "VPN Gateway BGP Peer Status Alert for $gatewayName" `
            -TargetResourceId $gatewayId `
            -TargetResourceType "Microsoft.Network/vpnGateways" `
            -TargetRegion $regionNoSpaces `
            -Severity 1 `
            -TargetResourceGroup $deploymentResourceGroup `
            -ActionGroupId $actionGroupId
            
        # 6. Tunnel Disconnect Log Alert (requires Log Analytics workspace)
        $success6 = Deploy-LogAlert `
            -TemplatePath "services/Network/vpnGateways/templates/bicep/VpnGateway-TunnelDisconnectLog.bicep" `
            -AlertName "vpn-tunnel-disconnect-$gatewayName" `
            -Description "VPN Gateway Tunnel Disconnect Log Alert for $gatewayName" `
            -WorkspaceId $LogWorkspace `
            -Severity 2 `
            -TargetResourceGroup $deploymentResourceGroup `
            -ActionGroupId $actionGroupId
        
        if ($success1) { $results.Success++ } else { $results.Failed++ }
        if ($success2) { $results.Success++ } else { $results.Failed++ }
        if ($success3) { $results.Success++ } else { $results.Failed++ }
        if ($success4) { $results.Success++ } else { $results.Failed++ }
        if ($success5) { $results.Success++ } else { $results.Failed++ }
        if ($success6) { $results.Success++ } else { $results.Failed++ }
        if ($success3) { $results.Success++ } else { $results.Failed++ }
    }
    
    return $results
}

# Deploy ExpressRoute Gateway alerts
function Deploy-ExpressRouteGatewayAlerts {
    param([array]$Resources, [string]$TargetResourceGroup)
    
    if (-not $Resources.ErGateways -or $Resources.ErGateways.Count -eq 0) {
        Write-Warning-Log "No ExpressRoute Gateways found, skipping ExpressRoute Gateway alerts"
        return @{ Success = 0; Failed = 0; Skipped = 1 }
    }
    
    Write-Log "Deploying ExpressRoute Gateway alerts for $($Resources.ErGateways.Count) gateways..."
    
    $results = @{ Success = 0; Failed = 0; Skipped = 0 }
    
    foreach ($gateway in $Resources.ErGateways) {
        $gatewayName = $gateway.name
        $gatewayId = $gateway.id
        $regionNoSpaces = $gateway.location -replace ' ',''
        
        # Determine deployment region and resource group
        if ($CentralizedMonitoring) {
            $deploymentRegion = $Location
            $deploymentResourceGroup = $TargetResourceGroup
        } else {
            $deploymentRegion = $gateway.location
            $deploymentResourceGroup = "$TargetResourceGroup-$regionNoSpaces"
        }
        
        Write-Host "  Processing ExpressRoute Gateway: $gatewayName (Region: $($gateway.location))" -ForegroundColor Cyan
        if (-not $CentralizedMonitoring) {
            Write-Host "    Alerts will be deployed to: $deploymentResourceGroup in $deploymentRegion" -ForegroundColor Gray
        }
        
        # Create regional resource group if needed
        if (-not $CentralizedMonitoring) {
            New-ResourceGroupIfNotExists -ResourceGroup $deploymentResourceGroup -Region $deploymentRegion -WhatIfMode $WhatIf
        }
        
        # Get action group for this gateway's subscription and region
        $actionGroupId = Get-ActionGroupForResource -ResourceId $gatewayId -DeploymentRegion $deploymentRegion
        
        # CPU Utilization Alert
        $success1 = Deploy-MetricAlert `
            -TemplatePath "services/Network/expressRouteGateways/templates/bicep/ExpressRouteGateway-CPUUtilization.bicep" `
            -AlertName "er-cpu-utilization-$gatewayName" `
            -Description "ExpressRoute Gateway CPU Utilization Alert for $gatewayName" `
            -TargetResourceId $gatewayId `
            -TargetResourceType "Microsoft.Network/expressRouteGateways" `
            -TargetRegion $regionNoSpaces `
            -Severity 2 `
            -TargetResourceGroup $deploymentResourceGroup `
            -ActionGroupId $actionGroupId
            
        # Connection Bits In Per Second Alert
        $success2 = Deploy-MetricAlert `
            -TemplatePath "services/Network/expressRouteGateways/templates/bicep/ExpressRouteGateway-ConnectionBitsInPerSecond.bicep" `
            -AlertName "er-connection-bits-in-$gatewayName" `
            -Description "ExpressRoute Gateway Connection Bits In Per Second Alert for $gatewayName" `
            -TargetResourceId $gatewayId `
            -TargetResourceType "Microsoft.Network/expressRouteGateways" `
            -TargetRegion $regionNoSpaces `
            -Severity 0 `
            -TargetResourceGroup $deploymentResourceGroup `
            -ActionGroupId $actionGroupId
            
        # Connection Bits Out Per Second Alert
        $success3 = Deploy-MetricAlert `
            -TemplatePath "services/Network/expressRouteGateways/templates/bicep/ExpressRouteGateway-ConnectionBitsOutPerSecond.bicep" `
            -AlertName "er-connection-bits-out-$gatewayName" `
            -Description "ExpressRoute Gateway Connection Bits Out Per Second Alert for $gatewayName" `
            -TargetResourceId $gatewayId `
            -TargetResourceType "Microsoft.Network/expressRouteGateways" `
            -TargetRegion $regionNoSpaces `
            -Severity 0 `
            -TargetResourceGroup $deploymentResourceGroup `
            -ActionGroupId $actionGroupId
        
        if ($success1) { $results.Success++ } else { $results.Failed++ }
        if ($success2) { $results.Success++ } else { $results.Failed++ }
        if ($success3) { $results.Success++ } else { $results.Failed++ }
    }
    
    return $results
}

# Deploy Azure Firewall alerts
function Deploy-AzureFirewallAlerts {
    param([array]$Resources, [string]$TargetResourceGroup)
    
    if (-not $Resources.Firewalls -or $Resources.Firewalls.Count -eq 0) {
        Write-Warning-Log "No Azure Firewalls found, skipping Azure Firewall alerts"
        return @{ Success = 0; Failed = 0; Skipped = 1 }
    }
    
    Write-Log "Deploying Azure Firewall alerts for $($Resources.Firewalls.Count) firewalls..."
    
    $results = @{ Success = 0; Failed = 0; Skipped = 0 }
    
    foreach ($firewall in $Resources.Firewalls) {
        $firewallName = $firewall.name
        $firewallId = $firewall.id
        $regionNoSpaces = $firewall.location -replace ' ',''
        
        # Determine deployment region and resource group
        if ($CentralizedMonitoring) {
            $deploymentRegion = $Location
            $deploymentResourceGroup = $TargetResourceGroup
        } else {
            $deploymentRegion = $firewall.location
            $deploymentResourceGroup = "$TargetResourceGroup-$regionNoSpaces"
        }
        
        Write-Host "  Processing Azure Firewall: $firewallName (Region: $($firewall.location))" -ForegroundColor Cyan
        if (-not $CentralizedMonitoring) {
            Write-Host "    Alerts will be deployed to: $deploymentResourceGroup in $deploymentRegion" -ForegroundColor Gray
        }
        
        # Create regional resource group if needed
        if (-not $CentralizedMonitoring) {
            New-ResourceGroupIfNotExists -ResourceGroup $deploymentResourceGroup -Region $deploymentRegion -WhatIfMode $WhatIf
        }
        
        # Get action group for this firewall's subscription and region
        $actionGroupId = Get-ActionGroupForResource -ResourceId $firewallId -DeploymentRegion $deploymentRegion
        
        # SNAT Port Utilization Alert
        $success = Deploy-MetricAlert `
            -TemplatePath "services/Network/azureFirewalls/templates/bicep/AzureFirewall-SNATPortUtilization.bicep" `
            -AlertName "fw-snat-port-utilization-$firewallName" `
            -Description "Azure Firewall SNAT Port Utilization Alert for $firewallName" `
            -TargetResourceId $firewallId `
            -TargetResourceType "Microsoft.Network/azureFirewalls" `
            -TargetRegion $regionNoSpaces `
            -Severity 2 `
            -TargetResourceGroup $deploymentResourceGroup `
            -ActionGroupId $actionGroupId
        
        if ($success) { $results.Success++ } else { $results.Failed++ }
    }
    
    return $results
}

# Run interactive mode
function Start-InteractiveMode {
    param([string]$DefaultResourceGroup = "rg-vwan-monitoring")
    
    Show-WelcomeBanner
    
    # Get subscriptions
    $availableSubscriptions = Get-UserSubscriptions
    if ($availableSubscriptions.Count -eq 0) {
        Write-Error-Log "No subscriptions available. Exiting."
        exit 1
    }
    
    # Select subscriptions
    $selectedSubscriptions = Select-Subscriptions -Subscriptions $availableSubscriptions
    
    # Select alert types
    $selectedAlertTypes = Select-AlertTypes
    
    # Get resource group
    $targetResourceGroup = Get-ResourceGroupInput -DefaultRG $DefaultResourceGroup
    
    # Select deployment strategy
    Write-Host "`n[STRATEGY] Deployment Strategy" -ForegroundColor Cyan
    Write-Host ("=" * 50) -ForegroundColor Cyan
    Write-Host "Choose how to deploy your monitoring alerts:" -ForegroundColor Yellow
    Write-Host "`n[1] Regional Deployment (RECOMMENDED)" -ForegroundColor White
    Write-Host "    - Alerts deployed to same regions as monitored resources" -ForegroundColor Gray
    Write-Host "    - Better performance and compliance with data residency" -ForegroundColor Gray
    Write-Host "    - Resource groups created per region (e.g., rg-vwan-monitoring-eastus)" -ForegroundColor Gray
    Write-Host "`n[2] Centralized Deployment (LEGACY)" -ForegroundColor White
    Write-Host "    - All alerts deployed to the specified location ($Location)" -ForegroundColor Gray
    Write-Host "    - Single resource group for all alerts" -ForegroundColor Gray
    Write-Host "    - May have cross-region latency for alert processing" -ForegroundColor Gray
    
    do {
        $strategyChoice = Read-Host "`nDeployment strategy (1-2)"
        if ($strategyChoice -eq "1") {
            $script:CentralizedMonitoring = $false
            Write-Host "[OK] Regional deployment selected" -ForegroundColor Green
            break
        } elseif ($strategyChoice -eq "2") {
            $script:CentralizedMonitoring = $true
            Write-Host "[OK] Centralized deployment selected" -ForegroundColor Green
            break
        } else {
            Write-Warning-Log "Invalid selection. Please choose 1 or 2."
        }
    } while ($true)
    
    # Get Log Analytics workspace
    $logWorkspace = Get-LogAnalyticsInput
    
    # Configure Action Group
    $actionGroupConfig = $null
    if ($selectedSubscriptions.Count -eq 1) {
        $actionGroupConfig = Get-ActionGroupConfiguration -SubscriptionId $selectedSubscriptions[0].id
    } else {
        Write-Host "`n[EMAIL] Action Group Configuration" -ForegroundColor Cyan
        Write-Host ("=" * 50) -ForegroundColor Cyan
        Write-Host "Multi-subscription deployment detected." -ForegroundColor Yellow
        Write-Host "Action groups will be created per subscription or you can skip notifications." -ForegroundColor White
        
        Write-Host "`nChoose an option:" -ForegroundColor Yellow
        Write-Host "[1] Configure action groups for each subscription" -ForegroundColor White
        Write-Host "[2] Skip action group configuration (no notifications)" -ForegroundColor Gray
        
        do {
            $choice = Read-Host "Selection (1-2)"
            if ($choice -eq "1") {
                $actionGroupConfig = "per-subscription"
                break
            } elseif ($choice -eq "2") {
                $actionGroupConfig = $null
                Write-Warning-Log "Skipping action group configuration for all subscriptions."
                break
            } else {
                Write-Warning-Log "Invalid selection. Please choose 1 or 2."
            }
        } while ($true)
    }
    
    # Confirm deployment
    $confirmed = Confirm-Deployment -Subscriptions $selectedSubscriptions -AlertTypes $selectedAlertTypes -ResourceGroup $targetResourceGroup -LogWorkspace $logWorkspace -ActionGroupConfig $actionGroupConfig -WhatIfMode $WhatIf
    
    if (-not $confirmed) {
        Write-Log "Deployment cancelled by user."
        exit 0
    }
    
    # Execute deployment
    Start-Deployment -Subscriptions $selectedSubscriptions -AlertTypes $selectedAlertTypes -TargetResourceGroup $targetResourceGroup -LogWorkspace $logWorkspace -ActionGroupConfig $actionGroupConfig
}

# Execute deployment with given parameters
function Start-Deployment {
    param(
        [array]$Subscriptions,
        [array]$AlertTypes,
        [string]$TargetResourceGroup,
        [string]$LogWorkspace,
        [object]$ActionGroupConfig = $null
    )
    
    Write-Log "Starting Azure Monitor Baseline Alerts for Azure Virtual WAN"
    
    # Check prerequisites
    Test-Prerequisites
    
    # Store original subscription for restoration later
    $originalSubscription = az account show --query "id" -o tsv
    
    try {
        # Create resource group in the first subscription (or current if not specified)
        if (-not $WhatIf) {
            if ($Subscriptions.Count -gt 0) {
                az account set --subscription $Subscriptions[0].id
            }
            New-ResourceGroupIfNotExists -ResourceGroup $TargetResourceGroup
        }
        
        # Create or configure action groups
        $actionGroupIds = @{}
        if ($ActionGroupConfig -and $ActionGroupConfig -ne "skip") {
            if ($ActionGroupConfig -eq "per-subscription") {
                # Create action group for each subscription
                foreach ($sub in $Subscriptions) {
                    Write-Log "`n--- Configuring Action Group for Subscription: $($sub.name) ---"
                    az account set --subscription $sub.id
                    $subActionGroupConfig = Get-ActionGroupConfiguration -SubscriptionId $sub.id
                    if ($subActionGroupConfig) {
                        if ($CentralizedMonitoring) {
                            # Single action group in specified location
                            $agId = New-ActionGroup -ActionGroupConfig $subActionGroupConfig -Region $Location -WhatIfMode $WhatIf
                            if ($agId) {
                                $actionGroupIds[$sub.id] = $agId
                            }
                        } else {
                            # Create action groups per region for each subscription
                            $regions = Get-UniqueRegionsForSubscription -SubscriptionId $sub.id -Resources (Get-VwanResources -SubscriptionList @($sub))
                            foreach ($region in $regions) {
                                $regionNoSpaces = $region -replace ' ',''
                                $regionalActionGroupConfig = @{
                                    Name = "$($subActionGroupConfig.Name)-$regionNoSpaces"
                                    ResourceGroup = "$($subActionGroupConfig.ResourceGroup)-$regionNoSpaces"
                                    SubscriptionId = $subActionGroupConfig.SubscriptionId
                                    IsNew = $subActionGroupConfig.IsNew
                                    Notifications = $subActionGroupConfig.Notifications
                                }
                                
                                $agId = New-ActionGroup -ActionGroupConfig $regionalActionGroupConfig -Region $region -WhatIfMode $WhatIf
                                if ($agId) {
                                    $actionGroupIds["$($sub.id)-$region"] = $agId
                                }
                            }
                        }
                    }
                }
                # Set back to first subscription for deployments
                if ($Subscriptions.Count -gt 0) {
                    az account set --subscription $Subscriptions[0].id
                }
            } elseif ($ActionGroupConfig.GetType().Name -eq "Hashtable") {
                # Single action group configuration
                $deployRegion = if ($CentralizedMonitoring) { $Location } else { $ActionGroupConfig.Region }
                $agId = New-ActionGroup -ActionGroupConfig $ActionGroupConfig -Region $deployRegion -WhatIfMode $WhatIf
                if ($agId) {
                    $actionGroupIds[$ActionGroupConfig.SubscriptionId] = $agId
                }
            }
        }
        
        # Store action group IDs for template deployment
        $script:ActionGroupIds = $actionGroupIds
        
        # Skip resource discovery in WhatIf mode for performance
        if ($WhatIf) {
            Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
            Write-Host "WHAT-IF MODE: DEPLOYMENT PREVIEW" -ForegroundColor Cyan -BackgroundColor Black
            Write-Host ("=" * 80) -ForegroundColor Cyan
            
            Write-Host "`n📋 Configuration Summary:" -ForegroundColor Yellow
            Write-Host "  • Subscriptions: $($Subscriptions.Count) subscription(s)" -ForegroundColor White
            Write-Host "  • Alert Types: $($AlertTypes -join ', ')" -ForegroundColor White  
            Write-Host "  • Target Resource Group: $TargetResourceGroup" -ForegroundColor White
            Write-Host "  • Centralized Monitoring: $CentralizedMonitoring" -ForegroundColor White
            
            Write-Host "`n🔍 What Would Happen:" -ForegroundColor Yellow
            Write-Host "  ✅ Scan $($Subscriptions.Count) subscription(s) for vWAN resources" -ForegroundColor Green
            Write-Host "  ✅ Deploy alert templates only for discovered resources" -ForegroundColor Green
            Write-Host "  ✅ Create/configure action groups for notifications" -ForegroundColor Green
            Write-Host "  ✅ Deploy alerts to appropriate regions/resource groups" -ForegroundColor Green
            
            Write-Host "`n📊 Alert Templates Available for Deployment:" -ForegroundColor Yellow
            Write-Host "  (Templates will only be deployed if matching resources are found)" -ForegroundColor Gray
            if ($AlertTypes -contains "All" -or $AlertTypes -contains "VirtualHub") {
                Write-Host "  🏢 Virtual Hub Alerts (2 templates):" -ForegroundColor Cyan
                Write-Host "     • BGP Peer Status monitoring" -ForegroundColor White
                Write-Host "     • Data Processing capacity monitoring" -ForegroundColor White
            }
            if ($AlertTypes -contains "All" -or $AlertTypes -contains "S2SVPN") {
                Write-Host "  🔐 S2S VPN Alerts (6 templates - AMBA compliant):" -ForegroundColor Cyan
                Write-Host "     • Tunnel Average Bandwidth (intelligent scale unit detection)" -ForegroundColor White
                Write-Host "     • Activity Log Delete (security governance)" -ForegroundColor White
                Write-Host "     • Tunnel Egress Bytes (traffic monitoring)" -ForegroundColor White
                Write-Host "     • BGP Peer Status monitoring" -ForegroundColor White
                Write-Host "     • Tunnel Packet Drop monitoring" -ForegroundColor White
                Write-Host "     • Tunnel Disconnect log alerts" -ForegroundColor White
            }
            if ($AlertTypes -contains "All" -or $AlertTypes -contains "ExpressRoute") {
                Write-Host "  ⚡ ExpressRoute Gateway Alerts (3 templates):" -ForegroundColor Cyan
                Write-Host "     • CPU Utilization monitoring" -ForegroundColor White
                Write-Host "     • Connection Bits In (intelligent autoscale detection)" -ForegroundColor White
                Write-Host "     • Connection Bits Out (intelligent autoscale detection)" -ForegroundColor White
            }
            if ($AlertTypes -contains "All" -or $AlertTypes -contains "Firewall") {
                Write-Host "  🔥 Azure Firewall Alerts (1 template):" -ForegroundColor Cyan
                Write-Host "     • SNAT Port Utilization monitoring" -ForegroundColor White
            }
            
            Write-Host "`n⚡ Performance Note:" -ForegroundColor Yellow
            Write-Host "   WhatIf mode shows available templates without scanning for resources." -ForegroundColor Gray
            Write-Host "   Actual deployment will scan for vWAN resources and deploy only matching alerts." -ForegroundColor Gray
            
            Write-Host "`n💡 Important:" -ForegroundColor Yellow
            Write-Host "   If you have no vWAN resources, actual deployment will deploy 0 alerts." -ForegroundColor Gray
            Write-Host "   Templates are only deployed when matching resource types are found." -ForegroundColor Gray
            
            Write-Host "`n🚀 Ready to Deploy?" -ForegroundColor Green
            Write-Host "   Run without -WhatIf flag to execute actual deployment:" -ForegroundColor White
            Write-Host "   .\deploy-alerts.ps1 -Interactive" -ForegroundColor Cyan
            
            Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
            Write-Host "WHAT-IF MODE COMPLETED" -ForegroundColor Cyan -BackgroundColor Black  
            Write-Host ("=" * 80) -ForegroundColor Cyan
            return
        }
        
        # Discover vWAN resources across all subscriptions (only in actual deployment)
        Write-Log "`n🔍 Discovering vWAN resources across subscriptions..."
        $resources = Get-VwanResources -SubscriptionList $Subscriptions
        
        # Get Virtual Hub scale unit configuration if needed
        $hubScaleUnits = @{}
        if (($AlertTypes -contains "All" -or $AlertTypes -contains "VirtualHub") -and $resources.VirtualHubs.Count -gt 0) {
            $hubScaleUnits = Get-VirtualHubScaleUnits -VirtualHubs $resources.VirtualHubs
        }
        
        # Deploy alerts based on selected types
        $overallResults = @{ Success = 0; Failed = 0; Skipped = 0 }
        
        # Set context back to first subscription for deployments
        if ($Subscriptions.Count -gt 0) {
            az account set --subscription $Subscriptions[0].id
        }
        
        if ($AlertTypes -contains "All" -or $AlertTypes -contains "VirtualHub") {
            Write-Log "`n--- Deploying Virtual Hub Alerts ---"
            $result = Deploy-VirtualHubAlerts -Resources $resources -TargetResourceGroup $TargetResourceGroup -HubScaleUnits $hubScaleUnits
            $overallResults.Success += $result.Success
            $overallResults.Failed += $result.Failed
            $overallResults.Skipped += $result.Skipped
        }
        
        if ($AlertTypes -contains "All" -or $AlertTypes -contains "S2SVPN") {
            Write-Log "`n--- Deploying S2S VPN Alerts ---"
            $result = Deploy-VpnGatewayAlerts -Resources $resources -TargetResourceGroup $TargetResourceGroup -LogWorkspace $LogWorkspace
            $overallResults.Success += $result.Success
            $overallResults.Failed += $result.Failed
            $overallResults.Skipped += $result.Skipped
        }
        
        if ($AlertTypes -contains "All" -or $AlertTypes -contains "ExpressRoute") {
            Write-Log "`n--- Deploying ExpressRoute Gateway Alerts ---"
            $result = Deploy-ExpressRouteGatewayAlerts -Resources $resources -TargetResourceGroup $TargetResourceGroup
            $overallResults.Success += $result.Success
            $overallResults.Failed += $result.Failed
            $overallResults.Skipped += $result.Skipped
        }
        
        if ($AlertTypes -contains "All" -or $AlertTypes -contains "Firewall") {
            Write-Log "`n--- Deploying Azure Firewall Alerts ---"
            $result = Deploy-AzureFirewallAlerts -Resources $resources -TargetResourceGroup $TargetResourceGroup
            $overallResults.Success += $result.Success
            $overallResults.Failed += $result.Failed
            $overallResults.Skipped += $result.Skipped
        }
        
        # Display final results
        Write-Host "`n" + ("=" * 80) -ForegroundColor Green
        Write-Host "DEPLOYMENT COMPLETED" -ForegroundColor Green -BackgroundColor Black
        Write-Host ("=" * 80) -ForegroundColor Green
        
        Write-Host "Results Summary:" -ForegroundColor Cyan
        Write-Host "  [OK] Successful deployments: $($overallResults.Success)" -ForegroundColor Green
        Write-Host "  [ERROR] Failed deployments: $($overallResults.Failed)" -ForegroundColor Red
        Write-Host "  ⏭️  Skipped deployments: $($overallResults.Skipped)" -ForegroundColor Yellow
        
        $totalAttempted = $overallResults.Success + $overallResults.Failed
        if ($totalAttempted -gt 0) {
            $successRate = [math]::Round(($overallResults.Success / $totalAttempted) * 100, 1)
            Write-Host "  [DATA] Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 90) { "Green" } elseif ($successRate -ge 75) { "Yellow" } else { "Red" })
        }
        
        # This section only runs for actual deployment (not WhatIf)
        Write-Host "`n🎉 Azure Monitor Baseline Alerts for Azure Virtual WAN deployment completed!" -ForegroundColor Green
        Write-Host "[LIST] Next steps:" -ForegroundColor Yellow
        Write-Host "  • Check the Azure portal to verify alert deployments" -ForegroundColor White
        if ($script:ActionGroupIds -and $script:ActionGroupIds.Count -gt 0) {
            Write-Host "  • Action groups have been configured for notifications" -ForegroundColor Green
        } else {
            Write-Host "  • Configure action groups for notifications (alerts won't send notifications without them)" -ForegroundColor Yellow
        }
        Write-Host "  • Test alert functionality in a controlled manner" -ForegroundColor White
        Write-Host "  • Review and adjust thresholds based on your environment" -ForegroundColor White
    }
    finally {
        # Restore original subscription context
        if ($originalSubscription) {
            az account set --subscription $originalSubscription
        }
    }
}

# Main execution entry point
function Main {
    if ($Interactive) {
        Start-InteractiveMode -DefaultResourceGroup $ResourceGroup
    } else {
        # Non-interactive mode - validate parameters
        if ($SubscriptionIds.Count -eq 0) {
            # Use current subscription if none specified
            $currentSub = az account show --query "{id:id, name:name, tenantId:tenantId}" | ConvertFrom-Json
            if (-not $currentSub) {
                Write-Error-Log "No subscription specified and unable to determine current subscription. Use -Interactive mode or specify -SubscriptionIds."
                exit 1
            }
            $subscriptions = @($currentSub)
        } else {
            # Convert subscription IDs to subscription objects
            $subscriptions = @()
            foreach ($subId in $SubscriptionIds) {
                try {
                    $sub = az account show --subscription $subId --query "{id:id, name:name, tenantId:tenantId}" | ConvertFrom-Json
                    $subscriptions += $sub
                } catch {
                    Write-Error-Log "Invalid subscription ID: $subId"
                    exit 1
                }
            }
        }
        
        if ($AlertTypes.Count -eq 0) {
            $AlertTypes = @("All")
        }
        
        # Handle action group configuration in non-interactive mode
        $actionGroupConfig = $null
        if ($UseExistingActionGroup) {
            # For non-interactive mode with existing action group, use the first subscription
            $actionGroupConfig = Select-ExistingActionGroup -SubscriptionId $subscriptions[0].id
        } elseif (-not [string]::IsNullOrWhiteSpace($ActionGroupName)) {
            # Create new action group configuration
            $notifications = @{}
            if ($EmailAddresses.Count -gt 0) { $notifications.Emails = $EmailAddresses }
            if ($SmsNumbers.Count -gt 0) { $notifications.SMS = $SmsNumbers }
            if ($WebhookUrls.Count -gt 0) { $notifications.Webhooks = $WebhookUrls }
            
            $actionGroupConfig = @{
                Name = $ActionGroupName
                ResourceGroup = if ([string]::IsNullOrWhiteSpace($ActionGroupResourceGroup)) { $ResourceGroup } else { $ActionGroupResourceGroup }
                SubscriptionId = $subscriptions[0].id
                Notifications = $notifications
                IsNew = $true
            }
        }
        
        # Validate Log Analytics workspace if provided
        if (![string]::IsNullOrEmpty($LogAnalyticsWorkspace)) {
            Write-Host "`nValidating Log Analytics workspace..." -ForegroundColor Yellow
            if (-not (Test-LogAnalyticsWorkspace -WorkspaceId $LogAnalyticsWorkspace)) {
                Write-Host "Warning: Workspace validation failed. Proceeding anyway..." -ForegroundColor Yellow
                Write-Host "Ensure you have appropriate permissions to the specified workspace." -ForegroundColor Yellow
            }
        }
        
        Start-Deployment -Subscriptions $subscriptions -AlertTypes $AlertTypes -TargetResourceGroup $ResourceGroup -LogWorkspace $LogAnalyticsWorkspace -ActionGroupConfig $actionGroupConfig
    }
}

# Execute main function
Main
