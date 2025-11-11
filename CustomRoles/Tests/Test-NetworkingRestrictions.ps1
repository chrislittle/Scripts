<#
.SYNOPSIS
    Test networking restrictions

.DESCRIPTION
    Tests requirements #1-14: All networking-related restrictions

.PARAMETER Context
    Test context containing resource IDs and configuration

.PARAMETER SelectedRequirements
    Array of requirement numbers to test (1-14). If not specified, runs all tests.
#>

function Test-NetworkingRestrictions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,

        [Parameter(Mandatory = $false)]
        [int[]]$SelectedRequirements = @(1..14)
    )

    $results = @()

    Write-Host "  Testing networking restrictions..." -ForegroundColor Gray

    # Helper function to execute and log tests
    function Invoke-RBACTest {
        param(
            [string]$RequirementNumber,
            [string]$Category,
            [string]$Action,
            [string]$Operation,
            [scriptblock]$TestScript
        )

        $testStart = Get-Date
        $testResult = @{
            Requirement = $RequirementNumber
            Category = $Category
            Action = $Action
            Operation = $Operation
            ExpectedResult = "Denied"
            ActualResult = "Unknown"
            Status = "ERROR"
            ErrorMessage = ""
            Duration = ""
        }

        try {
            & $TestScript
            $testResult.ActualResult = "Allowed"
            $testResult.Status = "FAIL"
            $testResult.ErrorMessage = "Operation was not blocked as expected"
            Write-Host "    ✗ $Operation - FAIL (was allowed)" -ForegroundColor Red
        } catch {
            $errorMessage = $_.Exception.Message
            if ($errorMessage -like "*AuthorizationFailed*" -or 
                $errorMessage -like "*forbidden*" -or 
                $errorMessage -like "*does not have authorization*" -or
                $errorMessage -like "*insufficient privileges*") {
                $testResult.ActualResult = "Denied"
                $testResult.Status = "PASS"
                $testResult.ErrorMessage = "AuthorizationFailed (expected)"
                Write-Host "    ✓ $Operation - PASS" -ForegroundColor Green
            } else {
                $testResult.ActualResult = "Error"
                $testResult.Status = "ERROR"
                $testResult.ErrorMessage = $errorMessage
                Write-Host "    ⚠ $Operation - ERROR: $errorMessage" -ForegroundColor Yellow
            }
        }

        $testEnd = Get-Date
        $testResult.Duration = ($testEnd - $testStart).TotalSeconds.ToString("F2") + "s"
        return $testResult
    }

    # Helper to create a SKIPPED test result (for operations not reliably testable in ephemeral env)
    function New-SkippedResult {
        param(
            [string]$RequirementNumber,
            [string]$Category,
            [string]$Action,
            [string]$Operation,
            [string]$Reason
        )
        return @{
            Requirement    = $RequirementNumber
            Category       = $Category
            Action         = $Action
            Operation      = $Operation
            ExpectedResult = "Denied"
            ActualResult   = "Skipped"
            Status         = "SKIPPED"
            ErrorMessage   = $Reason
            Duration       = "0.00s"
        }
    }

    # ===== Requirement #1: Virtual Networks =====
    if ($SelectedRequirements -contains 1) {
        Write-Host "    [Req #1] Testing Virtual Network restrictions..." -ForegroundColor Cyan

    # Test 1.1: Create VNET
    $results += Invoke-RBACTest `
        -RequirementNumber "1" `
        -Category "Virtual Networks" `
        -Action "Microsoft.Network/virtualNetworks/write" `
        -Operation "New-AzVirtualNetwork" `
        -TestScript {
            New-AzVirtualNetwork `
                -Name "vnet-test-new" `
                -ResourceGroupName $Context.ResourceGroupName `
                -Location $Context.Location `
                -AddressPrefix "10.200.0.0/16" `
                -ErrorAction Stop | Out-Null
        }

    # Test 1.2: Modify existing VNET
    $results += Invoke-RBACTest `
        -RequirementNumber "1" `
        -Category "Virtual Networks" `
        -Action "Microsoft.Network/virtualNetworks/write" `
        -Operation "Set-AzVirtualNetwork (modify)" `
        -TestScript {
            $vnet = Get-AzVirtualNetwork -Name "vnet-test-existing" -ResourceGroupName $Context.ResourceGroupName -ErrorAction Stop
            Add-AzVirtualNetworkSubnet -Name "subnet-test" -VirtualNetwork $vnet -AddressPrefix "10.100.1.0/24" -ErrorAction Stop | Out-Null
            Set-AzVirtualNetwork -VirtualNetwork $vnet -ErrorAction Stop | Out-Null
        }

    # Test 1.3: Delete VNET
    $results += Invoke-RBACTest `
        -RequirementNumber "1" `
        -Category "Virtual Networks" `
        -Action "Microsoft.Network/virtualNetworks/delete" `
        -Operation "Remove-AzVirtualNetwork" `
        -TestScript {
            Remove-AzVirtualNetwork `
                -Name "vnet-test-existing" `
                -ResourceGroupName $Context.ResourceGroupName `
                -Force `
                -ErrorAction Stop | Out-Null
        }

    # Test 1.4: Create VNET Peering (using real peer VNet)
    $results += Invoke-RBACTest `
        -RequirementNumber "1" `
        -Category "Virtual Networks" `
        -Action "Microsoft.Network/virtualNetworks/virtualNetworkPeerings/write" `
        -Operation "Add-AzVirtualNetworkPeering" `
        -TestScript {
            $vnet1 = Get-AzVirtualNetwork -Name "vnet-test-existing" -ResourceGroupName $Context.ResourceGroupName -ErrorAction Stop
            Add-AzVirtualNetworkPeering `
                -Name "peer-test" `
                -VirtualNetwork $vnet1 `
                -RemoteVirtualNetworkId $Context.PeerVnetId `
                -ErrorAction Stop | Out-Null
        }
    }

    # ===== Requirement #2: ExpressRoute & VPN Gateways =====
    if ($SelectedRequirements -contains 2) {
        Write-Host "    [Req #2] Testing Gateway restrictions..." -ForegroundColor Cyan

    # Test 2.1: Create VPN Gateway (with prerequisite subnet & public IP)
    $results += Invoke-RBACTest `
        -RequirementNumber "2" `
        -Category "ExpressRoute & VPN Gateways" `
        -Action "Microsoft.Network/virtualNetworkGateways/write" `
        -Operation "New-AzVirtualNetworkGateway" `
        -TestScript {
            $ipConf = New-AzVirtualNetworkGatewayIpConfig -Name 'gwip' -SubnetId $Context.GatewaySubnetId -PublicIpAddressId $Context.GatewayPublicIpId
            New-AzVirtualNetworkGateway `
                -Name "vpn-gateway-test" `
                -ResourceGroupName $Context.ResourceGroupName `
                -Location $Context.Location `
                -IpConfigurations $ipConf `
                -GatewayType Vpn `
                -VpnType RouteBased `
                -GatewaySku VpnGw1 `
                -ErrorAction Stop | Out-Null
        }

    # Test 2.2: Create ExpressRoute Circuit (SKIPPED - requires pre-provisioned service key & provider infra)
    Write-Host "      ◦ Skipping ExpressRoute Circuit test (provider service key & physical connectivity not available in ephemeral test run)" -ForegroundColor DarkGray
    $results += New-SkippedResult `
        -RequirementNumber "2" `
        -Category "ExpressRoute & VPN Gateways" `
        -Action "Microsoft.Network/expressRouteCircuits/write" `
        -Operation "New-AzExpressRouteCircuit" `
        -Reason "Skipped: ExpressRoute circuit creation requires a valid service provider key and cannot be reliably tested in ephemeral environment."
    }

    # ===== Requirement #3: Route Tables =====
    if ($SelectedRequirements -contains 3) {
        Write-Host "    [Req #3] Testing Route Table restrictions..." -ForegroundColor Cyan

    # Test 3.1: Create Route Table
    $results += Invoke-RBACTest `
        -RequirementNumber "3" `
        -Category "Route Tables" `
        -Action "Microsoft.Network/routeTables/write" `
        -Operation "New-AzRouteTable" `
        -TestScript {
            New-AzRouteTable `
                -Name "rt-test-new" `
                -ResourceGroupName $Context.ResourceGroupName `
                -Location $Context.Location `
                -ErrorAction Stop | Out-Null
        }

    # Test 3.2: Modify Route Table (add route)
    $results += Invoke-RBACTest `
        -RequirementNumber "3" `
        -Category "Route Tables" `
        -Action "Microsoft.Network/routeTables/routes/write" `
        -Operation "Add-AzRouteConfig" `
        -TestScript {
            $routeTable = Get-AzRouteTable -Name "rt-test-existing" -ResourceGroupName $Context.ResourceGroupName -ErrorAction Stop
            Add-AzRouteConfig `
                -Name "route-test" `
                -RouteTable $routeTable `
                -AddressPrefix "10.0.0.0/8" `
                -NextHopType VirtualAppliance `
                -NextHopIpAddress "10.100.1.4" `
                -ErrorAction Stop | Out-Null
            Set-AzRouteTable -RouteTable $routeTable -ErrorAction Stop | Out-Null
        }

    # Test 3.3: Delete Route Table
    $results += Invoke-RBACTest `
        -RequirementNumber "3" `
        -Category "Route Tables" `
        -Action "Microsoft.Network/routeTables/delete" `
        -Operation "Remove-AzRouteTable" `
        -TestScript {
            Remove-AzRouteTable `
                -Name "rt-test-existing" `
                -ResourceGroupName $Context.ResourceGroupName `
                -Force `
                -ErrorAction Stop | Out-Null
        }
    }

    # ===== Requirement #4: Front Door & CDN =====
    if ($SelectedRequirements -contains 4) {
        Write-Host "    [Req #4] Testing Front Door & CDN restrictions..." -ForegroundColor Cyan

    # Test 4.1: Create Front Door
    $results += Invoke-RBACTest `
        -RequirementNumber "4" `
        -Category "Front Door & CDN" `
        -Action "Microsoft.Network/frontDoors/write" `
        -Operation "New-AzFrontDoor" `
        -TestScript {
            # Create health probe object
            $healthProbe = New-AzFrontDoorHealthProbeSettingObject `
                -Name "healthprobe1" `
                -Path "/" `
                -Protocol "Http" `
                -IntervalInSeconds 30 `
                -ErrorAction Stop
            
            # Create load balancing object
            $loadBalancing = New-AzFrontDoorLoadBalancingSettingObject `
                -Name "loadbalancing1" `
                -SampleSize 4 `
                -SuccessfulSamplesRequired 2 `
                -ErrorAction Stop
            
            # Create required backend object
            $backend = New-AzFrontDoorBackendObject `
                -Address "www.contoso.com" `
                -HttpPort 80 `
                -HttpsPort 443 `
                -Priority 1 `
                -Weight 50 `
                -ErrorAction Stop
            
            $backendPool = New-AzFrontDoorBackendPoolObject `
                -Name "backendpool1" `
                -ResourceGroupName $Context.ResourceGroupName `
                -FrontDoorName "frontdoor-test-rbac" `
                -Backend $backend `
                -HealthProbeSettingsName "healthprobe1" `
                -LoadBalancingSettingsName "loadbalancing1" `
                -ErrorAction Stop
            
            # Create frontend endpoint object
            $frontendEndpoint = New-AzFrontDoorFrontendEndpointObject `
                -Name "frontendendpoint1" `
                -HostName "frontdoor-test-rbac.azurefd.net" `
                -ErrorAction Stop
            
            # Create required routing rule object
            $routingRule = New-AzFrontDoorRoutingRuleObject `
                -Name "routingrule1" `
                -FrontDoorName "frontdoor-test-rbac" `
                -ResourceGroupName $Context.ResourceGroupName `
                -FrontendEndpointName "frontendendpoint1" `
                -BackendPoolName "backendpool1" `
                -ErrorAction Stop
            
            # Create Front Door with all required objects
            New-AzFrontDoor `
                -Name "frontdoor-test-rbac" `
                -ResourceGroupName $Context.ResourceGroupName `
                -RoutingRule $routingRule `
                -BackendPool $backendPool `
                -FrontendEndpoint $frontendEndpoint `
                -HealthProbeSetting $healthProbe `
                -LoadBalancingSetting $loadBalancing `
                -ErrorAction Stop | Out-Null
        }

    # Test 4.2: Create CDN Profile (used by Front Door)
    $results += Invoke-RBACTest `
        -RequirementNumber "4" `
        -Category "Front Door" `
        -Action "Microsoft.Cdn/profiles/write" `
        -Operation "New-AzCdnProfile" `
        -TestScript {
            New-AzCdnProfile `
                -ProfileName "cdn-test" `
                -ResourceGroupName $Context.ResourceGroupName `
                -Location $Context.Location `
                -Sku Standard_Microsoft `
                -ErrorAction Stop | Out-Null
        }
    }

    # ===== Requirement #5: Load Balancers =====
    if ($SelectedRequirements -contains 5) {
        Write-Host "    [Req #5] Testing Load Balancer restrictions..." -ForegroundColor Cyan

    # Test 5.1: Create Load Balancer (using existing subnet)
    $results += Invoke-RBACTest `
        -RequirementNumber "5" `
        -Category "Load Balancers" `
        -Action "Microsoft.Network/loadBalancers/write" `
        -Operation "New-AzLoadBalancer" `
        -TestScript {
            $frontendIP = New-AzLoadBalancerFrontendIpConfig -Name "fe-test" -PrivateIpAddress "10.100.1.10" -SubnetId $Context.DefaultSubnetId
            New-AzLoadBalancer `
                -Name "lb-test" `
                -ResourceGroupName $Context.ResourceGroupName `
                -Location $Context.Location `
                -FrontendIpConfiguration $frontendIP `
                -ErrorAction Stop | Out-Null
        }

    # Test 5.2: Create Application Gateway (minimal config)
    $results += Invoke-RBACTest `
        -RequirementNumber "5" `
        -Category "Load Balancers" `
        -Action "Microsoft.Network/applicationGateways/write" `
        -Operation "New-AzApplicationGateway" `
        -TestScript {
            $feIp = New-AzApplicationGatewayFrontendIPConfig -Name feip -PublicIPAddressId $Context.AppGatewayPublicIpId
            $gwSubnet = $Context.AppGatewaySubnetId
            $gatewayIpConfig = New-AzApplicationGatewayIPConfiguration -Name gwipc -SubnetId $gwSubnet
            $backendPool = New-AzApplicationGatewayBackendAddressPool -Name bepool
            $frontendPort = New-AzApplicationGatewayFrontendPort -Name feport -Port 80
            $probe = New-AzApplicationGatewayProbeConfig -Name probe -Protocol Http -Path '/' -Interval 30 -Timeout 30 -UnhealthyThreshold 3 -Port 80
            $httpSetting = New-AzApplicationGatewayBackendHttpSetting -Name setting -Port 80 -Protocol Http -CookieBasedAffinity Disabled -PickHostNameFromBackendAddress:$false -RequestTimeout 30 -Probe $probe
            $listener = New-AzApplicationGatewayHttpListener -Name listener -FrontendIpConfiguration $feIp -FrontendPort $frontendPort -Protocol Http
            $rule = New-AzApplicationGatewayRequestRoutingRule -Name rule1 -RuleType Basic -HttpListener $listener -BackendAddressPool $backendPool -BackendHttpSettings $httpSetting
            # Build SKU object explicitly to avoid type conversion issues
            $appGwSku = New-Object -TypeName Microsoft.Azure.Commands.Network.Models.PSApplicationGatewaySku
            $appGwSku.Name = 'Standard_v2'
            $appGwSku.Tier = 'Standard_v2'
            $appGwSku.Capacity = 1
            New-AzApplicationGateway -Name "appgw-test" -ResourceGroupName $Context.ResourceGroupName -Location $Context.Location -Sku $appGwSku -GatewayIpConfiguration $gatewayIpConfig -FrontendIpConfiguration $feIp -FrontendPort $frontendPort -BackendAddressPools $backendPool -BackendHttpSettingsCollection $httpSetting -HttpListeners $listener -RequestRoutingRules $rule -Probes $probe -ErrorAction Stop | Out-Null
        }
    }

    # ===== Requirement #6: Private Link & Endpoints =====
    if ($SelectedRequirements -contains 6) {
        Write-Host "    [Req #6] Testing Private Link restrictions..." -ForegroundColor Cyan

    # Test 6.1: Create Private Endpoint (with target storage account)
    $results += Invoke-RBACTest `
        -RequirementNumber "6" `
        -Category "Private Link & Private Endpoints" `
        -Action "Microsoft.Network/privateEndpoints/write" `
        -Operation "New-AzPrivateEndpoint" `
        -TestScript {
            $subnet = Get-AzVirtualNetworkSubnetConfig -ResourceId $Context.PrivateEndpointSubnetId -ErrorAction Stop
            $conn = New-AzPrivateLinkServiceConnection -Name pelink -PrivateLinkServiceId $Context.PrivateEndpointTargetId -GroupId @('blob')
            New-AzPrivateEndpoint -Name "pe-test" -ResourceGroupName $Context.ResourceGroupName -Location $Context.Location -Subnet $subnet -PrivateLinkServiceConnection $conn -ErrorAction Stop | Out-Null
        }

    # Test 6.2: Create Private Link Service
    $results += Invoke-RBACTest `
        -RequirementNumber "6" `
        -Category "Private Link" `
        -Action "Microsoft.Network/privateLinkServices/write" `
        -Operation "New-AzPrivateLinkService" `
        -TestScript {
            $plsSubnet = Get-AzVirtualNetworkSubnetConfig -ResourceId $Context.PrivateEndpointSubnetId -ErrorAction Stop
            $plsIpConfig = New-AzPrivateLinkServiceIpConfig -Name "plsip" -PrivateIpAddress "10.100.1.10" -Subnet $plsSubnet
            New-AzPrivateLinkService `
                -Name "pls-test" `
                -ResourceGroupName $Context.ResourceGroupName `
                -Location $Context.Location `
                -IpConfiguration $plsIpConfig `
                -LoadBalancerFrontendIpConfiguration @() `
                -ErrorAction Stop | Out-Null
        }
    }

    # ===== Requirement #7: NAT Gateways =====
    if ($SelectedRequirements -contains 7) {
        Write-Host "    [Req #7] Testing NAT Gateway restrictions..." -ForegroundColor Cyan

    # Test 7.1: Create NAT Gateway (new resource)
    $results += Invoke-RBACTest `
        -RequirementNumber "7" `
        -Category "NAT Gateway" `
        -Action "Microsoft.Network/natGateways/write" `
        -Operation "New-AzNatGateway (create new)" `
        -TestScript {
            # Resolve Public IP by name/RG instead of -ResourceId (not available in current Az module version)
            $natPipId = $Context.NatPublicIpId
            if ($natPipId -match '/resourceGroups/([^/]+)/') { $natRg = $Matches[1] }
            if ($natPipId -match '/publicIPAddresses/([^/]+)$') { $natPipName = $Matches[1] }
            $natPublicIp = Get-AzPublicIpAddress -Name $natPipName -ResourceGroupName $natRg -ErrorAction Stop
            New-AzNatGateway -Name "nat-test-NEW-$($Context.UniqueSuffix)" -ResourceGroupName $Context.ResourceGroupName -Location $Context.Location -PublicIpAddress $natPublicIp -Sku Standard -ErrorAction Stop | Out-Null
        }

    # Test 7.2: Modify NAT Gateway (existing resource)
    $results += Invoke-RBACTest `
        -RequirementNumber "7" `
        -Category "NAT Gateway" `
        -Action "Microsoft.Network/natGateways/write" `
        -Operation "Set-AzNatGateway (modify existing)" `
        -TestScript {
            $natGw = Get-AzNatGateway -Name $Context.NatGatewayName -ResourceGroupName $Context.ResourceGroupName -ErrorAction Stop
            $natGw.IdleTimeoutInMinutes = 10
            Set-AzNatGateway -NatGateway $natGw -ErrorAction Stop | Out-Null
        }

    # Test 7.3: Delete NAT Gateway (existing resource)
    $results += Invoke-RBACTest `
        -RequirementNumber "7" `
        -Category "NAT Gateway" `
        -Action "Microsoft.Network/natGateways/delete" `
        -Operation "Remove-AzNatGateway" `
        -TestScript {
            Remove-AzNatGateway -Name $Context.NatGatewayName -ResourceGroupName $Context.ResourceGroupName -Force -ErrorAction Stop | Out-Null
        }
    }

    # ===== Requirement #8: Network Watcher =====
    if ($SelectedRequirements -contains 8) {
        Write-Host "    [Req #8] Testing Network Watcher restrictions..." -ForegroundColor Cyan

    # Test 8.1: Create Network Watcher (new resource)
    $results += Invoke-RBACTest `
        -RequirementNumber "8" `
        -Category "Network Watcher Tools" `
        -Action "Microsoft.Network/networkWatchers/write" `
        -Operation "New-AzNetworkWatcher (create new)" `
        -TestScript {
            New-AzNetworkWatcher `
                -Name "nw-test-NEW-$($Context.UniqueSuffix)" `
                -ResourceGroupName $Context.ResourceGroupName `
                -Location $Context.Location `
                -ErrorAction Stop | Out-Null
        }

    # Test 8.2: Modify Network Watcher (existing resource - tags only)
    $results += Invoke-RBACTest `
        -RequirementNumber "8" `
        -Category "Network Watcher Tools" `
        -Action "Microsoft.Network/networkWatchers/write" `
        -Operation "Set-AzNetworkWatcher (modify existing)" `
        -TestScript {
            $nwWatcher = Get-AzNetworkWatcher -Name $Context.NetworkWatcherName -ResourceGroupName $Context.ResourceGroupName -ErrorAction Stop
            $nwWatcher.Tag = @{ "TestTag" = "Modified" }
            Set-AzNetworkWatcher -NetworkWatcher $nwWatcher -ErrorAction Stop | Out-Null
        }

    # Test 8.3: Delete Network Watcher (generic resource delete; skip if reused)
    if ($Context.NetworkWatcherCreatedByUs -and $Context.NetworkWatcherId) {
        $results += Invoke-RBACTest `
            -RequirementNumber "8" `
            -Category "Network Watcher Tools" `
            -Action "Microsoft.Network/networkWatchers/delete" `
            -Operation "Remove-AzResource (network watcher delete)" `
            -TestScript {
                Remove-AzResource -ResourceId $Context.NetworkWatcherId -Force -ErrorAction Stop | Out-Null
            }
    } else {
        Write-Host "    ⧗ Skipping Network Watcher delete test (existing watcher reused; cannot safely delete)" -ForegroundColor DarkGray
        $results += @{
            Requirement = "8"
            Category = "Network Watcher Tools"
            Action = "Microsoft.Network/networkWatchers/delete"
            Operation = "Remove-AzResource (network watcher delete)"
            ExpectedResult = "SKIPPED"
            ActualResult = "SKIPPED"
            Status = "SKIPPED"
            ErrorMessage = "Reused existing Network Watcher from outside test RG; deletion skipped to avoid impacting diagnostics"
            Duration = "0.00s"
        }
    }
    }

    # ===== Requirement #9: Service Endpoints =====
    if ($SelectedRequirements -contains 9) {
        Write-Host "    [Req #9] Testing Service Endpoint restrictions..." -ForegroundColor Cyan

    # Test 9.1: Create Service Endpoint Policy (new resource)
    $results += Invoke-RBACTest `
        -RequirementNumber "9" `
        -Category "Service Endpoints" `
        -Action "Microsoft.Network/serviceEndpointPolicies/write" `
        -Operation "New-AzServiceEndpointPolicy (create new)" `
        -TestScript {
            New-AzServiceEndpointPolicy `
                -Name "sep-test-NEW-$($Context.UniqueSuffix)" `
                -ResourceGroupName $Context.ResourceGroupName `
                -Location $Context.Location `
                -ErrorAction Stop | Out-Null
        }

    # Test 9.2: Modify Service Endpoint Policy (existing resource - add definition)
    $results += Invoke-RBACTest `
        -RequirementNumber "9" `
        -Category "Service Endpoints" `
        -Action "Microsoft.Network/serviceEndpointPolicies/write" `
        -Operation "Set-AzServiceEndpointPolicy (modify existing)" `
        -TestScript {
            $sepPolicy = Get-AzServiceEndpointPolicy -Name $Context.ServiceEndpointPolicyName -ResourceGroupName $Context.ResourceGroupName -ErrorAction Stop
            $sepPolicy.Tag = @{ "Environment" = "Test" }
            Set-AzServiceEndpointPolicy -ServiceEndpointPolicy $sepPolicy -ErrorAction Stop | Out-Null
        }

    # Test 9.3: Delete Service Endpoint Policy (existing resource)
    $results += Invoke-RBACTest `
        -RequirementNumber "9" `
        -Category "Service Endpoints" `
        -Action "Microsoft.Network/serviceEndpointPolicies/delete" `
        -Operation "Remove-AzServiceEndpointPolicy" `
        -TestScript {
            Remove-AzServiceEndpointPolicy -Name $Context.ServiceEndpointPolicyName -ResourceGroupName $Context.ResourceGroupName -Force -ErrorAction Stop | Out-Null
        }
    }

    # ===== Requirement #10: Virtual WAN =====
    if ($SelectedRequirements -contains 10) {
        Write-Host "    [Req #10] Testing Virtual WAN restrictions (create-only)..." -ForegroundColor Cyan

        # Test 10.1: Create Virtual WAN (new resource) - create-only test
        $results += Invoke-RBACTest `
            -RequirementNumber "10" `
            -Category "Virtual WAN" `
            -Action "Microsoft.Network/virtualWans/write" `
            -Operation "New-AzVirtualWan (create test)" `
            -TestScript {
                New-AzVirtualWan `
                    -Name "vwan-test-NEW-$($Context.UniqueSuffix)" `
                    -ResourceGroupName $Context.ResourceGroupName `
                    -Location $Context.Location `
                    -ErrorAction Stop | Out-Null
            }

        # Note: Virtual Hub create test removed due to hard dependency on Virtual WAN
        # (cannot create hub without valid WAN object; WAN creation expected to be denied)
    }


    # ===== Requirement #11: Traffic Manager =====
    if ($SelectedRequirements -contains 11) {
        Write-Host "    [Req #11] Testing Traffic Manager restrictions..." -ForegroundColor Cyan

    # Test 11.1: Create Traffic Manager Profile (new resource)
    $results += Invoke-RBACTest `
        -RequirementNumber "11" `
        -Category "Traffic Manager" `
        -Action "Microsoft.Network/trafficManagerProfiles/write" `
        -Operation "New-AzTrafficManagerProfile (create new)" `
        -TestScript {
            New-AzTrafficManagerProfile `
                -Name "tm-test-NEW-$($Context.UniqueSuffix)" `
                -ResourceGroupName $Context.ResourceGroupName `
                -TrafficRoutingMethod Performance `
                -RelativeDnsName "tm-test-NEW-$($Context.UniqueSuffix)" `
                -Ttl 30 `
                -MonitorProtocol HTTP `
                -MonitorPort 80 `
                -MonitorPath "/" `
                -ErrorAction Stop | Out-Null
        }

    # Test 11.2: Modify Traffic Manager Profile (existing resource - change TTL)
    $results += Invoke-RBACTest `
        -RequirementNumber "11" `
        -Category "Traffic Manager" `
        -Action "Microsoft.Network/trafficManagerProfiles/write" `
        -Operation "Set-AzTrafficManagerProfile (modify existing)" `
        -TestScript {
            $tmProfile = Get-AzTrafficManagerProfile -Name $Context.TrafficManagerProfileName -ResourceGroupName $Context.ResourceGroupName -ErrorAction Stop
            $tmProfile.Ttl = 60
            Set-AzTrafficManagerProfile -TrafficManagerProfile $tmProfile -ErrorAction Stop | Out-Null
        }

    # Test 11.3: Delete Traffic Manager Profile (existing resource)
    $results += Invoke-RBACTest `
        -RequirementNumber "11" `
        -Category "Traffic Manager" `
        -Action "Microsoft.Network/trafficManagerProfiles/delete" `
        -Operation "Remove-AzTrafficManagerProfile" `
        -TestScript {
            Remove-AzTrafficManagerProfile -Name $Context.TrafficManagerProfileName -ResourceGroupName $Context.ResourceGroupName -Force -ErrorAction Stop | Out-Null
        }
    }

    # ===== Requirement #12: Virtual Network Tap =====
    if ($SelectedRequirements -contains 12) {
        Write-Host "    [Req #12] Testing Virtual Network Tap restrictions..." -ForegroundColor Cyan

    # Test 12.1: Create Virtual Network Tap (SKIPPED - requires packet capture target configuration)
    Write-Host "      ◦ Skipping Virtual Network Tap test (no target NIC/VM provisioned for tap session)" -ForegroundColor DarkGray
    $results += New-SkippedResult `
        -RequirementNumber "12" `
        -Category "Virtual Network Tap" `
        -Action "Microsoft.Network/virtualNetworkTaps/write" `
        -Operation "New-AzVirtualNetworkTap" `
        -Reason "Skipped: Virtual Network Tap requires a supported target (NIC or VM) and capture config not provisioned in test scope."
    }

    # ===== Requirement #13: Azure Firewall =====
    if ($SelectedRequirements -contains 13) {
        Write-Host "    [Req #13] Testing Azure Firewall restrictions..." -ForegroundColor Cyan

    # Test 13.1: Create Azure Firewall (new resource - with subnet & public IP)
    $results += Invoke-RBACTest `
        -RequirementNumber "13" `
        -Category "Azure Firewall" `
        -Action "Microsoft.Network/azureFirewalls/write" `
        -Operation "New-AzFirewall (create new)" `
        -TestScript {
            # Resolve firewall Public IP without using -ResourceId (not available in current Az module version)
            $fwPipId = $Context.FirewallPublicIpId
            if ($fwPipId -match '/resourceGroups/([^/]+)/') { $fwRg = $Matches[1] }
            if ($fwPipId -match '/publicIPAddresses/([^/]+)$') { $fwPipName = $Matches[1] }
            $fwPublicIp = Get-AzPublicIpAddress -Name $fwPipName -ResourceGroupName $fwRg -ErrorAction Stop
            New-AzFirewall -Name "fw-test-NEW-$($Context.UniqueSuffix)" -ResourceGroupName $Context.ResourceGroupName -Location $Context.Location -VirtualNetworkName "vnet-test-existing-$($Context.UniqueSuffix)" -PublicIpAddress $fwPublicIp -SkuName AZFW_VNet -SkuTier Standard -ErrorAction Stop | Out-Null
        }

    # Test 13.2: Create Firewall Policy (new resource)
    $results += Invoke-RBACTest `
        -RequirementNumber "13" `
        -Category "Azure Firewall" `
        -Action "Microsoft.Network/firewallPolicies/write" `
        -Operation "New-AzFirewallPolicy (create new)" `
        -TestScript {
            New-AzFirewallPolicy `
                -Name "fwpol-test-NEW-$($Context.UniqueSuffix)" `
                -ResourceGroupName $Context.ResourceGroupName `
                -Location $Context.Location `
                -ErrorAction Stop | Out-Null
        }

    # Test 13.3: Modify Firewall Policy (existing resource - add rule collection group)
    $results += Invoke-RBACTest `
        -RequirementNumber "13" `
        -Category "Azure Firewall" `
        -Action "Microsoft.Network/firewallPolicies/write" `
        -Operation "Set-AzFirewallPolicy (modify existing)" `
        -TestScript {
            $fwPolicy = Get-AzFirewallPolicy -Name $Context.FirewallPolicyName -ResourceGroupName $Context.ResourceGroupName -ErrorAction Stop
            $fwPolicy.Tag = @{ "UpdatedBy" = "RBACTest" }
            Set-AzFirewallPolicy -InputObject $fwPolicy -ErrorAction Stop | Out-Null
        }

    # Test 13.4: Delete Firewall Policy (existing resource)
    $results += Invoke-RBACTest `
        -RequirementNumber "13" `
        -Category "Azure Firewall" `
        -Action "Microsoft.Network/firewallPolicies/delete" `
        -Operation "Remove-AzFirewallPolicy" `
        -TestScript {
            Remove-AzFirewallPolicy -Name $Context.FirewallPolicyName -ResourceGroupName $Context.ResourceGroupName -Force -ErrorAction Stop | Out-Null
        }

    # Test 13.5: Create IP Group (new resource)
    $results += Invoke-RBACTest `
        -RequirementNumber "13" `
        -Category "Azure Firewall" `
        -Action "Microsoft.Network/ipGroups/write" `
        -Operation "New-AzIpGroup (create new)" `
        -TestScript {
            New-AzIpGroup `
                -Name "ipgroup-test-NEW-$($Context.UniqueSuffix)" `
                -ResourceGroupName $Context.ResourceGroupName `
                -Location $Context.Location `
                -IpAddress @("10.1.0.0/24") `
                -ErrorAction Stop | Out-Null
        }

    # Test 13.6: Modify IP Group (existing resource - update IP ranges)
    $results += Invoke-RBACTest `
        -RequirementNumber "13" `
        -Category "Azure Firewall" `
        -Action "Microsoft.Network/ipGroups/write" `
        -Operation "Set-AzIpGroup (modify existing)" `
        -TestScript {
            $ipGroup = Get-AzIpGroup -Name $Context.IpGroupName -ResourceGroupName $Context.ResourceGroupName -ErrorAction Stop
            $ipGroup.IpAddresses = @("10.0.0.0/24", "192.168.1.0/24", "172.16.0.0/16")
            Set-AzIpGroup -InputObject $ipGroup -ErrorAction Stop | Out-Null
        }

    # Test 13.7: Delete IP Group (existing resource)
    $results += Invoke-RBACTest `
        -RequirementNumber "13" `
        -Category "Azure Firewall" `
        -Action "Microsoft.Network/ipGroups/delete" `
        -Operation "Remove-AzIpGroup" `
        -TestScript {
            Remove-AzIpGroup -Name $Context.IpGroupName -ResourceGroupName $Context.ResourceGroupName -Force -ErrorAction Stop | Out-Null
        }
    }

    # ===== Requirement #14: DDoS Protection =====
    if ($SelectedRequirements -contains 14) {
        Write-Host "    [Req #14] Testing DDoS Protection Plan restrictions (create-only)..." -ForegroundColor Cyan
        $results += Invoke-RBACTest `
            -RequirementNumber "14" `
            -Category "DDoS Protection" `
            -Action "Microsoft.Network/ddosProtectionPlans/write" `
            -Operation "New-AzDdosProtectionPlan (create test)" `
            -TestScript {
                New-AzDdosProtectionPlan `
                    -Name "ddos-test" `
                    -ResourceGroupName $Context.ResourceGroupName `
                    -Location $Context.Location `
                    -ErrorAction Stop | Out-Null
            }
    }

    Write-Host "  ✓ Networking tests completed" -ForegroundColor Green
    return $results
}
