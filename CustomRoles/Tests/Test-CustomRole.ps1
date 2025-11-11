<#
.SYNOPSIS
    End-to-end test orchestrator for the Restricted Subscription Owner custom role.

.DESCRIPTION
    This script orchestrates the complete testing of the custom RBAC role by:
    1. Setting up a test environment with a service principal
    2. Running all restriction tests
    3. Generating comprehensive reports
    4. Cleaning up test resources

.PARAMETER SubscriptionId
    The Azure subscription ID where tests will run

.PARAMETER CustomRoleName
    The name of the custom role to test (default: "Restricted Subscription Owner")

.PARAMETER TestResourceGroupName
    The name of the resource group for test resources (default: "rg-rbac-test")

.PARAMETER Location
    Azure region (Azure location name) for test resources (default: "eastus"). If omitted or blank, you will be prompted to select from available regions in the current subscription.

.PARAMETER SkipSetup
    Skip the setup phase (use existing test environment)

.PARAMETER SkipCleanup
    Skip the cleanup phase (leave test resources for inspection)

.PARAMETER TestServicePrincipalName
    Name for the test service principal (default: "sp-rbac-test")

.PARAMETER Interactive
    Enable interactive menu to select which test categories to run

.EXAMPLE
    .\Test-CustomRole.ps1 -SubscriptionId "12345-..." -Location "eastus"

.EXAMPLE
    .\Test-CustomRole.ps1 -SubscriptionId "12345-..." -SkipCleanup

.EXAMPLE
    .\Test-CustomRole.ps1 -SubscriptionId "12345-..." -Interactive
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [string]$CustomRoleName = "Restricted Subscription Owner",

    [Parameter(Mandatory = $false)]
    [string]$TestResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus",

    [Parameter(Mandatory = $false)]
    [switch]$StrictRegionValidation,

    [Parameter(Mandatory = $false)]
    [switch]$SkipSetup,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCleanup,

    [Parameter(Mandatory = $false)]
    [string]$TestServicePrincipalName,

    [Parameter(Mandatory = $false)]
    [switch]$SafetyPrompts,

    [Parameter(Mandatory = $false)]
    [switch]$Interactive
)

# Script configuration
$ErrorActionPreference = "Continue"
$WarningPreference = "SilentlyContinue"  # Suppress cross-tenant MFA warnings
$ScriptRoot = $PSScriptRoot
$TestStartTime = Get-Date

# Generate unique suffix for this test run (used for all resources)
$UniqueSuffix = Get-Date -Format 'yyyyMMdd-HHmmss'

# Set default names with unique suffix if not provided
if (-not $TestResourceGroupName) {
    $TestResourceGroupName = "rg-rbac-test-$UniqueSuffix"
}
if (-not $TestServicePrincipalName) {
    $TestServicePrincipalName = "sp-rbac-test-$UniqueSuffix"
}

# In interactive mode OR when safety prompts are enabled, force region picker unless user explicitly supplied -Location.
# This prevents premature region capability validation against the implicit default (eastus)
# and ensures the user consciously selects the target region before tests proceed.
if ( ($Interactive -or $SafetyPrompts) -and -not $PSBoundParameters.ContainsKey('Location')) {
    $trigger = if ($Interactive -and $SafetyPrompts) { 'Interactive & SafetyPrompts' } elseif ($Interactive) { 'Interactive' } else { 'SafetyPrompts' }
    Write-Host "$trigger mode: deferring region selection (default '$Location' ignored)." -ForegroundColor Gray
    $Location = $null
}

# Disable cross-tenant token acquisition attempts
$env:AZURE_ENABLE_MULTI_TENANT_DISCOVERY = "false"

# Subscription selection helper
function Select-AzureSubscription {
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Azure Subscription Selection" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    # Check if already connected
    $currentContext = Get-AzContext -ErrorAction SilentlyContinue
    if (-not $currentContext) {
        Write-Host "Not connected to Azure. Initiating login..." -ForegroundColor Yellow
        Connect-AzAccount | Out-Null
        $currentContext = Get-AzContext
    } else {
        Write-Host "Current account: $($currentContext.Account.Id)" -ForegroundColor Gray
        if ($currentContext.Tenant.Id) {
            Write-Host "Current tenant: $($currentContext.Tenant.Id)" -ForegroundColor Gray
        }
        Write-Host ""
    }

    # Get subscriptions in current tenant only (respect existing tenant scope)
    $currentTenantId = $currentContext.Tenant.Id
    Write-Host "Retrieving available subscriptions in current tenant ($currentTenantId)..." -ForegroundColor Gray
    $allSubscriptions = @()
    
    try {
        # Explicitly limit to current tenant to avoid cross-tenant MFA prompts
        $allSubscriptions = @(Get-AzSubscription -TenantId $currentTenantId -ErrorAction Stop)
        
        if ($allSubscriptions.Count -eq 0) {
            throw "No subscriptions found in the current tenant ($currentTenantId). Please ensure you have access to at least one subscription."
        }
    } catch {
        throw "Failed to retrieve subscriptions: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "Available Subscriptions:" -ForegroundColor Cyan
    Write-Host ""

    # Display subscriptions with index
    for ($i = 0; $i -lt $allSubscriptions.Count; $i++) {
        $sub = $allSubscriptions[$i]
        $tenantDisplay = if ($sub.TenantId) { " (Tenant: $($sub.TenantId.Substring(0,8))...)" } else { "" }
        Write-Host "  [$i] $($sub.Name)$tenantDisplay" -ForegroundColor White
        Write-Host "      ID: $($sub.Id)" -ForegroundColor Gray
        Write-Host "      State: $($sub.State)" -ForegroundColor Gray
        Write-Host ""
    }

    # Prompt for selection
    do {
        Write-Host "Enter subscription number [0-$($allSubscriptions.Count - 1)]:" -ForegroundColor Yellow
        $selection = Read-Host "Selection"
        
        if ([string]::IsNullOrWhiteSpace($selection)) {
            Write-Host "No selection made. Please try again." -ForegroundColor Red
            continue
        }
        
        $selectedIndex = -1
        if ([int]::TryParse($selection, [ref]$selectedIndex)) {
            if ($selectedIndex -ge 0 -and $selectedIndex -lt $allSubscriptions.Count) {
                $selectedSub = $allSubscriptions[$selectedIndex]
                Write-Host ""
                Write-Host "Selected: $($selectedSub.Name) ($($selectedSub.Id))" -ForegroundColor Green
                
                # Set context to selected subscription
                Set-AzContext -SubscriptionId $selectedSub.Id -TenantId $selectedSub.TenantId | Out-Null
                
                return $selectedSub.Id
            }
        }
        
        Write-Host "Invalid selection. Please enter a number between 0 and $($allSubscriptions.Count - 1)." -ForegroundColor Red
    } while ($true)
}

# Region selection helper (invoked only if -Location not provided or blank)
function Select-AzureRegion {
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Azure Region Selection" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    # Fetch available locations for the current subscription context
    $locations = Get-AzLocation | Sort-Object -Property DisplayName
    if (-not $locations) { throw "Could not retrieve Azure locations for subscription." }

    # Prefer a curated/common list first for convenience
    $commonCodes = @("eastus","eastus2","westus","westus2","centralus","northcentralus","southcentralus","westeurope","northeurope","uksouth","ukwest","swedencentral","francecentral","germanywestcentral","eastasia","southeastasia","japaneast","australiaeast","centralindia","canadacentral")
    $ordered = @()
    foreach ($code in $commonCodes) {
        $match = $locations | Where-Object { $_.Location -eq $code }
        if ($match) { $ordered += $match }
    }
    # Append remaining locations not already included
    $remaining = $locations | Where-Object { $commonCodes -notcontains $_.Location }
    $ordered += $remaining

    Write-Host "Available Regions (first list shows commonly used):" -ForegroundColor Cyan
    Write-Host ""
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $loc = $ordered[$i]
        $display = $loc.DisplayName
        $code = $loc.Location
        Write-Host "  [$i] $display ($code)" -ForegroundColor White
    }
    Write-Host ""
    do {
        Write-Host "Enter region number [0-$($ordered.Count - 1)]:" -ForegroundColor Yellow
        $sel = Read-Host "Selection"
        $idx = 0
        if ([int]::TryParse($sel, [ref]$idx)) {
            if ($idx -ge 0 -and $idx -lt $ordered.Count) {
                $chosen = $ordered[$idx].Location
                Write-Host "Selected region: $($ordered[$idx].DisplayName) ($chosen)" -ForegroundColor Green
                return $chosen
            }
        }
        Write-Host "Invalid selection. Please try again." -ForegroundColor Red
    } while ($true)
}

# Validate and optionally register required resource providers
function Test-AzureProviderRegistration {
    param(
        [switch]$AutoRegister,
        [switch]$Strict
    )

    Write-Host "Validating required resource provider registration..." -ForegroundColor Gray
    $requiredProviders = @(
        'Microsoft.Network',
        'Microsoft.Storage'
    )

    $unregistered = @()
    foreach ($providerNs in $requiredProviders) {
        try {
            $provider = Get-AzResourceProvider -ProviderNamespace $providerNs -ErrorAction Stop
            $regState = $provider.RegistrationState
            
            if ($regState -ne 'Registered') {
                $unregistered += @{ Namespace = $providerNs; State = $regState }
                Write-Host "  ⚠ Provider '$providerNs' is not registered (state: $regState)" -ForegroundColor Yellow
            } else {
                Write-Host "  ✓ Provider '$providerNs' is registered" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  ⚠ Could not query provider '$providerNs': $($_.Exception.Message)" -ForegroundColor Yellow
            if ($Strict) { throw }
        }
    }

    if ($unregistered.Count -gt 0) {
        if ($AutoRegister) {
            Write-Host ""
            Write-Host "  → Auto-registering unregistered providers..." -ForegroundColor Cyan
            foreach ($item in $unregistered) {
                try {
                    Write-Host "    Registering $($item.Namespace)..." -ForegroundColor Gray
                    Register-AzResourceProvider -ProviderNamespace $item.Namespace | Out-Null
                    Write-Host "    ✓ Registration initiated for $($item.Namespace)" -ForegroundColor Gray
                } catch {
                    Write-Host "    ✗ Failed to register $($item.Namespace): $($_.Exception.Message)" -ForegroundColor Red
                    if ($Strict) { throw }
                }
            }
            
            # Wait for registration to complete
            Write-Host "    → Waiting for provider registration (up to 120 seconds)..." -ForegroundColor Gray
            $waitStart = Get-Date
            $allRegistered = $false
            while (-not $allRegistered -and ((Get-Date) - $waitStart).TotalSeconds -lt 120) {
                Start-Sleep -Seconds 10
                $stillPending = @()
                foreach ($item in $unregistered) {
                    $current = Get-AzResourceProvider -ProviderNamespace $item.Namespace -ErrorAction SilentlyContinue
                    if ($current.RegistrationState -ne 'Registered') {
                        $stillPending += $item.Namespace
                    }
                }
                if ($stillPending.Count -eq 0) {
                    $allRegistered = $true
                    Write-Host "    ✓ All providers registered successfully" -ForegroundColor Green
                } else {
                    $elapsed = [int]((Get-Date) - $waitStart).TotalSeconds
                    Write-Host "      → Still registering: $($stillPending -join ', ') (${elapsed}s elapsed)" -ForegroundColor DarkGray
                }
            }
            
            if (-not $allRegistered) {
                Write-Host "    ⚠ Some providers still registering after timeout; proceeding anyway" -ForegroundColor Yellow
            }
        } else {
            Write-Host ""
            Write-Host "  ⚠ Unregistered providers detected. You can:" -ForegroundColor Yellow
            Write-Host "    1. Run this script again with automatic registration (will prompt)" -ForegroundColor Yellow
            Write-Host "    2. Manually register via: Register-AzResourceProvider -ProviderNamespace <namespace>" -ForegroundColor Yellow
            Write-Host ""
            $response = Read-Host "  Register providers now? (Y/N)"
            if ($response -in @('Y','y')) {
                Test-AzureProviderRegistration -AutoRegister
                return
            } else {
                Write-Host "  → Proceeding without registration; resource creation may fail" -ForegroundColor DarkGray
                if ($Strict) {
                    throw "Provider registration required under strict mode. Unregistered: $($unregistered.Namespace -join ', ')"
                }
            }
        }
    } else {
        Write-Host "  ✓ All required providers are registered" -ForegroundColor Green
    }
}

# Validate region supports required resource types (network + storage)
function Test-AzureRegionCompatibility {
    param(
        [Parameter(Mandatory)] [string]$Location,
        [switch]$Strict
    )

    Write-Host "Validating region support for required resource types..." -ForegroundColor Gray
    # NOTE: Provider metadata returns Display Names (e.g. "East US") while callers typically
    # pass short codes (e.g. "eastus"). Previous logic compared code to display causing
    # false negatives. We normalize both sets before comparison.
    $allLocations = Get-AzLocation | Select-Object DisplayName, Location
    $selected = $allLocations | Where-Object { $_.Location -eq $Location }
    if (-not $selected) {
        $normalizedInput = ($Location -replace '\s','' -replace '[^a-zA-Z0-9]','')
        $selected = $allLocations | Where-Object { ($_.DisplayName -replace '\s','' -replace '[^a-zA-Z0-9]','') -eq $normalizedInput }
    }
    if (-not $selected) {
        Write-Host "  ⚠ Could not resolve supplied location '$Location' against subscription location list." -ForegroundColor Yellow
        if ($Strict) { throw "Unrecognized location '$Location'" }
    }
    $normalizedTargetCode    = $selected.Location
    $normalizedTargetDisplay = $selected.DisplayName
    $targetTokens = @()
    if ($normalizedTargetCode)    { $targetTokens += $normalizedTargetCode.ToLower() }
    if ($normalizedTargetDisplay) { $targetTokens += $normalizedTargetDisplay.ToLower(); $targetTokens += ($normalizedTargetDisplay -replace '\s','').ToLower() }
    if (-not $targetTokens) { $targetTokens += ($Location.ToLower()) }
    $requiredTypes = @(
        'Microsoft.Network/virtualNetworks',
        'Microsoft.Network/virtualNetworkGateways',
        'Microsoft.Network/routeTables',
        'Microsoft.Network/loadBalancers',
        'Microsoft.Network/applicationGateways',
        'Microsoft.Network/privateEndpoints',
        'Microsoft.Network/privateLinkServices',
        'Microsoft.Network/natGateways',
        'Microsoft.Network/networkWatchers',
        'Microsoft.Network/serviceEndpointPolicies',
        'Microsoft.Network/virtualWans',
        'Microsoft.Network/virtualHubs',
        'Microsoft.Network/trafficManagerProfiles',  # often global
        'Microsoft.Network/virtualNetworkTaps',
        'Microsoft.Network/azureFirewalls',
        'Microsoft.Network/firewallPolicies',
        'Microsoft.Network/ipGroups',
        'Microsoft.Network/ddosProtectionPlans',
        'Microsoft.Storage/storageAccounts'
    )

    $grouped = $requiredTypes | Group-Object { ($_ -split '/')[0] }
    $missing = @()

    foreach ($grp in $grouped) {
        $providerNs = $grp.Name
        try {
            $provider = Get-AzResourceProvider -ProviderNamespace $providerNs -ErrorAction Stop
        } catch {
            Write-Host "  ⚠ Could not query provider ${providerNs}: $($_.Exception.Message)" -ForegroundColor Yellow
            if ($Strict) { throw }
            continue
        }

        foreach ($fullType in $grp.Group) {
            $typeName = ($fullType -split '/')[1]
            $rt = $provider.ResourceTypes | Where-Object { $_.ResourceTypeName -eq $typeName }
            if (-not $rt) {
                # Sometimes subtypes (e.g., trafficManagerProfiles) not listed per region because global
                Write-Host "  ◦ Resource type not found in provider metadata (assuming global): $fullType" -ForegroundColor DarkGray
                continue
            }
            $locations = $rt.Locations
            if (-not $locations -or $locations.Count -eq 0) {
                Write-Host "  ◦ No location list for $fullType (treating as global/multi-region)" -ForegroundColor DarkGray
                continue
            }
            $normalizedLocations = $locations | ForEach-Object {
                @(
                    $_.ToLower(),
                    ($_.ToLower() -replace '\s',''),
                    ($_.ToLower() -replace '[^a-z0-9]','')
                )
            } | Select-Object -Unique
            $isGlobal = ($normalizedLocations -contains 'global')
            $locationMatches = ($targetTokens | Where-Object { $normalizedLocations -contains $_ })
            if (-not $isGlobal -and -not $locationMatches) {
                $missing += $fullType
            }
        }
    }

    if ($missing.Count -gt 0) {
        $displayLoc = if ($normalizedTargetDisplay) { $normalizedTargetDisplay } else { $Location }
        Write-Host "  ⚠ Region '$displayLoc' does not list support for: " -ForegroundColor Yellow
        $missing | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
        if ($Strict) {
            throw "Region validation failed under strict mode. Unsupported types: $($missing -join ', ')"
        } else {
            Write-Host "  (Proceeding anyway; some types may succeed if globally routed or recently added)" -ForegroundColor DarkGray
        }
    } else {
        $displayLoc = if ($normalizedTargetDisplay) { $normalizedTargetDisplay } else { $Location }
        Write-Host "  ✓ Region '$displayLoc' passed compatibility validation" -ForegroundColor Green
    }
}

# If SubscriptionId not provided, show subscription picker
if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
    $SubscriptionId = Select-AzureSubscription
    Write-Host ""
}

# Prompt for region if user passed empty string or placeholder
if ([string]::IsNullOrWhiteSpace($Location)) {
    Write-Host "No region provided. Launching region picker..." -ForegroundColor Yellow
    $Location = Select-AzureRegion
    Write-Host ""
}

# Validate resource provider registration (check Microsoft.Network and Microsoft.Storage)
try {
    Test-AzureProviderRegistration -Strict:$StrictRegionValidation
    Write-Host ""
} catch {
    Write-Host "  ✗ Provider registration validation failed: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# Perform region capability validation (non-strict by default)
try {
    Test-AzureRegionCompatibility -Location $Location -Strict:$StrictRegionValidation
} catch {
    Write-Host "  ✗ Region compatibility validation failed: $($_.Exception.Message)" -ForegroundColor Red
    throw
}

# Test results collection
$Global:TestResults = @{
    TestRun = @{
        Timestamp = $TestStartTime.ToString("o")
        CustomRoleName = $CustomRoleName
        Subscription = $SubscriptionId
        Location = $Location
        TestIdentity = $TestServicePrincipalName
        Results = @()
        Summary = @{
            TotalTests = 0
            Passed = 0
            Failed = 0
            Errors = 0
            Skipped = 0
        }
    }
}

# Import test modules
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Restricted Subscription Owner - RBAC Test Suite" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Interactive menu for test selection
$selectedCategories = @()
if ($Interactive) {
    Write-Host "Select Test Categories to Run:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [0]  Run ALL Tests (Authorization + All Networking)" -ForegroundColor White
    Write-Host ""
    Write-Host "  Authorization & Policy:" -ForegroundColor Cyan
    Write-Host "    [15] Policy & Authorization restrictions" -ForegroundColor White
    Write-Host ""
    Write-Host "  Networking Restrictions:" -ForegroundColor Cyan
    Write-Host "    [1]  Virtual Networks (VNET, subnets, peering)" -ForegroundColor White
    Write-Host "    [2]  ExpressRoute & VPN Gateways (create-only tests)" -ForegroundColor White
    Write-Host "    [3]  Route Tables" -ForegroundColor White
    Write-Host "    [4]  Front Door & CDN (create-only tests)" -ForegroundColor White
    Write-Host "    [5]  Load Balancers & Application Gateways (create-only tests)" -ForegroundColor White
    Write-Host "    [6]  Private Link & Private Endpoints (create-only tests)" -ForegroundColor White
    Write-Host "    [7]  NAT Gateways" -ForegroundColor White
    Write-Host "    [8]  Network Watcher" -ForegroundColor White
    Write-Host "    [9]  Service Endpoints" -ForegroundColor White
    Write-Host "    [10] Virtual WAN (create-only test)" -ForegroundColor White
    Write-Host "    [11] Traffic Manager" -ForegroundColor White
    Write-Host "    [12] Virtual Network Tap (create-only test)" -ForegroundColor White
    Write-Host "    [13] Azure Firewall & Firewall Policies" -ForegroundColor White
    Write-Host "    [14] DDoS Protection Plans (create-only test)" -ForegroundColor White
    Write-Host ""
    Write-Host "Enter your selections (comma-separated, e.g., 0 or 1,2,5,15):" -ForegroundColor Yellow
    $selection = Read-Host "Selection"
    
    if ([string]::IsNullOrWhiteSpace($selection)) {
        Write-Host "No selection made. Running ALL tests." -ForegroundColor Gray
        $selectedCategories = @(1..15)
    } elseif ($selection -eq "0") {
        Write-Host "Running ALL tests." -ForegroundColor Green
        $selectedCategories = @(1..15)
    } else {
        $selectedCategories = $selection -split ',' | ForEach-Object { [int]$_.Trim() } | Where-Object { $_ -ge 1 -and $_ -le 15 }
        if ($selectedCategories.Count -eq 0) {
            Write-Host "Invalid selection. Running ALL tests." -ForegroundColor Yellow
            $selectedCategories = @(1..15)
        } else {
            Write-Host "Selected categories: $($selectedCategories -join ', ')" -ForegroundColor Green
        }
    }
    Write-Host ""
} else {
    # Non-interactive: run all tests
    $selectedCategories = @(1..15)
}

try {
    # Phase 1: Setup
    if (-not $SkipSetup) {
        Write-Host "[PHASE 1] Setting up test environment..." -ForegroundColor Yellow
        . "$ScriptRoot\Initialize-TestEnvironment.ps1"
        $setupResult = Initialize-TestEnvironment `
            -SubscriptionId $SubscriptionId `
            -CustomRoleName $CustomRoleName `
            -TestResourceGroupName $TestResourceGroupName `
            -Location $Location `
            -TestServicePrincipalName $TestServicePrincipalName `
            -UniqueSuffix $UniqueSuffix `
            -SafetyPrompts:$SafetyPrompts

        if (-not $setupResult.Success) {
            throw "Setup failed: $($setupResult.Error)"
        }

        $Global:TestContext = $setupResult.Context
        Write-Host "✓ Setup completed successfully" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "[PHASE 1] Skipping setup phase (using existing environment)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "[WARNING] SkipSetup mode detected - tests will run in current context" -ForegroundColor Yellow
        Write-Host "          Ensure you are authenticated as the service principal with restricted role" -ForegroundColor Yellow
        Write-Host "          Or tests may show incorrect results if running as Owner/Contributor" -ForegroundColor Yellow
        Write-Host ""
        
        # Check if already running as service principal
        $currentContext = Get-AzContext
        $currentAccount = $currentContext.Account.Id
        
        # Try to find the test service principal
        $testSp = Get-AzADServicePrincipal -DisplayName $TestServicePrincipalName -ErrorAction SilentlyContinue
        if ($testSp -and $currentAccount -eq $testSp.AppId) {
            Write-Host "  ✓ Currently authenticated as test service principal: $currentAccount" -ForegroundColor Green
            Write-Host ""
        } else {
            Write-Host "  ⚠ Not authenticated as test service principal!" -ForegroundColor Yellow
            Write-Host "    Current account: $currentAccount" -ForegroundColor Yellow
            if ($testSp) {
                Write-Host "    Expected SP: $($testSp.AppId)" -ForegroundColor Yellow
            }
            Write-Host ""
        }
        
        # Load existing context
        $Global:TestContext = @{
            SubscriptionId = $SubscriptionId
            ResourceGroupName = $TestResourceGroupName
            Location = $Location
            ServicePrincipalId = $testSp.Id
            ServicePrincipalAppId = $testSp.AppId
        }
    }

    # Switch to Service Principal context for testing (only if we have credentials from setup)
    if (-not $SkipSetup -and $Global:TestContext.ServicePrincipalAppId -and $Global:TestContext.ServicePrincipalSecret) {
        Write-Host "[CONTEXT SWITCH] Authenticating as test service principal..." -ForegroundColor Cyan
        
        if ($SafetyPrompts) {
            $resp = Read-Host "  Switch context to service principal '$TestServicePrincipalName'? (Y/N)"
            if ($resp -notin @('Y','y')) { throw "User declined service principal context switch." }
        }
        
        # Save current user context
        $userContext = Get-AzContext
        $Global:TestContext.UserContext = $userContext
        
        # Authenticate as service principal
        $spPassword = ConvertTo-SecureString $Global:TestContext.ServicePrincipalSecret -AsPlainText -Force
        $spCredential = New-Object System.Management.Automation.PSCredential($Global:TestContext.ServicePrincipalAppId, $spPassword)
        
        try {
            $WarningPreference = 'SilentlyContinue'
            Connect-AzAccount -ServicePrincipal -Credential $spCredential -Tenant $Global:TestContext.TenantId -Subscription $SubscriptionId -ErrorAction Stop | Out-Null
            $WarningPreference = 'Continue'
            Write-Host "  ✓ Now running tests as service principal: $($Global:TestContext.ServicePrincipalAppId)" -ForegroundColor Green
            Write-Host "  ✓ With custom role: $($Global:TestContext.CustomRoleName)" -ForegroundColor Green
            Write-Host ""
        } catch {
            Write-Host "  ✗ Failed to authenticate as service principal: $($_.Exception.Message)" -ForegroundColor Red
            throw
        }
    } else {
        Write-Host "[WARNING] Running tests in current user context (not service principal)" -ForegroundColor Yellow
        Write-Host "          Tests may show unexpected results if user has Owner/Contributor roles" -ForegroundColor Yellow
        Write-Host ""
    }

    # Phase 2: Test Authorization Restrictions
    if ($selectedCategories -contains 15) {
        Write-Host "[PHASE 2] Testing Authorization & Policy restrictions..." -ForegroundColor Yellow
        
        # Verify we're running as service principal
        $currentContext = Get-AzContext
        if ($Global:TestContext.ServicePrincipalAppId -and $currentContext.Account.Id -ne $Global:TestContext.ServicePrincipalAppId) {
            Write-Host "  ⚠ WARNING: Not running as expected service principal!" -ForegroundColor Yellow
            Write-Host "    Expected: $($Global:TestContext.ServicePrincipalAppId)" -ForegroundColor Yellow
            Write-Host "    Current: $($currentContext.Account.Id)" -ForegroundColor Yellow
        }
        
        . "$ScriptRoot\Test-AuthorizationRestrictions.ps1"
        $authResults = Test-AuthorizationRestrictions -Context $Global:TestContext
        $Global:TestResults.TestRun.Results += $authResults
        Write-Host "✓ Authorization tests completed ($($authResults.Count) tests)" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "[PHASE 2] Skipping Authorization tests (not selected)" -ForegroundColor Gray
        Write-Host ""
    }

    # Phase 3: Test Networking Restrictions
    $networkCategories = $selectedCategories | Where-Object { $_ -ge 1 -and $_ -le 14 }
    if ($networkCategories.Count -gt 0) {
        Write-Host "[PHASE 3] Testing Networking restrictions..." -ForegroundColor Yellow
        
        # Verify we're still running as service principal
        $currentContext = Get-AzContext
        if ($Global:TestContext.ServicePrincipalAppId -and $currentContext.Account.Id -ne $Global:TestContext.ServicePrincipalAppId) {
            Write-Host "  ⚠ WARNING: Not running as expected service principal!" -ForegroundColor Yellow
            Write-Host "    Expected: $($Global:TestContext.ServicePrincipalAppId)" -ForegroundColor Yellow
            Write-Host "    Current: $($currentContext.Account.Id)" -ForegroundColor Yellow
        }
        
        . "$ScriptRoot\Test-NetworkingRestrictions.ps1"
        $networkResults = Test-NetworkingRestrictions -Context $Global:TestContext -SelectedRequirements $networkCategories
        $Global:TestResults.TestRun.Results += $networkResults
        Write-Host "✓ Networking tests completed ($($networkResults.Count) tests)" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "[PHASE 3] Skipping Networking tests (not selected)" -ForegroundColor Gray
        Write-Host ""
    }

    # Phase 4: Calculate Summary
    Write-Host "[PHASE 4] Calculating test results..." -ForegroundColor Yellow
    $Global:TestResults.TestRun.Summary.TotalTests = $Global:TestResults.TestRun.Results.Count
    $Global:TestResults.TestRun.Summary.Passed = ($Global:TestResults.TestRun.Results | Where-Object { $_.Status -eq "PASS" }).Count
    $Global:TestResults.TestRun.Summary.Failed = ($Global:TestResults.TestRun.Results | Where-Object { $_.Status -eq "FAIL" }).Count
    $Global:TestResults.TestRun.Summary.Errors  = ($Global:TestResults.TestRun.Results | Where-Object { $_.Status -eq "ERROR" }).Count
    $Global:TestResults.TestRun.Summary.Skipped = ($Global:TestResults.TestRun.Results | Where-Object { $_.Status -eq "SKIPPED" }).Count
    
    $TestEndTime = Get-Date
    $Global:TestResults.TestRun.Duration = ($TestEndTime - $TestStartTime).ToString()
    
    Write-Host "✓ Summary calculated" -ForegroundColor Green
    Write-Host ""

    # Switch back to user context before export/cleanup
    if ($Global:TestContext.UserContext) {
        Write-Host "[CONTEXT SWITCH] Restoring user context..." -ForegroundColor Cyan
        if ($SafetyPrompts) {
            $resp = Read-Host "  Restore original user context before cleanup? (Y/N)"
            if ($resp -notin @('Y','y')) { Write-Host "  ⚠ User skipped context restore; continuing in SP context" -ForegroundColor Yellow }
            else {
                try {
                    $WarningPreference = 'SilentlyContinue'
                    Set-AzContext -Context $Global:TestContext.UserContext -ErrorAction Stop | Out-Null
                    $WarningPreference = 'Continue'
                    Write-Host "  ✓ Restored user context for export and cleanup" -ForegroundColor Green
                    Write-Host ""
                } catch {
                    Write-Host "  ✗ Failed to restore user context: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "  → You may need to manually re-authenticate" -ForegroundColor Yellow
                    Write-Host ""
                }
            }
        } else {
            try {
                $WarningPreference = 'SilentlyContinue'
                Set-AzContext -Context $Global:TestContext.UserContext -ErrorAction Stop | Out-Null
                $WarningPreference = 'Continue'
                Write-Host "  ✓ Restored user context for export and cleanup" -ForegroundColor Green
                Write-Host ""
            } catch {
                Write-Host "  ✗ Failed to restore user context: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "  → You may need to manually re-authenticate" -ForegroundColor Yellow
                Write-Host ""
            }
        }
    }

    # Phase 5: Export Results
    Write-Host "[PHASE 5] Exporting test results..." -ForegroundColor Yellow
    . "$ScriptRoot\Export-TestResults.ps1"
    Export-TestResults -TestResults $Global:TestResults -OutputPath "$ScriptRoot\Results"
    Write-Host "✓ Results exported" -ForegroundColor Green
    Write-Host ""

    # Phase 6: Cleanup
    if (-not $SkipCleanup) {
        Write-Host "[PHASE 6] Cleaning up test environment..." -ForegroundColor Yellow
    . "$ScriptRoot\Clear-TestEnvironment.ps1"
    Clear-TestEnvironment -Context $Global:TestContext -SafetyPrompts:$SafetyPrompts
        Write-Host "✓ Cleanup completed" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-Host "[PHASE 6] Skipping cleanup phase (resources preserved)" -ForegroundColor Gray
        Write-Host ""
    }

    # Display Summary
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  TEST SUMMARY" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Total Tests:  $($Global:TestResults.TestRun.Summary.TotalTests)" -ForegroundColor White
    Write-Host "Passed:       $($Global:TestResults.TestRun.Summary.Passed)" -ForegroundColor Green
    Write-Host "Failed:       $($Global:TestResults.TestRun.Summary.Failed)" -ForegroundColor Red
    Write-Host "Errors:       $($Global:TestResults.TestRun.Summary.Errors)" -ForegroundColor Yellow
    Write-Host "Skipped:      $($Global:TestResults.TestRun.Summary.Skipped)" -ForegroundColor Gray
    Write-Host "Duration:     $($Global:TestResults.TestRun.Duration)" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan

    $failedCount = $Global:TestResults.TestRun.Summary.Failed
    $errorCount  = $Global:TestResults.TestRun.Summary.Errors
    $skippedCount = $Global:TestResults.TestRun.Summary.Skipped

    if ($failedCount -eq 0 -and $errorCount -eq 0) {
        if ($skippedCount -gt 0) {
            Write-Host "✓ All executed tests passed. Some tests were skipped (see reports)." -ForegroundColor Green
        } else {
            Write-Host "✓ All tests passed successfully!" -ForegroundColor Green
        }
        $global:LASTEXITCODE = 0
    } elseif ($failedCount -gt 0 -and $errorCount -gt 0) {
        Write-Host "✗ Tests completed with failures ($failedCount) and errors ($errorCount). Review detailed reports: $ScriptRoot\Results" -ForegroundColor Red
        $global:LASTEXITCODE = 1
    } elseif ($failedCount -gt 0) {
        Write-Host "✗ Some tests failed ($failedCount). Review detailed reports: $ScriptRoot\Results" -ForegroundColor Red
        $global:LASTEXITCODE = 1
    } elseif ($errorCount -gt 0) {
        Write-Host "✗ Tests encountered errors ($errorCount) but no functional failures. Review error details: $ScriptRoot\Results" -ForegroundColor Yellow
        # Treat errors as non-zero exit to surface pipeline issues
        $global:LASTEXITCODE = 1
    }
    return $Global:TestResults.TestRun
} catch {
    Write-Host "✗ Critical error during test execution:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    
    # Attempt to restore user context if it was saved
    if ($Global:TestContext.UserContext) {
        Write-Host "" -ForegroundColor Red
        Write-Host "[CONTEXT RESTORE] Attempting to restore user context after error..." -ForegroundColor Yellow
        try {
            $WarningPreference = 'SilentlyContinue'
            Set-AzContext -Context $Global:TestContext.UserContext -ErrorAction Stop | Out-Null
            $WarningPreference = 'Continue'
            Write-Host "  ✓ User context restored" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Failed to restore context: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "  → You may need to run: Connect-AzAccount" -ForegroundColor Yellow
        }
    }
    
    $global:LASTEXITCODE = 1
    return $Global:TestResults.TestRun
}
