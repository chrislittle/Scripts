# RBAC Test Suite for Restricted Subscription Owner

> **📖 Role Definition Documentation:** [../README.md](../README.md) - Custom role overview, permissions, restrictions, and use cases

This directory contains a comprehensive end-to-end testing framework for validating the **Restricted Subscription Owner** custom RBAC role.

## Overview

The test suite automates the validation of all 15 requirements defined in the custom role by attempting restricted operations and verifying they are properly denied through Azure RBAC.

## Test Architecture

```text
Tests/
├── Test-CustomRole.ps1                    # Main orchestrator script
├── Initialize-TestEnvironment.ps1         # Setup test environment
├── Test-AuthorizationRestrictions.ps1     # Test requirement #15
├── Test-NetworkingRestrictions.ps1        # Test requirements #1-14
├── Export-TestResults.ps1                 # Generate reports
├── Cleanup-TestEnvironment.ps1            # Teardown test resources
└── Results/                               # Output directory for test results
    ├── TestResults_[timestamp].json       # Detailed JSON results
    ├── TestResults_[timestamp].csv        # CSV export for analysis
    ├── TestResults_[timestamp].html       # Visual HTML report
    └── TestSummary_[timestamp].txt        # Text summary report
```

## Prerequisites

### Required Modules

```powershell
Install-Module -Name Az.Accounts
Install-Module -Name Az.Resources
Install-Module -Name Az.Network
Install-Module -Name Az.FrontDoor
Install-Module -Name Az.Cdn
Install-Module -Name Az.TrafficManager
```

### Required Permissions

- Owner or User Access Administrator role on the test subscription
- Ability to create service principals
- Ability to create custom role definitions
- Ability to assign roles

### Custom Role Auto-Deployment

**The test suite now automatically creates the custom role if it doesn't exist!**

During the setup phase, the script will:

1. Check if the custom role already exists
2. If not found, automatically create it from `CustomRole_RestrictedSubscriptionOwner.json`
3. Update the `AssignableScopes` to match your test subscription
4. Wait for role definition propagation

**Manual deployment (optional):**

If you prefer to deploy the role manually before testing:

```powershell
# Deploy the custom role manually
New-AzRoleDefinition -InputFile "..\CustomRole_RestrictedSubscriptionOwner.json"
```

## Usage

### Basic Test Execution

```powershell
# Run with specific subscription ID
.\Test-CustomRole.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012"

# Run with interactive subscription picker (shows all accessible subscriptions)
.\Test-CustomRole.ps1

# Run with interactive test selection menu
.\Test-CustomRole.ps1 -SubscriptionId "12345678-1234-1234-1234-123456789012" -Interactive

# Full interactive mode (subscription picker + test menu)
.\Test-CustomRole.ps1 -Interactive
```

### Region Selection Behavior (Interactive Mode)

By default the script assigns `-Location eastus` if you don't specify a region. However, **when you use `-Interactive` OR `-SafetyPrompts` and you do not explicitly pass `-Location`, the default is intentionally cleared and you will be prompted to choose a region before any compatibility validation runs.** This prevents the region capability check from executing against an assumed default you didn't consciously pick.

Summary:

- If you run `./Test-CustomRole.ps1 -Interactive` (no `-Location`), you'll be prompted to select a region.
- If you run `./Test-CustomRole.ps1 -SafetyPrompts` (no `-Location`), you'll also be prompted to select a region.
- If you run `./Test-CustomRole.ps1 -Interactive -Location westus2` or include `-SafetyPrompts -Location westus2`, your supplied region is used directly (no picker).
- Non-interactive runs still use the implicit default `eastus` unless you override it.
- Strict mode (`-StrictRegionValidation`) applies after selection and will fail early if required resource types aren't listed for the chosen region.

Tip: Use interactive or safety-prompt driven region selection for portability testing across multiple Azure regions.

#### Region Capability Validation Logic

Azure exposes location metadata in two forms: short codes (e.g. `eastus`) and display names (e.g. `East US`). Provider/resource type metadata (`Get-AzResourceProvider`) returns a `Locations` array containing **display names**, while users typically pass the short code. The test harness now:

- Resolves the supplied `-Location` using both code and display forms
- Normalizes comparisons (lowercase; removes spaces and punctuation)
- Treats missing `Locations` arrays as global/multi-region (skips false negatives)
- Accepts either the short code (`eastus`) or display name (`East US`) as input

If a region can't be resolved, a warning is shown; in strict mode the run stops. This eliminates the prior false unsupported list for regions like `eastus`.

### Interactive Subscription Selection

**If you omit the `-SubscriptionId` parameter**, the script will display an interactive subscription picker:

- Lists all subscriptions you have access to **in the current tenant**
- Shows subscription name, ID, state, and tenant information
- Respects your existing tenant scope from `Connect-AzAccount -Tenant <tenant-id>`
- Connects to Azure if not already authenticated (prompts for tenant selection if needed)
- Sets the correct context for the selected subscription

**Important:** If you need to test in a specific tenant, authenticate first with:

```powershell
Connect-AzAccount -Tenant <tenant-id>
.\Test-CustomRole.ps1
```

**Example:**

```text
═══════════════════════════════════════════════════════════════
  Azure Subscription Selection
═══════════════════════════════════════════════════════════════

Current account: user@contoso.com

Retrieving available subscriptions...

Available Subscriptions:

  [0] Production Subscription (Tenant: 12345678...)
      ID: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
      State: Enabled

  [1] Development Subscription (Tenant: 12345678...)
      ID: 11111111-2222-3333-4444-555555555555
      State: Enabled

  [2] Testing Subscription (Tenant: 87654321...)
      ID: 99999999-8888-7777-6666-555555555555
      State: Enabled

Enter subscription number [0-2]:
Selection: 1

Selected: Development Subscription (11111111-2222-3333-4444-555555555555)
```

### Interactive Test Selection

The `-Interactive` switch displays a menu allowing you to choose which requirement categories to test:

```text
Select Test Categories to Run:

  [0]  Run ALL Tests (Authorization + All Networking)

  Authorization & Policy:
    [15] Policy & Authorization restrictions

  Networking Restrictions:
    [1]  Virtual Networks (VNET, subnets, peering)
    [2]  ExpressRoute & VPN Gateways
    [3]  Route Tables
    [4]  Front Door & CDN
    [5]  Load Balancers & Application Gateways
    [6]  Private Link & Private Endpoints
    [7]  NAT Gateways
    [8]  Network Watcher
    [9]  Service Endpoints
    [10] Virtual WAN & Virtual Hubs
    [11] Traffic Manager
    [12] Virtual Network Tap
    [13] Azure Firewall & Firewall Policies
    [14] DDoS Protection Plans

Enter your selections (comma-separated, e.g., 0 or 1,2,5,15):
```

**Example selections:**

- `0` - Run all tests
- `1,2` - Test only VNets and Gateways
- `5,15` - Test Load Balancers and Authorization
- `13` - Test only Azure Firewall restrictions

**Benefits of interactive mode:**

- Faster iteration during development
- Focus on specific failed requirements
- Reduce test execution time and costs
- Skip resource-intensive tests when not needed

### Advanced Options

```powershell
# Use subscription picker with different location
.\Test-CustomRole.ps1 -Location "westus2"

# Use specific subscription with custom location
.\Test-CustomRole.ps1 -SubscriptionId "12345..." -Location "westus2"

# Skip setup (use existing test environment)
.\Test-CustomRole.ps1 -SkipSetup

# Skip cleanup (preserve resources for inspection)
.\Test-CustomRole.ps1 -SkipCleanup

# Custom role name
.\Test-CustomRole.ps1 -CustomRoleName "My Custom Role"

# Custom resource group name
.\Test-CustomRole.ps1 -TestResourceGroupName "rg-test-rbac"

# Combine options (subscription picker + interactive test menu + preserve resources)
.\Test-CustomRole.ps1 -Interactive -SkipCleanup
```

## Test Process

The test suite offers two execution modes:

### Interactive Mode (Selective Testing)

When you run with the `-Interactive` switch, you'll see a menu allowing you to choose which requirement categories to test:

- **Option 0**: Run ALL tests (Authorization + All Networking requirements)
- **Option 15**: Authorization & Policy restrictions only
- **Options 1-14**: Individual networking requirement categories

You can select multiple categories by entering comma-separated numbers (e.g., `1,2,5,15` to test VNets, Gateways, Load Balancers, and Authorization).

### Automated Mode (All Tests)

Without the `-Interactive` switch, all tests run automatically.

---

## Test Catalog & Prerequisites

### Prerequisite Resources Created During Setup

Before any tests run, the setup phase creates the following infrastructure in the test resource group:

#### Core Infrastructure

| Resource | Name | Purpose |
|----------|------|---------|
| **Service Principal** | `sp-rbac-test` | Test identity with the custom role assigned |
| **Resource Group** | `rg-rbac-test` | Container for all test resources |
| **Primary VNet** | `vnet-test-existing` | Base network for modification/deletion tests and specialized subnets |
| **Peer VNet** | `vnet-test-peer` | Target for VNet peering tests |
| **Route Table** | `rt-test-existing` | Target for route modification/deletion tests |

#### Specialized Subnets (in Primary VNet)

| Subnet | Address Range | Purpose |
|--------|---------------|---------|
| `default` | `10.100.1.0/24` | General workloads, Load Balancers, Private Endpoints |
| `GatewaySubnet` | `10.100.250.0/27` | VPN Gateway IP configuration |
| `AzureFirewallSubnet` | `10.100.251.0/26` | Azure Firewall attachment |
| `AppGatewaySubnet` | `10.100.252.0/27` | Application Gateway frontend |

#### Public IP Addresses

| Name | Purpose |
|------|---------|
| `pip-gateway` | VPN Gateway public endpoint |
| `pip-firewall` | Azure Firewall public IP |
| `pip-nat` | NAT Gateway outbound IP |
| `pip-appgw` | Application Gateway frontend IP |

#### Supporting Services

| Resource | Type | Purpose |
|----------|------|---------|
| Storage Account | `stpe{guid}` | Private Endpoint target for blob service |
| Network Watcher | `nw-test-existing-*` or reused existing | Tier 1 modify/delete tests (Azure limit: 1 per subscription per region; setup reuses if exists) |

### Test Categories Summary

| Category | Tests | Prerequisites | Duration | Skipped |
|----------|-------|---------------|----------|---------|
| **Authorization** (#15) | 7 | None | ~30s | 0 |
| **VNets** (#1) | 4 | VNet, Peer VNet | ~60s | 0 |
| **Gateways** (#2) | 2 | GatewaySubnet, Public IP | ~45s | 1 |
| **Route Tables** (#3) | 3 | Route Table | ~30s | 0 |
| **Front Door** (#4) | 2 | None | ~30s | 0 |
| **Load Balancers** (#5) | 2 | Subnets, Public IP | ~60s | 0 |
| **Private Link** (#6) | 2 | Storage Account | ~45s | 0 |
| **NAT Gateway** (#7) | 1 | Public IP | ~20s | 0 |
| **Network Watcher** (#8) | 1 | None | ~20s | 0 |
| **Service Endpoints** (#9) | 1 | None | ~20s | 0 |
| **Virtual WAN** (#10) | 2 | None | ~30s | 0 |
| **Traffic Manager** (#11) | 1 | None | ~20s | 0 |
| **VNet Tap** (#12) | 1 | None | ~5s | 1 |
| **Firewall** (#13) | 3 | Firewall Subnet, Public IP | ~60s | 0 |
| **DDoS** (#14) | 1 | None | ~20s | 0 |
| **TOTAL** | **33** | **11 resources** | **~7 min** | **2** |

### Common Test Selection Scenarios

#### Quick Validation (Core Network Controls)

Selection: `1,3,5` - VNets, Route Tables, Load Balancers (9 tests, ~2 minutes)

Use Case: Validate fundamental network isolation boundaries

#### High-Risk Resources (Security-Sensitive)

Selection: `2,10,13,15` - Gateways, Virtual WAN, Firewalls, Authorization (14 tests, ~3 minutes)

Use Case: Audit critical infrastructure and governance controls

#### Application Team Boundaries

Selection: `1,5,6,7` - VNets, Load Balancers, Private Link, NAT (9 tests, ~3 minutes)

Use Case: Validate app team can't modify network fabric

#### Platform Team Focus

Selection: `2,4,10,11,13` - Gateways, Front Door, Virtual WAN, Traffic Manager, Firewalls (10 tests, ~3 minutes)

Use Case: Verify platform-managed service restrictions

---

### Phase 1: Setup

1. Connects to Azure subscription
2. Verifies custom role exists (creates it automatically if not found)
3. Creates test resource group
4. Creates service principal for testing
5. Assigns custom role to service principal
6. Creates prerequisite resources (for modify/delete tests)

**Note:** Network Watcher has an Azure platform limit of **1 per subscription per region**. The setup phase automatically detects if a Network Watcher already exists in the target region and reuses it instead of attempting to create a duplicate (which would fail with `NetworkWatcherCountLimitReached`). Setup output will show either "Created Network Watcher" or "Reusing existing Network Watcher" accordingly.

Deletion Behavior:

- Azure does not expose a dedicated `Remove-AzNetworkWatcher` cmdlet in current Az modules.
- When the test suite creates a watcher, the delete test uses generic `Remove-AzResource -ResourceId <id>` to exercise the `Microsoft.Network/networkWatchers/delete` action.
- If the watcher was reused (pre-existing outside the test RG), the delete test is **skipped** to avoid disrupting existing diagnostics / flow logs.
- Skipped results are still reported with a clear reason.

Cleanup: Network Watchers created in the test resource group are removed automatically when the resource group is deleted. Reused watchers remain untouched.

### Phase 2: Authorization Tests

Tests restriction requirement #15:

- Policy assignment creation
- Policy definition creation
- Role assignment creation
- Custom role definition creation
- Resource lock creation
- Role assignment deletion
- Policy exemption creation

### Phase 3: Networking Tests

Tests restriction requirements #1-14:

- Virtual Networks (create, modify, delete, peering)
- ExpressRoute & VPN Gateways
- Route Tables
- Front Door & CDN
- Load Balancers & Application Gateways
- Private Endpoints & Private Link Services
- NAT Gateways
- Network Watcher
- Service Endpoints
- Virtual WAN & Virtual Hubs
- Traffic Manager
- Virtual Network Tap
- Azure Firewall & Firewall Policies
- DDoS Protection Plans

### Phase 4: Summary Calculation

Aggregates test results and calculates statistics

Status meanings:

- PASS: Operation correctly denied or allowed per expected restriction logic
- FAIL: Operation executed when it should have been denied (RBAC restriction gap)
- ERROR: Test script encountered an unexpected exception (API limitation, transient issue, missing prerequisite) — not a policy failure but still surfaced
- SKIPPED: Test intentionally not executed (e.g. safety rules, reused singleton resources like Network Watcher)

Exit code logic:

- 0: No FAIL and no ERROR results
- 1: Any FAIL or any ERROR (errors are treated as non-zero to signal pipeline instability)

The console summary now differentiates these states:

- "All executed tests passed" (may include SKIPPED)
- "Tests completed with failures and errors" (both present)
- "Some tests failed" (failures only)
- "Tests encountered errors but no functional failures" (errors only)

### Phase 5: Report Export

Generates reports in multiple formats:

- **JSON**: Structured data for programmatic analysis
- **CSV**: Tabular data for Excel/data analysis
- **HTML**: Visual report with charts and filtering
- **TXT**: Summary for quick review

### Phase 6: Cleanup

- Removes test resource group
- Removes test service principal
- Cleans up role assignments

## Test Result Interpretation

### Test Statuses

- **PASS** ✓: Operation was correctly denied (AuthorizationFailed)
- **FAIL** ✗: Operation was allowed when it should be blocked
- **ERROR** ⚠: Unexpected error occurred (not authorization related)
- **SKIPPED** ⏭: Test intentionally not executed due to external prerequisites (provider/service key/infra) not provisioned in ephemeral test environment

### Expected Results

All executed tests (non-SKIPPED) should result in **PASS** status, meaning:

- The operation was attempted
- Azure RBAC blocked the operation
- An AuthorizationFailed error was returned

### Example Output

```text
═══════════════════════════════════════════════════════════════
  Restricted Subscription Owner - RBAC Test Suite
═══════════════════════════════════════════════════════════════

[PHASE 1] Setting up test environment...
  → Connecting to Azure subscription: 12345678-...
  → Verifying custom role exists: Restricted Subscription Owner
  → Creating test resource group: rg-rbac-test
  → Creating test service principal: sp-rbac-test
  → Assigning custom role to service principal...
  → Creating pre-requisite test resources...
    ✓ Created test VNET
    ✓ Created test route table
  ✓ Test environment initialized successfully
✓ Setup completed successfully

[PHASE 2] Testing Authorization & Policy restrictions...
  Testing authorization restrictions...
    ✓ New-AzPolicyAssignment - PASS
    ✓ New-AzPolicyDefinition - PASS
    ✓ New-AzRoleAssignment - PASS
    ✓ New-AzRoleDefinition - PASS
    ✓ New-AzResourceLock - PASS
    ✓ Remove-AzRoleAssignment - PASS
    ✓ New-AzPolicyExemption - PASS
  ✓ Authorization tests completed
✓ Authorization tests completed (7 tests)

[PHASE 3] Testing Networking restrictions...
  Testing networking restrictions...
    [Req #1] Testing Virtual Network restrictions...
    ✓ New-AzVirtualNetwork - PASS
    ✓ Set-AzVirtualNetwork (modify) - PASS
    ✓ Remove-AzVirtualNetwork - PASS
    ✓ Add-AzVirtualNetworkPeering - PASS
    [Req #2] Testing Gateway restrictions...
    ✓ New-AzVirtualNetworkGateway - PASS
    ...
✓ Networking tests completed (45 tests)

[PHASE 4] Calculating test results...
✓ Summary calculated

[PHASE 5] Exporting test results...
  → JSON report: Results\TestResults_20251104-153045.json
  → CSV report: Results\TestResults_20251104-153045.csv
  → HTML report: Results\TestResults_20251104-153045.html
  → Summary report: Results\TestSummary_20251104-153045.txt
✓ Results exported

[PHASE 6] Cleaning up test environment...
  → Cleaning up test resources...
    Removing resource group: rg-rbac-test
    ✓ Resource group removed
    Removing service principal: ...
    ✓ Service principal removed
  ✓ Cleanup completed
✓ Cleanup completed

═══════════════════════════════════════════════════════════════
  TEST SUMMARY
═══════════════════════════════════════════════════════════════
Total Tests:  52
Passed:       52
Failed:       0
Errors:       0
Duration:     00:05:32
═══════════════════════════════════════════════════════════════
✓ All tests passed successfully!
```

## Reports

### HTML Report Features

- Visual summary with color-coded statistics
- Detailed test results table
- Filterable by status (Pass/Fail/Error/SKIPPED)
- Requirement badges for easy identification
- Responsive design for viewing on any device

### JSON Report Structure

```json
{
  "testRun": {
    "timestamp": "2025-11-04T15:30:45Z",
    "customRoleName": "Restricted Subscription Owner",
    "subscription": "12345678-...",
    "location": "eastus",
    "testIdentity": "sp-rbac-test",
    "duration": "00:05:32",
    "results": [
      {
        "requirement": "1",
        "category": "Virtual Networks",
        "action": "Microsoft.Network/virtualNetworks/write",
        "operation": "New-AzVirtualNetwork",
        "expectedResult": "Denied",
        "actualResult": "Denied",
        "status": "PASS",
        "errorMessage": "AuthorizationFailed (expected)",
        "duration": "1.25s"
      }
    ],
    "summary": {
      "totalTests": 52,
      "passed": 50,
      "failed": 0,
      "errors": 0,
      "skipped": 2
    }
  }
}
```

## Troubleshooting

### Common Issues

**Issue**: "Custom role not found"

- **Solution**: Deploy the custom role before running tests

**Issue**: "Insufficient permissions to create service principal"

- **Solution**: Ensure you have Owner or User Access Administrator role

**Issue**: "Role assignment propagation delays"

- **Solution**: The script includes wait times, but you may need to increase them for large tenants

**Issue**: "Tests timing out"

- **Solution**: Some Azure operations are slow. Consider testing in batches or increasing timeouts

**Issue**: "SKIPPED tests appear unexpectedly"

- **Solution**: Review skip reasons in JSON/HTML report. These are predefined for operations requiring external, non-testable prerequisites (e.g., ExpressRoute circuits, Virtual Network Tap targets). Provision prerequisites or remove skip logic if you want to attempt full validation.

### Manual Cleanup

If the automated cleanup fails:

```powershell
# Remove resource group
Remove-AzResourceGroup -Name "rg-rbac-test" -Force

# Remove service principal
Get-AzADServicePrincipal -DisplayName "sp-rbac-test" | Remove-AzADServicePrincipal -Force

# Remove role assignments
Get-AzRoleAssignment -Scope "/subscriptions/12345..." | 
  Where-Object { $_.RoleDefinitionName -eq "Restricted Subscription Owner" } | 
  Remove-AzRoleAssignment
```

## CI/CD Integration

### Azure DevOps Pipeline Example

```yaml
trigger: none

pool:
  vmImage: 'windows-latest'

steps:
- task: AzurePowerShell@5
  inputs:
    azureSubscription: 'YourServiceConnection'
    ScriptType: 'FilePath'
    ScriptPath: '$(Build.SourcesDirectory)/CustomRoles/Tests/Test-CustomRole.ps1'
    ScriptArguments: '-SubscriptionId $(SubscriptionId) -SkipCleanup:$false'
    azurePowerShellVersion: 'LatestVersion'
  displayName: 'Run RBAC Tests'

- task: PublishTestResults@2
  inputs:
    testResultsFormat: 'NUnit'
    testResultsFiles: '**/TestResults_*.xml'
  displayName: 'Publish Test Results'
  condition: always()
```

### GitHub Actions Example

```yaml
name: RBAC Tests

on:
  workflow_dispatch:
  schedule:
    - cron: '0 0 * * 0'  # Weekly on Sunday

jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Run RBAC Tests
        shell: pwsh
        run: |
          ./CustomRoles/Tests/Test-CustomRole.ps1 -SubscriptionId ${{ secrets.SUBSCRIPTION_ID }}
      
      - name: Upload Test Results
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: test-results
          path: CustomRoles/Tests/Results/
```

## Best Practices

1. **Run tests in a non-production subscription** to avoid interference with production workloads
2. **Schedule regular test runs** (weekly/monthly) to catch drift
3. **Review failed tests immediately** as they indicate security gaps
4. **Archive test results** for compliance and audit purposes
5. **Test after any role modifications** to ensure restrictions still work
6. **Use separate service principals** for different environments
7. **Track SKIPPED tests** to avoid assuming unvalidated coverage; periodically reassess if prerequisites can be added.

## Compliance & Auditing

Test results provide evidence of:

- Least privilege access controls
- Separation of duties enforcement
- Policy-driven governance
- Network isolation boundaries
- Regulatory compliance (SOC 2, ISO 27001, etc.)

## Support

For issues or questions:

1. Review the troubleshooting section
2. Check test result error messages
3. Examine the detailed JSON/HTML reports
4. Verify custom role definition matches expectations

---

**Last Updated:** November 4, 2025
