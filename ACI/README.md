# Nginx Internal Load Balancer with Azure Container Instances

This repository contains an ARM template that deploys an internal Standard Load Balancer with an Azure Container Instance running nginx, demonstrating a complete load balancing solution with VNet integration.

## Architecture Overview

The template creates the following resources:

1. **Virtual Network** with four subnets:
   - Load Balancer subnet (`10.0.1.0/24`)
   - Container subnet (`10.0.2.0/24`) with delegation to Azure Container Instances
   - Azure Bastion subnet (`10.0.3.0/26`)
   - VM subnet (`10.0.4.0/24`) for testing

2. **NAT Gateway** with:
   - Standard public IP for outbound connectivity
   - Associated with the container subnet
   - Configurable idle timeout (4-120 minutes)
   - Ensures reliable outbound internet access for ACI

3. **Internal Standard Load Balancer** with:
   - Frontend IP configuration in the load balancer subnet
   - Backend pool for container instances
   - Health probe for HTTP health checks (`/health`)
   - TCP health probe for UDP service monitoring
   - Load balancing rule for HTTP traffic (port 80 → 8080)
   - Load balancing rule for UDP traffic (port 9090 → 9090)

4. **Azure Container Instance** with:
   - nginx 1.15.5-alpine container image
   - VNet integration for private networking
   - Custom nginx configuration with health endpoint
   - Default web page for testing
   - UDP echo server on port 9090

**Note**: The UDP health probe uses TCP on port 8080 (the nginx HTTP port) since Azure Load Balancer doesn't support native UDP health probes. This ensures the container is healthy and reachable before routing UDP traffic to it.

1. **Azure Bastion** with:
   - Standard public IP for secure remote access
   - Integrated with the VNet for secure VM connections
   - Eliminates the need for public IPs on VMs

2. **Windows Server 2019 VM** with:
   - Dedicated subnet (10.0.4.0/24) for testing
   - Private IP only (no public IP for security)
   - Accessible via Azure Bastion for load balancer testing
   - Standard_D4s_v3 VM size (4 vCPUs, 16 GB RAM) for robust testing

The Azure Container Instance is integrated directly with the VNet using subnet delegation (no Network Profile required with API version 2023-05-01+).

## Files Included

- `nginx-loadbalancer-template.json` - Main ARM template
- `Deploy-NginxLoadBalancer.ps1` - PowerShell deployment script
- `parameters.json` - Default deployment parameters
- `README.md` - This documentation

## Prerequisites

1. Azure subscription with appropriate permissions
2. Azure PowerShell module (`Az`) installed
3. Logged in to Azure (`Connect-AzAccount`)
4. Azure CLI installed and logged in (`az login`) - *Recommended for automatic backend pool configuration*

## Deployment Options

### Option 1: Using PowerShell Script (Recommended)

```powershell
.\Deploy-NginxLoadBalancer.ps1 -ResourceGroupName "rg-nginx-test" -Location "East US"
```

The script will:

- Create the resource group if it doesn't exist
- Deploy the ARM template
- Wait for the container to get an IP address
- Automatically add the container to the load balancer backend pool
- Display connection information

### Option 2: Using Azure CLI

```bash
# Create resource group
az group create --name "rg-nginx-test" --location "centralus"

# Deploy template
az deployment group create \
  --resource-group "rg-nginx-test" \
  --template-file "nginx-loadbalancer-template.json" \
  --parameters resourcePrefix="nginx-lb" location="East US"

# Get container IP (after deployment)
CONTAINER_IP=$(az container show --resource-group "rg-nginx-test" --name "nginx-lb-aci" --query ipAddress.ip -o tsv)

# Add container to backend pool
az network lb address-pool address add \
  --resource-group "rg-nginx-test" \
  --lb-name "nginx-lb-lb" \
  --pool-name "BackendPool" \
  --name "nginx-aci" \
  --vnet "nginx-lb-vnet" \
  --ip-address $CONTAINER_IP
```

### Option 3: Using Azure Portal

1. Navigate to "Create a resource" > "Template deployment"
2. Choose "Build your own template in the editor"
3. Copy and paste the contents of `nginx-loadbalancer-template.json`
4. Fill in the parameters
5. Deploy the template
6. Manually add the container to the backend pool using Azure CLI or PowerShell

## Parameters

| Parameter | Description | Default Value |
|-----------|-------------|---------------|
| `resourcePrefix` | Prefix for all resource names | `nginx-lb` |
| `location` | Azure region for deployment | Resource group location |
| `vnetAddressPrefix` | Virtual network address space | `10.0.0.0/16` |
| `loadBalancerSubnetPrefix` | Load balancer subnet CIDR | `10.0.1.0/24` |
| `containerSubnetPrefix` | Container subnet CIDR | `10.0.2.0/24` |
| `bastionSubnetPrefix` | Azure Bastion subnet CIDR (must be /26 or larger) | `10.0.3.0/26` |
| `vmSubnetPrefix` | VM subnet CIDR | `10.0.4.0/24` |
| `containerImage` | Docker image for web server | `mcr.microsoft.com/oss/nginx/nginx:1.15.5-alpine` |
| `natGatewayIdleTimeoutInMinutes` | NAT Gateway idle timeout (4-120 minutes) | `4` |

**Note**: This deployment uses nginx for load balancer testing. The infrastructure and load balancing functionality remains the same.

## Verifying UDP Load Balancing

After deployment, follow these steps to verify that UDP load balancing is working correctly:

### Step 1: Check Load Balancer Configuration

First, verify that the UDP components are properly configured:

```powershell
# Check if UDP load balancing rule exists
az network lb rule show --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --name "UdpRule" --output table

# Check if UDP health probe exists
az network lb probe show --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --name "UdpHealthProbe" --output table

# List all load balancing rules to confirm both HTTP and UDP are present
az network lb rule list --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --output table
```

### Step 2: Verify Container UDP Service

Check that the container is running the UDP echo server:

```powershell
# Check container logs to see if UDP server started
az container logs --resource-group "rg-nginx-test" --name "nginx-lb-aci" --container-name "nginx"

# Get container status
az container show --resource-group "rg-nginx-test" --name "nginx-lb-aci" --query "containers[0].instanceView.currentState" --output table

# Test if container is listening on UDP port (from within the container)
az container exec --resource-group "rg-nginx-test" --name "nginx-lb-aci" --container-name "nginx" --exec-command "netstat -ln | grep 9090"
```

### Step 3: Get IP Addresses for Testing

Get the necessary IP addresses:

```powershell
# Get load balancer private IP
$LB_IP = az network lb frontend-ip show --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --name "LoadBalancerFrontEnd" --query privateIPAddress -o tsv
Write-Host "Load Balancer IP: $LB_IP"

# Get container private IP
$CONTAINER_IP = az container show --resource-group "rg-nginx-test" --name "nginx-lb-aci" --query ipAddress.ip -o tsv
Write-Host "Container IP: $CONTAINER_IP"

# Get VM private IP (for testing from)
$VM_IP = az vm show --resource-group "rg-nginx-test" --name "nginx-lb-vm" --show-details --query privateIps -o tsv
Write-Host "VM IP: $VM_IP"
```

### Step 4: Test UDP from Windows Server VM

Connect to your Windows Server VM via Azure Bastion, then test UDP connectivity:

#### Option A: Using PowerShell Test-NetConnection (Limited - TCP connectivity only)

**Note**: `Test-NetConnection` is primarily designed for TCP connections and cannot properly test UDP services. It will only test if the port is reachable, but won't verify if the UDP echo server is actually responding.

```powershell
# Test basic port reachability (TCP-based test, limited for UDP)
Test-NetConnection -ComputerName "10.0.1.4" -Port 9090 -InformationLevel Detailed

# This only tests if the port is open, not if UDP service is working
Test-NetConnection -ComputerName "10.0.2.4" -Port 9090 -InformationLevel Detailed
```

**For proper UDP testing, use Option B (ncat) or Option C (PowerShell UDP client) below.**

#### Option B: Install and Use ncat (Full UDP echo test)

```powershell
# Install chocolatey (if not already installed)
Set-ExecutionPolicy Bypass -Scope Process -Force
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

# Install nmap (includes ncat which works better than netcat on Windows)
choco install nmap -y

# Refresh environment variables and PATH
refreshenv

# If refreshenv doesn't work, close and reopen your PowerShell window
# Or manually refresh the PATH:
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")

# Test if ncat is available
ncat --version

# Test UDP through load balancer using ncat
echo "Hello Load Balancer UDP!" | ncat -u 10.0.1.4 9090

# Test UDP directly to container using ncat
echo "Hello Container UDP!" | ncat -u 10.0.2.4 9090
```

#### Option C: Using PowerShell UDP Client (Custom script)

```powershell
# Custom PowerShell UDP test function
function Send-UDPMessage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Server,
        [Parameter(Mandatory=$true)]
        [int]$Port,
        [Parameter(Mandatory=$true)]
        [string]$Message
    )
    
    Write-Host "📤 Testing UDP connection to $Server`:$Port" -ForegroundColor Cyan
    Write-Host "📝 Message: '$Message'" -ForegroundColor Gray
    
    $UdpClient = New-Object System.Net.Sockets.UdpClient
    $UdpClient.Client.ReceiveTimeout = 5000  # 5 second timeout
    
    try {
        # Send UDP message
        $MessageBytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
        $BytesSent = $UdpClient.Send($MessageBytes, $MessageBytes.Length, $Server, $Port)
        Write-Host "✓ Sent $BytesSent bytes" -ForegroundColor Green
        
        # Wait for response
        $RemoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $ResponseBytes = $UdpClient.Receive([ref]$RemoteEndpoint)
        $ResponseText = [System.Text.Encoding]::UTF8.GetString($ResponseBytes)
        
        Write-Host "✅ UDP Response: '$ResponseText'" -ForegroundColor Green
        Write-Host "📍 From: $($RemoteEndpoint.Address):$($RemoteEndpoint.Port)" -ForegroundColor Cyan
        return $ResponseText
    }
    catch [System.Net.Sockets.SocketException] {
        Write-Host "❌ Socket Error: No UDP server listening or network unreachable" -ForegroundColor Red
        return $null
    }
    catch [System.TimeoutException] {
        Write-Host "⏰ Timeout: No response received within 5 seconds" -ForegroundColor Yellow
        return $null
    }
    catch {
        Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    finally {
        $UdpClient.Close()
    }
}

# Test UDP via Load Balancer
Send-UDPMessage -Server "10.0.1.4" -Port 9090 -Message "Hello Load Balancer!"

# Test UDP directly to container (if accessible)
Send-UDPMessage -Server "10.0.2.4" -Port 9090 -Message "Hello Container!"
```

### Step 5: Expected Results

When UDP is working correctly, you should see:

#### HTTP Status Check (confirms container is healthy)

```powershell
Invoke-RestMethod -Uri "http://10.0.1.4/udp-status"
# Expected: "UDP echo server running on port 9090"
```

#### UDP Echo Response

- **Through Load Balancer**: `"UDP Echo Server Ready"`
- **Direct to Container**: `"UDP Echo Server Ready"`
- **Both should return the same response**

#### Load Balancer Rules

```text
Name     Protocol    FrontendPort    BackendPort    HealthProbe
HttpRule Tcp         80              8080           HealthProbe
UdpRule  Udp         9090            9090           UdpHealthProbe
```

### UDP Testing Troubleshooting

If you get "TIMEOUT: No response" or socket errors, follow this diagnostic checklist:

#### 1. **First: Check if UDP is actually deployed in your container**

```powershell
# Check container logs for UDP server startup
az container logs --resource-group "rg-nginx-test" --name "nginx-lb-aci" --container-name "nginx"

# Look for these in the logs:
# - "apk add --no-cache netcat-openbsd" (netcat installation)
# - UDP server starting messages
# - No error messages about netcat or nc commands
```

**If you DON'T see netcat installation in the logs**, your container was deployed with an older template version without UDP support.

#### 2. **Check if UDP port is exposed**

```powershell
# Verify UDP port 9090 is configured
az container show --resource-group "rg-nginx-test" --name "nginx-lb-aci" --query "containers[0].ports" -o table

# Expected output should include:
# Port    Protocol
# ----    --------
# 8080    TCP
# 8081    TCP  
# 9090    UDP      ← This must be present!
```

#### 3. **Check if UDP load balancing rule exists**

```powershell
# Check for UDP rule
az network lb rule show --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --name "UdpRule" -o table

# If this fails, the UDP load balancing rule doesn't exist
```

#### 4. **Check backend pool configuration**

```powershell
# Verify container is in backend pool
$CONTAINER_IP = az container show --resource-group "rg-nginx-test" --name "nginx-lb-aci" --query ipAddress.ip -o tsv
$BACKEND_IPS = az network lb address-pool show --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --name "BackendPool" --query "loadBalancerBackendAddresses[].ipAddress" -o tsv

Write-Host "Container IP: $CONTAINER_IP"
Write-Host "Backend Pool IPs: $BACKEND_IPS"

if ($BACKEND_IPS -contains $CONTAINER_IP) {
    Write-Host "✓ Container is in backend pool" -ForegroundColor Green
} else {
    Write-Host "✗ Container NOT in backend pool - this is the problem!" -ForegroundColor Red
}
```

#### 5. **Test direct container access (bypass load balancer)**

```powershell
# Test UDP directly to container (this should work if UDP service is running)
function Test-UDPDirect {
    param($ContainerIP)
    
    $UdpClient = $null
    try {
        $UdpClient = New-Object System.Net.Sockets.UdpClient
        $UdpClient.Client.ReceiveTimeout = 3000
        
        $Message = [System.Text.Encoding]::UTF8.GetBytes("Direct test")
        $UdpClient.Send($Message, $Message.Length, $ContainerIP, 9090)
        
        $RemoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $Response = $UdpClient.Receive([ref]$RemoteEndpoint)
        $ResponseText = [System.Text.Encoding]::UTF8.GetString($Response)
        
        Write-Host "✓ Direct container UDP works: $ResponseText" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "✗ Direct container UDP failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
    finally {
        if ($UdpClient) { $UdpClient.Close() }
    }
}

Test-UDPDirect -ContainerIP $CONTAINER_IP
```

## **Solutions Based on Diagnosis:**

### **Solution A: Container Missing UDP (Most Likely)**

If UDP port or netcat isn't in the container, you need to redeploy:

```powershell
# Redeploy with updated template
.\Deploy-NginxLoadBalancer.ps1 -ResourceGroupName "rg-nginx-test" -Location "Central US"
```

### **Solution B: Missing UDP Load Balancer Rule**

If UDP rule doesn't exist, add it manually:

```powershell
# Add UDP health probe
az network lb probe create --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --name "UdpHealthProbe" --protocol "Tcp" --port 8080 --interval 15 --threshold 2

# Add UDP load balancing rule  
az network lb rule create --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --name "UdpRule" --protocol "Udp" --frontend-ip-name "LoadBalancerFrontEnd" --backend-pool-name "BackendPool" --probe-name "UdpHealthProbe" --frontend-port 9090 --backend-port 9090 --idle-timeout 4
```

### **Solution C: Backend Pool Missing Container**

If container not in backend pool:

```powershell
# Add container to backend pool
az network lb address-pool address add --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --pool-name "BackendPool" --name "nginx-aci" --vnet "nginx-lb-vnet" --ip-address $CONTAINER_IP
```

### **Solution D: Container Restart (If UDP service crashed)**

```powershell
# Restart the container to restart UDP service
az container restart --resource-group "rg-nginx-test" --name "nginx-lb-aci"

# Wait a moment, then check logs
Start-Sleep 30
az container logs --resource-group "rg-nginx-test" --name "nginx-lb-aci" --container-name "nginx"
```

#### 1. Environment Variables and PATH Issues

```powershell
# Method 1: Refresh environment variables
refreshenv

# Method 2: Manual PATH refresh
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")

# Method 3: Close and reopen PowerShell completely

# Method 4: Check if ncat is in PATH
Get-Command ncat -ErrorAction SilentlyContinue
if ($?) { 
    Write-Host "✓ ncat found in PATH" -ForegroundColor Green
    ncat --version
} else {
    Write-Host "✗ ncat not found in PATH" -ForegroundColor Red
    Write-Host "Try: C:\ProgramData\chocolatey\lib\nmap\tools\ncat.exe --version"
}

# Method 5: Use full path if ncat not in PATH
C:\ProgramData\chocolatey\lib\nmap\tools\ncat.exe --version
```

#### 2. Alternative UDP Testing Methods

If ncat still doesn't work, try these alternatives:

```powershell
# Option A: PowerShell UDP client function
function Send-UDPMessage {
    param(
        [string]$Server,
        [int]$Port,
        [string]$Message
    )
    
    $UdpClient = New-Object System.Net.Sockets.UdpClient
    $UdpClient.Client.ReceiveTimeout = 5000
    
    try {
        # Send message
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
        $UdpClient.Send($Bytes, $Bytes.Length, $Server, $Port)
        
        # Receive response
        $RemoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $Response = $UdpClient.Receive([ref]$RemoteEndpoint)
        $ResponseText = [System.Text.Encoding]::UTF8.GetString($Response)
        
        Write-Host "✓ UDP Response from $Server`: $ResponseText" -ForegroundColor Green
        return $ResponseText
    }
    catch {
        Write-Host "✗ UDP test failed: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
    finally {
        $UdpClient.Close()
    }
}

# Test UDP with PowerShell function
$LB_IP = "10.0.1.4"  # Replace with your load balancer IP
Send-UDPMessage -Server $LB_IP -Port 9090 -Message "Hello from PowerShell!"
```

```powershell
# Option B: Test basic connectivity first (TCP-based port check only)
Test-NetConnection -ComputerName $LB_IP -Port 9090 -InformationLevel Detailed

# Note: Test-NetConnection doesn't work for UDP echo testing - use UDP client function instead

# Option C: Use telnet for basic testing (TCP only, but tests connectivity)
# Note: This won't work for UDP but tests if the load balancer is reachable
Test-NetConnection -ComputerName $LB_IP -Port 80 -InformationLevel Detailed
```

#### 3. Verify Container and Load Balancer Status

```powershell
# Check if container is running
az container show --resource-group "rg-nginx-test" --name "nginx-lb-aci" --query "containers[0].instanceView.currentState.state" -o tsv

# Check container logs for UDP server
az container logs --resource-group "rg-nginx-test" --name "nginx-lb-aci" --container-name "nginx" | Select-String -Pattern "UDP|netcat|nc"

# Check if UDP port is exposed in container
az container show --resource-group "rg-nginx-test" --name "nginx-lb-aci" --query "containers[0].ports" -o table

# Verify load balancer UDP rule exists
az network lb rule show --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --name "UdpRule" -o table

# Check backend pool has container
az network lb address-pool show --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --name "BackendPool" --query "loadBalancerBackendAddresses[].ipAddress" -o tsv
```

If UDP isn't working, check these common issues:

```powershell
# 1. Verify backend pool has the container
az network lb address-pool show --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --name "BackendPool" --query "loadBalancerBackendAddresses[].ipAddress"

# 2. Check health probe status
az network lb probe show --resource-group "rg-nginx-test" --lb-name "nginx-lb-lb" --name "UdpHealthProbe" --query "provisioningState"

# 3. Verify container ports are exposed
az container show --resource-group "rg-nginx-test" --name "nginx-lb-aci" --query "containers[0].ports"

# 4. Check if UDP process is running in container
az container exec --resource-group "rg-nginx-test" --name "nginx-lb-aci" --container-name "nginx" --exec-command "ps aux | grep nc"
```

### Quick UDP Test Script

Save this as `Test-UDP.ps1` for quick testing:

```powershell
param(
    [string]$ResourceGroup = "rg-nginx-test",
    [string]$LoadBalancerName = "nginx-lb-lb",
    [string]$ContainerName = "nginx-lb-aci"
)

Write-Host "=== UDP Load Balancer Test ===" -ForegroundColor Yellow

# Get IPs
$LB_IP = az network lb frontend-ip show --resource-group $ResourceGroup --lb-name $LoadBalancerName --name "LoadBalancerFrontEnd" --query privateIPAddress -o tsv
$CONTAINER_IP = az container show --resource-group $ResourceGroup --name $ContainerName --query ipAddress.ip -o tsv

Write-Host "Load Balancer IP: $LB_IP" -ForegroundColor Cyan
Write-Host "Container IP: $CONTAINER_IP" -ForegroundColor Cyan

# Test HTTP status
Write-Host "`nTesting HTTP UDP status endpoint..." -ForegroundColor Yellow
try {
    $Status = Invoke-RestMethod -Uri "http://$LB_IP/udp-status" -TimeoutSec 5
    Write-Host "✓ HTTP Status: $Status" -ForegroundColor Green
} catch {
    Write-Host "✗ HTTP Status failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test basic connectivity
Write-Host "`nTesting UDP port reachability (TCP-based test)..." -ForegroundColor Yellow
$LBTest = Test-NetConnection -ComputerName $LB_IP -Port 9090 -InformationLevel Quiet -WarningAction SilentlyContinue
$ContainerTest = Test-NetConnection -ComputerName $CONTAINER_IP -Port 9090 -InformationLevel Quiet -WarningAction SilentlyContinue

Write-Host "✓ Load Balancer Port 9090 Reachable: $(if($LBTest){'Yes'}else{'No'})" -ForegroundColor $(if($LBTest){'Green'}else{'Red'})
Write-Host "✓ Container Port 9090 Reachable: $(if($ContainerTest){'Yes'}else{'No'})" -ForegroundColor $(if($ContainerTest){'Green'}else{'Red'})
Write-Host "Note: This only tests port reachability, not UDP echo functionality" -ForegroundColor Yellow

Write-Host "`n=== Test Complete ===" -ForegroundColor Yellow
Write-Host "Next: Install nmap with 'choco install nmap' for full UDP echo testing with ncat" -ForegroundColor Cyan
```

### Quick Environment Reset Script

If you're having issues with environment variables or PATH, save this as `Reset-Environment.ps1`:

```powershell
# Reset-Environment.ps1 - Fix PATH and environment issues after installing nmap

Write-Host "=== Environment Reset Script ===" -ForegroundColor Yellow

# Method 1: Refresh environment variables
Write-Host "Refreshing environment variables..." -ForegroundColor Cyan
try {
    if (Get-Command refreshenv -ErrorAction SilentlyContinue) {
        refreshenv
        Write-Host "✓ refreshenv completed" -ForegroundColor Green
    } else {
        Write-Host "! refreshenv not available" -ForegroundColor Yellow
    }
} catch {
    Write-Host "! refreshenv failed: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Method 2: Manual PATH refresh
Write-Host "Manually refreshing PATH..." -ForegroundColor Cyan
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("PATH","User")

# Method 3: Check for ncat
Write-Host "Checking for ncat..." -ForegroundColor Cyan
if (Get-Command ncat -ErrorAction SilentlyContinue) {
    Write-Host "✓ ncat found in PATH" -ForegroundColor Green
    $ncatVersion = ncat --version 2>$null
    Write-Host "ncat version: $ncatVersion" -ForegroundColor White
} else {
    Write-Host "✗ ncat not found in PATH" -ForegroundColor Red
    
    # Try common locations
    $commonPaths = @(
        "C:\ProgramData\chocolatey\lib\nmap\tools\ncat.exe",
        "C:\Program Files (x86)\Nmap\ncat.exe",
        "C:\Program Files\Nmap\ncat.exe"
    )
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            Write-Host "✓ Found ncat at: $path" -ForegroundColor Green
            Write-Host "You can use the full path: $path -u [ip] [port]" -ForegroundColor Cyan
            break
        }
    }
}

# Method 4: Test basic PowerShell UDP function
Write-Host "Testing PowerShell UDP function..." -ForegroundColor Cyan
function Test-UDPEcho {
    param($Server, $Port, $Message = "Test")
    $UdpClient = New-Object System.Net.Sockets.UdpClient
    try {
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Message)
        $UdpClient.Send($Bytes, $Bytes.Length, $Server, $Port)
        $UdpClient.Client.ReceiveTimeout = 3000
        $RemoteEndpoint = New-Object System.Net.IPEndPoint([System.Net.IPAddress]::Any, 0)
        $Response = $UdpClient.Receive([ref]$RemoteEndpoint)
        return [System.Text.Encoding]::UTF8.GetString($Response)
    } catch {
        return "Error: $($_.Exception.Message)"
    } finally {
        $UdpClient.Close()
    }
}

Write-Host "✓ PowerShell UDP function available" -ForegroundColor Green
Write-Host "Usage: Test-UDPEcho -Server '10.0.1.4' -Port 9090 -Message 'Hello!'" -ForegroundColor Cyan

Write-Host "`n=== Reset Complete ===" -ForegroundColor Yellow
Write-Host "If ncat still doesn't work, close and reopen PowerShell completely." -ForegroundColor White
```

## NAT Gateway for Outbound Connectivity

The template includes an Azure NAT Gateway that provides reliable outbound internet connectivity for the Azure Container Instance:

### Benefits

- **Reliable Outbound Connectivity**: Ensures consistent outbound internet access for container instances
- **No SNAT Port Exhaustion**: Eliminates SNAT port exhaustion issues that can occur with default outbound connectivity
- **Static Public IP**: Uses a dedicated Standard public IP for all outbound traffic
- **Configurable Timeout**: Adjustable idle timeout (4-120 minutes) to optimize connection handling
- **Enhanced Security**: Provides more predictable outbound connectivity compared to default Azure outbound access

### Use Cases

- Container instances that need to pull images from registries
- Applications that make outbound API calls
- Software updates and package installations
- External monitoring and logging services

## Nginx Configuration

The nginx container is configured with:

- **Frontend**: Listens on port 8080 for HTTP traffic
- **Backend**: Routes to internal web server on port 8081
- **Health Check Endpoint**: `/health` returns HTTP 200 with "nginx is healthy"
- **UDP Status Endpoint**: `/udp-status` returns information about the UDP echo server
- **Default Web Page**: Simple HTML page confirming the setup is working
- **UDP Echo Server**: Listens on port 9090 for UDP traffic

### Container Ports

- `8080`: Main HTTP frontend (receives load balancer traffic)
- `8081`: Internal web server (serves default page)
- `9090`: UDP echo server (for UDP testing)

### UDP Echo Server

The container includes a UDP echo server built with netcat that:

- Listens on port 9090
- Echoes back "UDP Echo Server Ready" to any UDP message received
- Can be tested from within the VNet using netcat/ncat or similar tools
- **Now accessible through the Azure Load Balancer** at port 9090

## Testing the Deployment

Since this is an internal load balancer, you'll need to test from within the VNet. The deployment includes a Windows Server 2019 VM and Azure Bastion for secure testing:

### 1. Connect to the Windows Server Test VM

The template includes a Windows Server 2019 VM specifically for testing the load balancer. Use Azure Bastion to connect:

1. **Via Azure Portal**:
   - Navigate to the Windows Server VM in the Azure Portal (VM name will be `<resourcePrefix>-vm`)
   - Click "Connect" > "Bastion"
   - Enter the VM credentials:
     - Username: `vmadmin` (or the value you set in parameters)
     - Password: The secure password you provided in the parameters
   - Connect securely through your browser

2. **Alternative - if you created your own test VM**:

```bash
az vm create \
  --resource-group "rg-nginx-test" \
  --name "test-vm" \
  --image "Ubuntu2204" \
  --vnet-name "nginx-lb-vnet" \
  --subnet "vm-subnet" \
  --admin-username "azureuser" \
  --generate-ssh-keys \
  --public-ip-address ""
```

### 2. Run Load Balancer Tests

**From Windows Server VM** (connect via Azure Bastion first):

1. Open PowerShell or Command Prompt
2. Test using PowerShell cmdlets or curl (if available):

```bash
# Get the load balancer private IP from deployment outputs
LB_IP="10.0.1.4"  # Replace with actual IP from deployment

# Test health check endpoint
curl -v http://$LB_IP/health

# Test default web page
curl -v http://$LB_IP/

# Test with specific host header
curl -v -H "Host: example.com" http://$LB_IP/
```

**Using PowerShell (Windows Server VM)**:

```powershell
# Get the load balancer private IP from deployment outputs
$LB_IP = "10.0.1.4"  # Replace with actual IP from deployment

# Test health check endpoint
Invoke-RestMethod -Uri "http://$LB_IP/health" -Method Get -Verbose

# Test default web page
Invoke-WebRequest -Uri "http://$LB_IP/" -Verbose

# Test UDP status endpoint
Invoke-RestMethod -Uri "http://$LB_IP/udp-status" -Method Get -Verbose

# Test with specific host header
Invoke-WebRequest -Uri "http://$LB_IP/" -Headers @{"Host"="example.com"} -Verbose
```

**Testing UDP Load Balancer**:

From the Windows Server VM, you can now test the UDP echo server through the load balancer:

```powershell
# Get the load balancer private IP from deployment outputs
$LB_IP = "10.0.1.4"  # Replace with actual IP from deployment

# Test UDP through the load balancer 
# Note: Test-NetConnection is TCP-focused and won't properly test UDP echo functionality
# For basic port reachability only:
Test-NetConnection -ComputerName $LB_IP -Port 9090 -InformationLevel Detailed

# For proper UDP testing, use the PowerShell UDP function (Option C) or ncat
```

Or if you install nmap on Windows:

```cmd
REM Test UDP echo server through load balancer
echo "Hello UDP Load Balancer!" | ncat -u [load-balancer-ip] 9090
```

You can also test the UDP endpoint directly to the container IP for comparison:

```powershell
# Get the container private IP (from deployment outputs or Azure CLI)
$CONTAINER_IP = "10.0.2.4"  # Replace with actual container IP

# Test UDP endpoint directly to container
# Note: Test-NetConnection only tests port reachability (TCP-based), not UDP echo functionality
Test-NetConnection -ComputerName $CONTAINER_IP -Port 9090 -InformationLevel Detailed

# For actual UDP echo testing, use the PowerShell UDP client function from Option C above
```

**Using curl (if available on Windows Server)**:

```cmd
REM Get the load balancer private IP from deployment outputs
set LB_IP=10.0.1.4

REM Test health check endpoint
curl -v http://%LB_IP%/health

REM Test default web page
curl -v http://%LB_IP%/

REM Test with specific host header
curl -v -H "Host: example.com" http://%LB_IP%/
```

Expected responses:

- Health check: `nginx is healthy`
- UDP status: `UDP echo server running on port 9090`
- Web page: HTML page with "Hello from nginx!" message and UDP server information
- UDP echo: `UDP Echo Server Ready` (when testing UDP port directly)

### 3. Verify Load Balancer Configuration

Before testing, ensure the backend pool is configured correctly:

```bash
# Check if container is in the backend pool
az network lb address-pool show \
  --resource-group "rg-nginx-test" \
  --lb-name "nginx-lb-lb" \
  --name "BackendPool" \
  --query "loadBalancerBackendAddresses[].ipAddress" \
  --output table
```

If the backend pool is empty, add the container manually:

```bash
# Get container IP
CONTAINER_IP=$(az container show --resource-group "rg-nginx-test" --name "nginx-lb-aci" --query ipAddress.ip -o tsv)

# Add to backend pool
az network lb address-pool address add \
  --resource-group "rg-nginx-test" \
  --lb-name "nginx-lb-lb" \
  --pool-name "BackendPool" \
  --name "nginx-aci" \
  --vnet "nginx-lb-vnet" \
  --ip-address $CONTAINER_IP
```

## Troubleshooting

### Container Not Starting

```bash
# Check container logs
az container logs --resource-group "rg-nginx-test" --name "nginx-lb-aci" --container-name "nginx"

# Check container status
az container show --resource-group "rg-nginx-test" --name "nginx-lb-aci"
```

### Load Balancer Not Responding

```bash
# Check backend pool members
az network lb address-pool show \
  --resource-group "rg-nginx-test" \
  --lb-name "nginx-lb-lb" \
  --name "BackendPool"

# Check load balancer frontend IP
az network lb frontend-ip show \
  --resource-group "rg-nginx-test" \
  --lb-name "nginx-lb-lb" \
  --name "LoadBalancerFrontEnd"
```

### Backend Pool Empty

If the backend pool is empty after deployment, manually add the container:

```bash
# Get the container IP
CONTAINER_IP=$(az container show --resource-group "rg-nginx-test" --name "nginx-lb-aci" --query ipAddress.ip -o tsv)

# Add container to backend pool
az network lb address-pool address add \
  --resource-group "rg-nginx-test" \
  --lb-name "nginx-lb-lb" \
  --pool-name "BackendPool" \
  --name "nginx-aci" \
  --vnet "nginx-lb-vnet" \
  --ip-address $CONTAINER_IP

# Verify the backend pool has the container
az network lb address-pool show \
  --resource-group "rg-nginx-test" \
  --lb-name "nginx-lb-lb" \
  --name "BackendPool" \
  --query "loadBalancerBackendAddresses[].ipAddress" \
  --output table
```

### UDP Load Balancer Issues

```bash
# Check UDP load balancing rule
az network lb rule show \
  --resource-group "rg-nginx-test" \
  --lb-name "nginx-lb-lb" \
  --name "UdpRule"

# Check UDP health probe status
az network lb probe show \
  --resource-group "rg-nginx-test" \
  --lb-name "nginx-lb-lb" \
  --name "UdpHealthProbe"

# Test UDP connectivity through load balancer
# Get load balancer IP
LB_IP=$(az network lb frontend-ip show \
  --resource-group "rg-nginx-test" \
  --lb-name "nginx-lb-lb" \
  --name "LoadBalancerFrontEnd" \
  --query privateIPAddress -o tsv)

# Test UDP through load balancer (requires ncat from nmap)
echo "test message" | ncat -u $LB_IP 9090
```

### Network Connectivity Issues

```bash
# Test from container subnet
az network vnet subnet show \
  --resource-group "rg-nginx-test" \
  --vnet-name "nginx-lb-vnet" \
  --name "container-subnet"

# Check NSG rules (if any)
az network nsg list --resource-group "rg-nginx-test"
```

## Customizing Nginx Configuration

To customize the nginx configuration:

1. Modify the base64-encoded configuration in the ARM template
2. Or mount a custom configuration file using Azure Files
3. Update the container command to use your custom config

### Example: Adding SSL Termination

```nginx
server {
    listen 443 ssl;
    ssl_certificate /etc/ssl/certs/certificate.pem;
    ssl_certificate_key /etc/ssl/private/private-key.pem;
    
    location / {
        proxy_pass http://backend;
    }
}
```

## Clean Up

To remove all resources:

```bash
az group delete --name "rg-nginx-test" --yes --no-wait
```

## Security Considerations

1. **Private Network**: All resources are deployed in private subnets
2. **No Public IPs on VMs**: VMs don't need public IP addresses thanks to Azure Bastion
3. **Secure Remote Access**: Azure Bastion provides secure RDP/SSH access without exposing VMs
4. **Network Segmentation**: Separate subnets for load balancer, containers, and Bastion
5. **Access Control**: Consider implementing Network Security Groups (NSGs) for additional security

## Cost Optimization

1. **Container Resources**: Adjust CPU/memory requests based on actual load
2. **Load Balancer SKU**: Use Basic SKU for development environments
3. **Availability Zones**: Consider zone redundancy for production workloads

## Production Considerations

1. **High Availability**: Deploy multiple container instances across availability zones
2. **Monitoring**: Implement Azure Monitor for load balancer and container metrics
3. **Logging**: Configure centralized logging for nginx and container logs
4. **SSL/TLS**: Implement SSL termination at the load balancer or nginx level
5. **Auto Scaling**: Consider using Container Apps for auto-scaling capabilities

## Support

For issues with this template:

1. Check the troubleshooting section above
2. Review Azure service documentation
3. Check container logs for nginx-specific issues
