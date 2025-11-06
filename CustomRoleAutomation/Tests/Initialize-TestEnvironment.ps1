<#
.SYNOPSIS
    Initialize test environment for RBAC testing

.DESCRIPTION
    Sets up the test environment including:
    - Service principal creation
    - Custom role assignment
    - Test resource group
    - Pre-requisite resources for modify/delete tests
#>

function Initialize-TestEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory = $true)]
        [string]$CustomRoleName,

        [Parameter(Mandatory = $true)]
        [string]$TestResourceGroupName,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$TestServicePrincipalName,

        [Parameter(Mandatory = $false)]
        [string]$UniqueSuffix,

        [Parameter(Mandatory = $false)]
        [switch]$SafetyPrompts
    )

    $result = @{
        Success = $false
        Error = $null
        Context = @{}
    }

    try {
        Write-Host "  → Connecting to Azure subscription: $SubscriptionId" -ForegroundColor Gray
        
        # Suppress cross-tenant warnings during context switch
        $originalWarningPref = $WarningPreference
        $WarningPreference = 'SilentlyContinue'
        
        Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
        
        $WarningPreference = $originalWarningPref

        # Check if custom role exists, create if not
        Write-Host "  → Verifying custom role exists: $CustomRoleName" -ForegroundColor Gray
        $customRole = Get-AzRoleDefinition -Name $CustomRoleName -ErrorAction SilentlyContinue
        if (-not $customRole) {
            Write-Host "  → Custom role not found. Creating from definition file..." -ForegroundColor Yellow
            $roleDefPath = Join-Path $PSScriptRoot "..\CustomRole_RestrictedSubscriptionOwner.json"
            
            if (-not (Test-Path $roleDefPath)) {
                throw "Custom role definition file not found at: $roleDefPath. Please ensure the file exists."
            }
            
            # Read and update the role definition with current subscription
            $roleDefContent = Get-Content $roleDefPath -Raw | ConvertFrom-Json
            $roleDefContent.AssignableScopes = @("/subscriptions/$SubscriptionId")
            
            # Create temporary file with updated scope
            $tempRoleDef = Join-Path $env:TEMP "CustomRole_Temp_$([System.Guid]::NewGuid().ToString('N').Substring(0,8)).json"
            $roleDefContent | ConvertTo-Json -Depth 10 | Set-Content $tempRoleDef
            
            try {
                New-AzRoleDefinition -InputFile $tempRoleDef | Out-Null
                Write-Host "    ✓ Custom role '$CustomRoleName' created successfully" -ForegroundColor Green
                Write-Host "    → Waiting for role definition propagation (60 seconds)..." -ForegroundColor Gray
                Start-Sleep -Seconds 60  # Wait longer for role definition propagation across Azure
                
                # Verify role is queryable before proceeding
                $verifyCount = 0
                $roleReady = $false
                while (-not $roleReady -and $verifyCount -lt 6) {
                    $checkRole = Get-AzRoleDefinition -Name $CustomRoleName -ErrorAction SilentlyContinue
                    if ($checkRole) {
                        $roleReady = $true
                        Write-Host "    ✓ Role definition verified and ready" -ForegroundColor Gray
                    } else {
                        $verifyCount++
                        if ($verifyCount -lt 6) {
                            Write-Host "    → Role still propagating, waiting 10 more seconds... ($verifyCount/6)" -ForegroundColor Yellow
                            Start-Sleep -Seconds 10
                        }
                    }
                }
                
                if (-not $roleReady) {
                    Write-Host "    ⚠ Role may still be propagating. Proceeding anyway..." -ForegroundColor Yellow
                }
            } finally {
                # Clean up temp file
                if (Test-Path $tempRoleDef) {
                    Remove-Item $tempRoleDef -Force
                }
            }
        } else {
            Write-Host "    ✓ Custom role already exists" -ForegroundColor Gray
        }

        # Create or get test resource group
        Write-Host "  → Creating test resource group: $TestResourceGroupName" -ForegroundColor Gray
        $rg = Get-AzResourceGroup -Name $TestResourceGroupName -ErrorAction SilentlyContinue
        if (-not $rg) {
            $rg = New-AzResourceGroup -Name $TestResourceGroupName -Location $Location
        }

        # Create service principal for testing
        Write-Host "  → Creating test service principal: $TestServicePrincipalName" -ForegroundColor Gray
        $servicePrincipalCreatedByUs = $false
        $servicePrincipalAppObjectId = $null

        # Check if SP already exists
        $existingSp = Get-AzADServicePrincipal -DisplayName $TestServicePrincipalName -ErrorAction SilentlyContinue
        if ($existingSp) {
            Write-Host "    (Using existing service principal)" -ForegroundColor Gray
            $sp = $existingSp
            if ($SafetyPrompts) {
                $resp = Read-Host "    Confirm creating a NEW credential for existing SP '$TestServicePrincipalName'? (Y/N)"
                if ($resp -notin @('Y','y')) { throw "User declined SP credential creation." }
            }
            # Existing SP - create a new credential for authentication
            Write-Host "    → Creating new credential for existing SP..." -ForegroundColor Gray
            $spCredential = New-AzADServicePrincipalCredential -ObjectId $sp.Id -EndDate (Get-Date).AddHours(4)
            $spSecret = $spCredential.SecretText
        } else {
            if ($SafetyPrompts) {
                $resp = Read-Host "    Create NEW service principal '$TestServicePrincipalName'? (Y/N)"
                if ($resp -notin @('Y','y')) { throw "User declined SP creation." }
            }
            # Create new service principal without role assignment (avoid credential policy issues)
            # Use shorter credential validity to comply with organizational policies
            $sp = New-AzADServicePrincipal -DisplayName $TestServicePrincipalName -EndDate (Get-Date).AddHours(4) -ErrorAction Stop
            $spSecret = $sp.PasswordCredentials.SecretText
            Write-Host "    Created SP with Object ID: $($sp.Id)" -ForegroundColor Gray
            $servicePrincipalCreatedByUs = $true
            # Capture backing application object ID for optional cleanup
            try {
                $appObj = Get-AzADApplication -Filter "appId eq '$($sp.AppId)'" -ErrorAction SilentlyContinue
                if ($appObj) { $servicePrincipalAppObjectId = $appObj.Id }
            } catch {}
        }

        # Assign custom role to service principal at subscription scope
        Write-Host "  → Assigning custom role to service principal..." -ForegroundColor Gray
        if ($SafetyPrompts) {
            $resp = Read-Host "    Proceed with role assignment of '$CustomRoleName' to SP '$TestServicePrincipalName'? (Y/N)"
            if ($resp -notin @('Y','y')) { throw "User declined role assignment." }
        }
        $roleAssignment = Get-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $CustomRoleName -Scope "/subscriptions/$SubscriptionId" -ErrorAction SilentlyContinue
        if (-not $roleAssignment) {
            # Retry logic in case role definition hasn't propagated yet
            $retryCount = 0
            $maxRetries = 6  # Up to 6 attempts
            $assigned = $false
            
            while (-not $assigned -and $retryCount -lt $maxRetries) {
                try {
                    # First verify the role exists before attempting assignment
                    $roleCheck = Get-AzRoleDefinition -Name $CustomRoleName -ErrorAction SilentlyContinue
                    if (-not $roleCheck) {
                        throw "Role definition '$CustomRoleName' not yet available"
                    }
                    
                    New-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName $CustomRoleName -Scope "/subscriptions/$SubscriptionId" -ErrorAction Stop | Out-Null
                    $assigned = $true
                    Write-Host "    ✓ Role assigned successfully" -ForegroundColor Gray
                } catch {
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Write-Host "    → Role assignment failed (attempt $retryCount/$maxRetries): $($_.Exception.Message)" -ForegroundColor Yellow
                        Write-Host "    → Waiting 15 seconds before retry..." -ForegroundColor Yellow
                        Start-Sleep -Seconds 15
                    } else {
                        throw "Failed to assign role after $maxRetries attempts. Error: $($_.Exception.Message)"
                    }
                }
            }
            
            Write-Host "  → Waiting for role assignment propagation (30 seconds)..." -ForegroundColor Gray
            Start-Sleep -Seconds 30
        } else {
            Write-Host "    ✓ Role already assigned" -ForegroundColor Gray
        }

        # Create pre-requisite resources for complex network tests (as Owner)
        Write-Host "  → Creating prerequisite network resources..." -ForegroundColor Gray

        # Base VNet for modification / gateway / firewall tests
        try {
            $vnetName = "vnet-test-existing-$UniqueSuffix"
            $existingVnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue
            if (-not $existingVnet) {
                $existingVnet = New-AzVirtualNetwork -Name $vnetName -ResourceGroupName $TestResourceGroupName -Location $Location -AddressPrefix "10.100.0.0/16" -Subnet @(New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.100.1.0/24")
                Write-Host "    ✓ Created base VNET $vnetName" -ForegroundColor Gray
            }
            # Ensure gateway subnet exists
            if (-not ($existingVnet.Subnets | Where-Object { $_.Name -eq 'GatewaySubnet' })) {
                $existingVnet | Add-AzVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -AddressPrefix '10.100.250.0/27' | Out-Null
                $existingVnet | Add-AzVirtualNetworkSubnetConfig -Name 'AzureFirewallSubnet' -AddressPrefix '10.100.251.0/26' | Out-Null
                $existingVnet | Add-AzVirtualNetworkSubnetConfig -Name 'AppGatewaySubnet' -AddressPrefix '10.100.252.0/27' | Out-Null
                $existingVnet = Set-AzVirtualNetwork -VirtualNetwork $existingVnet
                Write-Host "    ✓ Added GatewaySubnet, AzureFirewallSubnet, AppGatewaySubnet" -ForegroundColor Gray
            }
        } catch {
            Write-Host "    ⚠ Could not create/augment test VNET: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Second VNet for peering test
        try {
            $peerVnetName = "vnet-test-peer-$UniqueSuffix"
            $peerVnet = Get-AzVirtualNetwork -Name $peerVnetName -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue
            if (-not $peerVnet) {
                $peerVnet = New-AzVirtualNetwork -Name $peerVnetName -ResourceGroupName $TestResourceGroupName -Location $Location -AddressPrefix "10.101.0.0/16" -Subnet @(New-AzVirtualNetworkSubnetConfig -Name "default" -AddressPrefix "10.101.1.0/24")
                Write-Host "    ✓ Created peer VNET $peerVnetName" -ForegroundColor Gray
            }
        } catch {
            Write-Host "    ⚠ Could not create peer VNET: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Route table for route modification tests
        try {
            $routeTableName = "rt-test-existing-$UniqueSuffix"
            $existingRouteTable = Get-AzRouteTable -Name $routeTableName -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue
            if (-not $existingRouteTable) {
                $existingRouteTable = New-AzRouteTable -Name $routeTableName -ResourceGroupName $TestResourceGroupName -Location $Location
                Write-Host "    ✓ Created route table $routeTableName" -ForegroundColor Gray
            }
        } catch {
            Write-Host "    ⚠ Could not create route table: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Public IPs for gateway, firewall, nat, app gateway (simplified)
        $publicIpNames = @("pip-gateway-$UniqueSuffix","pip-firewall-$UniqueSuffix","pip-nat-$UniqueSuffix","pip-appgw-$UniqueSuffix")
        foreach ($pipName in $publicIpNames) {
            try {
                $pip = Get-AzPublicIpAddress -Name $pipName -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue
                if (-not $pip) {
                    New-AzPublicIpAddress -Name $pipName -ResourceGroupName $TestResourceGroupName -Location $Location -Sku Standard -AllocationMethod Static | Out-Null
                    Write-Host "    ✓ Created Public IP $pipName" -ForegroundColor Gray
                }
            } catch {
                Write-Host "    ⚠ Could not create Public IP ${pipName}: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }

        # Storage account for Private Endpoint target
        try {
            $storageName = ("stpe" + ([System.Guid]::NewGuid().ToString("N").Substring(0,8))).ToLower()
            $storageAcct = New-AzStorageAccount -Name $storageName -ResourceGroupName $TestResourceGroupName -Location $Location -SkuName Standard_LRS -Kind StorageV2 -ErrorAction Stop
            Write-Host "    ✓ Created storage account $storageName for Private Endpoint target" -ForegroundColor Gray
        } catch {
            Write-Host "    ⚠ Could not create storage account for Private Endpoint: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Provision Tier 1 resources for modify/delete tests
        Write-Host "  → Provisioning Tier 1 test resources for modify/delete coverage..." -ForegroundColor Gray

        # NAT Gateway (requires public IP)
        $natGatewayName = "nat-test-existing-$UniqueSuffix"
        try {
            $natPipObj = Get-AzPublicIpAddress -Name "pip-nat-$UniqueSuffix" -ResourceGroupName $TestResourceGroupName -ErrorAction Stop
            $natGw = Get-AzNatGateway -Name $natGatewayName -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue
            if (-not $natGw) {
                $natGw = New-AzNatGateway -Name $natGatewayName -ResourceGroupName $TestResourceGroupName -Location $Location -PublicIpAddress $natPipObj -Sku Standard -IdleTimeoutInMinutes 4 -ErrorAction Stop
                Write-Host "    ✓ Created NAT Gateway $natGatewayName" -ForegroundColor Gray
            }
        } catch {
            Write-Host "    ⚠ Could not create NAT Gateway: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Traffic Manager Profile
        $trafficManagerName = "tm-test-existing-$UniqueSuffix"
        try {
            $tmProfile = Get-AzTrafficManagerProfile -Name $trafficManagerName -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue
            if (-not $tmProfile) {
                $tmProfile = New-AzTrafficManagerProfile -Name $trafficManagerName -ResourceGroupName $TestResourceGroupName -TrafficRoutingMethod Performance -RelativeDnsName "tm-test-$UniqueSuffix" -Ttl 30 -MonitorProtocol HTTP -MonitorPort 80 -MonitorPath "/" -ErrorAction Stop
                Write-Host "    ✓ Created Traffic Manager Profile $trafficManagerName" -ForegroundColor Gray
            }
        } catch {
            Write-Host "    ⚠ Could not create Traffic Manager Profile: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # IP Group (for Firewall rules)
        $ipGroupName = "ipgroup-test-existing-$UniqueSuffix"
        try {
            $ipGroup = Get-AzIpGroup -Name $ipGroupName -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue
            if (-not $ipGroup) {
                $ipGroup = New-AzIpGroup -Name $ipGroupName -ResourceGroupName $TestResourceGroupName -Location $Location -IpAddress @("10.0.0.0/24","192.168.1.0/24") -ErrorAction Stop
                Write-Host "    ✓ Created IP Group $ipGroupName" -ForegroundColor Gray
            }
        } catch {
            Write-Host "    ⚠ Could not create IP Group: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Service Endpoint Policy
        $serviceEndpointPolicyName = "sep-test-existing-$UniqueSuffix"
        try {
            $sepPolicy = Get-AzServiceEndpointPolicy -Name $serviceEndpointPolicyName -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue
            if (-not $sepPolicy) {
                $sepPolicy = New-AzServiceEndpointPolicy -Name $serviceEndpointPolicyName -ResourceGroupName $TestResourceGroupName -Location $Location -ErrorAction Stop
                Write-Host "    ✓ Created Service Endpoint Policy $serviceEndpointPolicyName" -ForegroundColor Gray
            }
        } catch {
            Write-Host "    ⚠ Could not create Service Endpoint Policy: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # Network Watcher (Azure allows only 1 per subscription per region; reuse if exists)
        $networkWatcherName = "nw-test-existing-$UniqueSuffix"
        $networkWatcherCreatedByUs = $false
        try {
            # First check if our named watcher exists in the RG
            $nwWatcher = Get-AzNetworkWatcher -Name $networkWatcherName -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue
            if (-not $nwWatcher) {
                # Check if ANY Network Watcher exists in this region across all RGs (Azure limit: 1/subscription/region)
                $allWatchers = Get-AzNetworkWatcher -ErrorAction SilentlyContinue | Where-Object { $_.Location -eq $Location }
                if ($allWatchers) {
                    # Reuse existing watcher from another RG
                    $nwWatcher = $allWatchers[0]
                    $networkWatcherName = $nwWatcher.Name
                    Write-Host "    ✓ Reusing existing Network Watcher '$networkWatcherName' (1/subscription/region limit)" -ForegroundColor Cyan
                    $networkWatcherCreatedByUs = $false
                } else {
                    # Safe to create new watcher
                    $nwWatcher = New-AzNetworkWatcher -Name $networkWatcherName -ResourceGroupName $TestResourceGroupName -Location $Location -ErrorAction Stop
                    Write-Host "    ✓ Created Network Watcher $networkWatcherName" -ForegroundColor Gray
                    $networkWatcherCreatedByUs = $true
                }
            } else {
                Write-Host "    ✓ Found existing Network Watcher $networkWatcherName" -ForegroundColor Gray
                $networkWatcherCreatedByUs = $true
            }
        } catch {
            Write-Host "    ⚠ Could not create Network Watcher: $($_.Exception.Message)" -ForegroundColor Yellow
            # Attempt fallback: use any existing watcher in region
            $allWatchers = Get-AzNetworkWatcher -ErrorAction SilentlyContinue | Where-Object { $_.Location -eq $Location }
            if ($allWatchers) {
                $nwWatcher = $allWatchers[0]
                $networkWatcherName = $nwWatcher.Name
                Write-Host "    ✓ Fallback: using existing Network Watcher '$networkWatcherName'" -ForegroundColor Cyan
                $networkWatcherCreatedByUs = $false
            }
        }

        # Firewall Policy
        $firewallPolicyName = "fwpol-test-existing-$UniqueSuffix"
        try {
            $fwPolicy = Get-AzFirewallPolicy -Name $firewallPolicyName -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue
            if (-not $fwPolicy) {
                $fwPolicy = New-AzFirewallPolicy -Name $firewallPolicyName -ResourceGroupName $TestResourceGroupName -Location $Location -ErrorAction Stop
                Write-Host "    ✓ Created Firewall Policy $firewallPolicyName" -ForegroundColor Gray
            }
        } catch {
            Write-Host "    ⚠ Could not create Firewall Policy: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        Write-Host "    ✓ Tier 1 resource provisioning completed" -ForegroundColor Gray

        # Capture subnet IDs for later tests
        $gatewaySubnetId    = ($existingVnet.Subnets | Where-Object { $_.Name -eq 'GatewaySubnet' }).Id
        $firewallSubnetId   = ($existingVnet.Subnets | Where-Object { $_.Name -eq 'AzureFirewallSubnet' }).Id
        $appGwSubnetId      = ($existingVnet.Subnets | Where-Object { $_.Name -eq 'AppGatewaySubnet' }).Id
        $defaultSubnetId    = ($existingVnet.Subnets | Where-Object { $_.Name -eq 'default' }).Id
        $peerVnetId         = $peerVnet.Id
        $gatewayPipId       = (Get-AzPublicIpAddress -Name "pip-gateway-$UniqueSuffix" -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue).Id
        $firewallPipId      = (Get-AzPublicIpAddress -Name "pip-firewall-$UniqueSuffix" -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue).Id
        $natPipId           = (Get-AzPublicIpAddress -Name "pip-nat-$UniqueSuffix" -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue).Id
        $appGwPipId         = (Get-AzPublicIpAddress -Name "pip-appgw-$UniqueSuffix" -ResourceGroupName $TestResourceGroupName -ErrorAction SilentlyContinue).Id
        $storageAcctId      = $storageAcct.Id

        # Store context
        $result.Context = @{
            SafetyPrompts = [bool]$SafetyPrompts
            SubscriptionId = $SubscriptionId
            ResourceGroupName = $TestResourceGroupName
            Location = $Location
            UniqueSuffix = $UniqueSuffix
            ServicePrincipalId = $sp.Id
            ServicePrincipalAppId = $sp.AppId
            ServicePrincipalSecret = $spSecret
            TenantId = (Get-AzContext).Tenant.Id
            CustomRoleName = $CustomRoleName
            ServicePrincipalCreatedByUs = $servicePrincipalCreatedByUs
            ServicePrincipalApplicationObjectId = $servicePrincipalAppObjectId
            ExistingVnetId = $existingVnet.Id
            PeerVnetId = $peerVnetId
            GatewaySubnetId = $gatewaySubnetId
            FirewallSubnetId = $firewallSubnetId
            AppGatewaySubnetId = $appGwSubnetId
            DefaultSubnetId = $defaultSubnetId
            GatewayPublicIpId = $gatewayPipId
            FirewallPublicIpId = $firewallPipId
            NatPublicIpId = $natPipId
            AppGatewayPublicIpId = $appGwPipId
            PrivateEndpointTargetId = $storageAcctId
            PrivateEndpointSubnetId = $defaultSubnetId
            NatGatewayName = $natGatewayName
            TrafficManagerProfileName = $trafficManagerName
            IpGroupName = $ipGroupName
            ServiceEndpointPolicyName = $serviceEndpointPolicyName
            NetworkWatcherName = $networkWatcherName
            NetworkWatcherCreatedByUs = $networkWatcherCreatedByUs
            NetworkWatcherId = if ($nwWatcher) { $nwWatcher.Id } else { $null }
            FirewallPolicyName = $firewallPolicyName
        }

        $result.Success = $true
        Write-Host "  ✓ Test environment initialized successfully" -ForegroundColor Green

    } catch {
        $result.Error = $_.Exception.Message
        Write-Host "  ✗ Setup failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    return $result
}
