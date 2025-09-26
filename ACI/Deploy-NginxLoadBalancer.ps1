#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Deploys the Nginx Load Balancer ARM template and configures the backend pool

.DESCRIPTION
    This script deploys an ARM template that creates:
    - A virtual network with separate subnets for load balancer and container instances
    - An internal standard load balancer
    - An Azure Container Instance running nginx with a default web page
    - Configures the load balancer backend pool with the container instance

.PARAMETER ResourceGroupName
    The name of the resource group where resources will be deployed

.PARAMETER Location
    The Azure region where resources will be deployed (default: East US)

.PARAMETER ResourcePrefix
    Prefix for all resource names (default: nginx-lb)

.EXAMPLE
    .\Deploy-NginxLoadBalancer.ps1 -ResourceGroupName "rg-nginx-test" -Location "East US"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroupName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "East US",
    
    [Parameter(Mandatory=$false)]
    [string]$ResourcePrefix = "nginx-lb"
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Function to write colored output
function Write-ColorOutput([string]$Message, [string]$Color = "White") {
    Write-Host $Message -ForegroundColor $Color
}

Write-ColorOutput "=== Nginx Load Balancer Deployment Script ===" "Cyan"
Write-ColorOutput "Resource Group: $ResourceGroupName" "Yellow"
Write-ColorOutput "Location: $Location" "Yellow"
Write-ColorOutput "Resource Prefix: $ResourcePrefix" "Yellow"

try {
    # Check if Azure PowerShell is installed
    if (!(Get-Module -ListAvailable -Name Az)) {
        Write-ColorOutput "Azure PowerShell (Az module) is not installed. Please install it first." "Red"
        Write-ColorOutput "Run: Install-Module -Name Az -AllowClobber -Scope CurrentUser" "Yellow"
        exit 1
    }

    # Check if logged in to Azure
    $context = Get-AzContext
    if (!$context) {
        Write-ColorOutput "Not logged in to Azure. Please login first." "Red"
        Write-ColorOutput "Run: Connect-AzAccount" "Yellow"
        exit 1
    }

    Write-ColorOutput "Current Azure Context:" "Green"
    Write-ColorOutput "Subscription: $($context.Subscription.Name) ($($context.Subscription.Id))" "White"
    Write-ColorOutput "Account: $($context.Account.Id)" "White"

    # Create resource group if it doesn't exist
    Write-ColorOutput "`nChecking resource group..." "Green"
    $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
    if (!$rg) {
        Write-ColorOutput "Creating resource group: $ResourceGroupName" "Yellow"
        $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location
        Write-ColorOutput "Resource group created successfully." "Green"
    } else {
        Write-ColorOutput "Resource group already exists." "Green"
    }

    # Deploy ARM template
    Write-ColorOutput "`nDeploying ARM template..." "Green"
    $templatePath = Join-Path $PSScriptRoot "nginx-loadbalancer-template.json"
    
    if (!(Test-Path $templatePath)) {
        Write-ColorOutput "ARM template not found at: $templatePath" "Red"
        exit 1
    }

    $deploymentName = "Nginx-LB-Deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    
    $deployment = New-AzResourceGroupDeployment `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile $templatePath `
        -Name $deploymentName `
        -resourcePrefix $ResourcePrefix `
        -location $Location `
        -Verbose

    if ($deployment.ProvisioningState -eq "Succeeded") {
        Write-ColorOutput "ARM template deployed successfully!" "Green"
        
        # Extract outputs
        $outputs = $deployment.Outputs
        $loadBalancerName = $outputs.loadBalancerName.Value
        $containerGroupName = $outputs.containerGroupName.Value
        $vnetName = $outputs.vnetName.Value
        $bastionName = $outputs.bastionName.Value
        $natGatewayName = $outputs.natGatewayName.Value
        
        Write-ColorOutput "`nDeployment Outputs:" "Cyan"
        Write-ColorOutput "Load Balancer Name: $loadBalancerName" "White"
        Write-ColorOutput "Container Group Name: $containerGroupName" "White"
        Write-ColorOutput "VNet Name: $vnetName" "White"
        Write-ColorOutput "Bastion Name: $bastionName" "White"
        Write-ColorOutput "NAT Gateway Name: $natGatewayName" "White"

        # Wait for container to get IP address
        Write-ColorOutput "`nWaiting for container to get IP address..." "Yellow"
        $maxRetries = 30
        $retryCount = 0
        $containerIP = $null

        do {
            Start-Sleep -Seconds 10
            $retryCount++
            Write-ColorOutput "Attempt $retryCount of $maxRetries..." "Gray"
            
            try {
                $containerGroup = Get-AzContainerGroup -ResourceGroupName $ResourceGroupName -Name $containerGroupName -ErrorAction SilentlyContinue
                if ($containerGroup -and $containerGroup.IPAddressIP) {
                    $containerIP = $containerGroup.IPAddressIP
                    Write-ColorOutput "Container IP found: $containerIP" "Green"
                    break
                }
            }
            catch {
                Write-ColorOutput "Error getting container IP: $($_.Exception.Message)" "Red"
            }
        } while ($retryCount -lt $maxRetries)

        if (!$containerIP) {
            Write-ColorOutput "Failed to get container IP address after $maxRetries attempts." "Red"
            Write-ColorOutput "You may need to manually add the container to the backend pool later." "Yellow"
        } else {
            # Add container to backend pool using Azure CLI (more reliable than PowerShell for this operation)
            Write-ColorOutput "`nAdding container to load balancer backend pool..." "Green"
            
            try {
                # Check if Azure CLI is available first (most reliable method)
                $azCliCheck = Get-Command az -ErrorAction SilentlyContinue
                if ($azCliCheck) {
                    # Method 1: Use Azure CLI (recommended)
                    Write-ColorOutput "Using Azure CLI for backend pool configuration..." "Cyan"
                    
                    $azCommand = "az network lb address-pool address add --resource-group `"$ResourceGroupName`" --lb-name `"$loadBalancerName`" --pool-name `"BackendPool`" --name `"nginx-aci`" --vnet `"$vnetName`" --ip-address `"$containerIP`""
                    
                    Write-ColorOutput "Executing: $azCommand" "Gray"
                    
                    $result = Invoke-Expression $azCommand 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-ColorOutput "Container successfully added to backend pool!" "Green"
                        
                        # Verify the backend pool contains the container
                        Write-ColorOutput "Verifying backend pool configuration..." "Yellow"
                        $verifyCommand = "az network lb address-pool show --resource-group `"$ResourceGroupName`" --lb-name `"$loadBalancerName`" --name `"BackendPool`" --query `"loadBalancerBackendAddresses[].ipAddress`" --output tsv"
                        $backendIPs = Invoke-Expression $verifyCommand 2>&1
                        
                        if ($backendIPs -contains $containerIP) {
                            Write-ColorOutput "✓ Backend pool verification successful - container IP found: $containerIP" "Green"
                        } else {
                            Write-ColorOutput "⚠ Backend pool verification failed - container IP not found in pool" "Yellow"
                            Write-ColorOutput "Backend pool IPs: $backendIPs" "Gray"
                        }
                    } else {
                        throw "Azure CLI command failed with exit code: $LASTEXITCODE. Output: $result"
                    }
                } else {
                    # Method 2: Use PowerShell Az module (fallback)
                    Write-ColorOutput "Azure CLI not available, using PowerShell Az module..." "Cyan"
                    
                    # Get the load balancer
                    $loadBalancer = Get-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $loadBalancerName
                    $backendPool = $loadBalancer.BackendAddressPools | Where-Object {$_.Name -eq "BackendPool"}
                    
                    if (!$backendPool) {
                        throw "Backend pool 'BackendPool' not found in load balancer"
                    }
                    
                    # Check if container is already in the pool
                    $existingAddress = $backendPool.LoadBalancerBackendAddresses | Where-Object {$_.IpAddress -eq $containerIP}
                    if ($existingAddress) {
                        Write-ColorOutput "Container IP already exists in backend pool" "Green"
                    } else {
                        # Get the VNet for the backend address
                        $vnet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $vnetName
                        
                        # Create the backend address using Add-AzLoadBalancerBackendAddressConfig
                        $updatedLB = Add-AzLoadBalancerBackendAddressConfig `
                            -LoadBalancer $loadBalancer `
                            -Name "nginx-aci" `
                            -IpAddress $containerIP `
                            -VirtualNetworkId $vnet.Id
                        
                        # Apply the changes
                        Set-AzLoadBalancer -LoadBalancer $updatedLB | Out-Null
                        
                        Write-ColorOutput "Container successfully added to backend pool using PowerShell!" "Green"
                    }
                }
            }
            catch {
                Write-ColorOutput "Error adding container to backend pool: $($_.Exception.Message)" "Red"
                Write-ColorOutput "`nManual steps to add container to backend pool:" "Yellow"
                Write-ColorOutput "Option 1 - Using Azure CLI:" "White"
                Write-ColorOutput "1. Ensure you're logged into Azure CLI: az login" "White"
                Write-ColorOutput "2. Run: az network lb address-pool address add -g $ResourceGroupName --lb-name $loadBalancerName --pool-name BackendPool --name nginx-aci --vnet $vnetName --ip-address $containerIP" "Cyan"
                Write-ColorOutput "`nOption 2 - Using Azure Portal:" "White"
                Write-ColorOutput "1. Navigate to the Load Balancer resource in Azure Portal" "White"
                Write-ColorOutput "2. Go to 'Backend pools' -> 'BackendPool'" "White"
                Write-ColorOutput "3. Click 'Add' and enter the container IP: $containerIP" "White"
                Write-ColorOutput "4. Select the VNet and save the configuration" "White"
            }
        }

        # Display final information
        Write-ColorOutput "`n=== Deployment Complete ===" "Cyan"
        Write-ColorOutput "Load Balancer Private IP: $($outputs.loadBalancerPrivateIP.Value)" "Green"
        Write-ColorOutput "Container Group IP: $containerIP" "Green"
        Write-ColorOutput "Windows Server VM Name: $($outputs.vmName.Value)" "Green"
        Write-ColorOutput "Windows Server VM Private IP: $($outputs.vmPrivateIP.Value)" "Green"
        Write-ColorOutput "Bastion Public IP: $($outputs.bastionPublicIP.Value)" "Green"
        Write-ColorOutput "NAT Gateway Public IP: $($outputs.natGatewayPublicIP.Value)" "Green"
        Write-ColorOutput "`nTo test the deployment:" "Yellow"
        Write-ColorOutput "1. Use Azure Bastion to connect to the Windows Server VM" "White"
        Write-ColorOutput "2. From the VM, test health check: Invoke-RestMethod -Uri 'http://$($outputs.loadBalancerPrivateIP.Value)/health'" "White"
        Write-ColorOutput "3. From the VM, test web page: Invoke-WebRequest -Uri 'http://$($outputs.loadBalancerPrivateIP.Value)/'" "White"
        Write-ColorOutput "`nBastion Access:" "Yellow"
        Write-ColorOutput "- Go to the Azure Portal" "White"
        Write-ColorOutput "- Navigate to the Windows Server VM: $($outputs.vmName.Value)" "White"
        Write-ColorOutput "- Click 'Connect' > 'Bastion' to securely connect via browser" "White"
        Write-ColorOutput "- Use VM credentials: vmadmin / (password from parameters)" "White"
        Write-ColorOutput "`nNAT Gateway Benefits:" "Yellow"
        Write-ColorOutput "- Reliable outbound internet connectivity for ACI" "White"
        Write-ColorOutput "- No SNAT port exhaustion issues" "White"
        Write-ColorOutput "- Static public IP for all outbound traffic: $($outputs.natGatewayPublicIP.Value)" "White"
        
    } else {
        Write-ColorOutput "ARM template deployment failed!" "Red"
        Write-ColorOutput "Deployment State: $($deployment.ProvisioningState)" "Red"
        exit 1
    }
}
catch {
    Write-ColorOutput "Error during deployment: $($_.Exception.Message)" "Red"
    exit 1
}

Write-ColorOutput "`nDeployment script completed successfully!" "Green"