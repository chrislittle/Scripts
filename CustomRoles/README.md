# Azure Custom Roles

This directory contains custom Azure RBAC role definitions designed to provide granular access control aligned with Azure Landing Zone best practices.

---

## 📖 Documentation

- **[Test Framework Documentation](./Tests/README.md)** - Comprehensive testing guide including:
  - Interactive test selection and subscription picker
  - Test architecture and execution modes
  - Detailed test catalog with prerequisites
  - Report formats and troubleshooting
  - CI/CD integration examples

---

## Custom Roles

### Restricted Subscription Owner

**File:** `CustomRole_RestrictedSubscriptionOwner.json`

**Purpose:** A custom role based on the Subscription Owner built-in role with enhanced restrictions to prevent modification of networking infrastructure and Azure Policy governance controls.

#### Overview

This role provides comprehensive subscription-level administrative access while enforcing strict boundaries around network architecture and policy governance. It follows the Azure Landing Zone principle of policy-driven governance and subscription democratization, allowing application teams to manage their workloads within platform-defined guardrails.

---

## 🚀 Quick Start - Validate This Role

### Recommended: Interactive mode with safety prompts

```powershell
cd .\CustomRoles\Tests
.\Test-CustomRole.ps1 -Interactive -SafetyPrompts
```

This provides:

- ✅ Interactive menu to select specific test requirements
- ✅ Y/N confirmations for all destructive operations
- ✅ Resource provider registration check with prompt to auto-register if needed
- ✅ Region selection picker (no need to specify `-Location`)
- ✅ Current subscription auto-detected (no need to specify `-SubscriptionId`)

### For CI/CD pipelines

```powershell
.\Test-CustomRole.ps1 -SubscriptionId <subId> -Location westus2
```

📖 **[Full Test Documentation](./Tests/README.md)** - Detailed guide including test architecture, advanced options, and troubleshooting

---

## Role Definition

### Base Permissions

- **Actions:** `*` (all actions, equivalent to Subscription Owner)
- **Scope:** Subscription level

### Restrictions (NotActions)

The role implements the following restrictions to maintain platform control and security boundaries:

#### 1. Authorization & Governance

- **`Microsoft.Authorization/*/write`** - Blocks creating or modifying:
  - Role assignments
  - Custom role definitions
  - Policy assignments, definitions, exemptions, and policy sets
  - Resource locks
- **`Microsoft.Authorization/*/Delete`** - Blocks deletion of authorization resources

#### 2. Virtual Networks (Requirement #1)

- **`Microsoft.Network/virtualNetworks/*`** - Blocks all VNET operations including:
  - Creating, modifying, or deleting virtual networks
  - Subnet management
  - Virtual network peering
  - DNS settings
  - Service endpoints within VNETs

#### 3. ExpressRoute & VPN Gateways (Requirement #2)

- **`Microsoft.Network/vpnGateways/*`** - VPN gateways
- **`Microsoft.Network/expressRouteCircuits/*`** - ExpressRoute circuits
- **`Microsoft.Network/expressRouteGateways/*`** - ExpressRoute gateways
- **`Microsoft.Network/expressRoutePorts/*`** - ExpressRoute ports
- **`Microsoft.Network/expressRoutePortsLocations/*`** - ExpressRoute port locations
- **`Microsoft.Network/expressRouteCrossConnections/*`** - ExpressRoute cross-connections
- **`Microsoft.Network/virtualNetworkGateways/*`** - Virtual network gateways

#### 4. Route Tables (Requirement #3)

- **`Microsoft.Network/routeTables/*`** - All route table operations including routes

#### 5. Front Door (Requirement #4)

- **`Microsoft.Network/frontDoors/*`** - Azure Front Door instances
- **`Microsoft.Network/frontdoorWebApplicationFirewallPolicies/*`** - Front Door WAF policies
- **`Microsoft.Cdn/profiles/*`** - CDN profiles (used by Front Door)

#### 6. Load Balancers (Requirement #5)

- **`Microsoft.Network/loadBalancers/*`** - All load balancer types
- **`Microsoft.Network/applicationGateways/*`** - Application Gateways
- **`Microsoft.Network/applicationGatewayWebApplicationFirewallPolicies/*`** - Application Gateway WAF policies

#### 7. Private Link & Private Endpoints (Requirement #6)

- **`Microsoft.Network/privateEndpoints/*`** - Private endpoints
- **`Microsoft.Network/privateLinkServices/*`** - Private link services
- **`Microsoft.Network/privateDnsZones/virtualNetworkLinks/*`** - Private DNS zone VNET links

#### 8. NAT Gateways (Requirement #7)

- **`Microsoft.Network/natGateways/*`** - NAT gateway operations

#### 9. Network Watcher Tools (Requirement #8)

- **`Microsoft.Network/networkWatchers/*`** - Network Watcher resources (includes connection monitors)

#### 10. Service Endpoints (Requirement #9)

- **`Microsoft.Network/serviceEndpointPolicies/*`** - Service endpoint policies
- **`Microsoft.Network/networkIntentPolicies/*`** - Network intent policies

#### 11. Virtual WAN (Requirement #10)

- **`Microsoft.Network/virtualWans/*`** - Virtual WAN instances (create-only test)
- **`Microsoft.Network/virtualHubs/*`** - Virtual hubs (not tested; hard dependency on Virtual WAN)
- **`Microsoft.Network/vpnSites/*`** - VPN sites
- **`Microsoft.Network/vpnServerConfigurations/*`** - VPN server configurations
- **`Microsoft.Network/p2sVpnGateways/*`** - Point-to-site VPN gateways

#### 12. Traffic Manager (Requirement #11)

- **`Microsoft.Network/trafficManagerProfiles/*`** - Traffic Manager profiles

#### 13. Virtual Network Tap (Requirement #12)

- **`Microsoft.Network/virtualNetworkTaps/*`** - Virtual network TAP resources

#### 14. Azure Firewall (Requirement #13)

- **`Microsoft.Network/azureFirewalls/*`** - Azure Firewall instances
- **`Microsoft.Network/firewallPolicies/*`** - Firewall policies
- **`Microsoft.Network/ipGroups/*`** - IP groups (used by firewalls)

#### 15. DDoS Protection (Requirement #14)

- **`Microsoft.Network/ddosCustomPolicies/*`** - DDoS custom policies
- **`Microsoft.Network/ddosProtectionPlans/*`** - DDoS protection plans

### Design Rationale

This role follows the **Application Owner** pattern from the Azure Landing Zone accelerator with additional networking restrictions. The design ensures:

1. **Separation of Duties:** Network infrastructure is managed centrally by the platform team (NetOps)
2. **Policy-Driven Governance:** Policy guardrails cannot be modified by subscription owners
3. **Least Privilege:** Application teams have full autonomy within their subscription while respecting platform boundaries
4. **Defense in Depth:** Both write and delete operations are blocked on critical infrastructure

### Deployment

#### Prerequisites

- Azure PowerShell module installed
- Authenticated to Azure with appropriate permissions to create custom roles
- Subscription ID where the role will be assignable

##### Steps

1. **Update the AssignableScopes:**

   ```json
   "AssignableScopes": [
     "/subscriptions/{subscriptionId}"
   ]
   ```

   Replace `{subscriptionId}` with your target subscription ID(s).

2. **Create the role definition:**

   ```powershell
   New-AzRoleDefinition -InputFile ".\CustomRole_RestrictedSubscriptionOwner.json"
   ```

3. **Assign the role to users/groups:**

   ```powershell
   New-AzRoleAssignment -ObjectId <user-or-group-object-id> `
     -RoleDefinitionName "Restricted Subscription Owner" `
     -Scope "/subscriptions/<subscription-id>"
   ```

#### Validation

To verify the role was created successfully:

```powershell
Get-AzRoleDefinition -Name "Restricted Subscription Owner"
```

#### Management

##### Update the role

```powershell
Set-AzRoleDefinition -InputFile ".\CustomRole_RestrictedSubscriptionOwner.json"
```

##### Delete the role

```powershell
Remove-AzRoleDefinition -Name "Restricted Subscription Owner"
```

#### Use Cases

This role is ideal for:

- **Application Landing Zone Owners:** Teams managing application workloads within a subscription
- **DevOps Teams:** Teams requiring broad subscription access without network architecture control
- **Multi-tenant Environments:** Where network infrastructure must remain under central control
- **Compliance Requirements:** Environments requiring strict separation between network and application teams

#### Compliance & Best Practices

This role aligns with:

- Azure Landing Zone design principles
- Microsoft Cloud Adoption Framework guidance
- Zero Trust network security principles
- Principle of Least Privilege (PoLP)
- Separation of duties requirements

#### Related Roles

Consider combining this role with other Landing Zone custom roles:

- **Network Management (NetOps):** For centralized network operations
- **Security Operations (SecOps):** For security oversight
- **Application Access Administrator:** For delegated access management within the application

#### References

- [Azure Landing Zone Identity and Access Management](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-area/identity-access-landing-zones)
- [Azure Built-in Roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles)
- [Azure Custom Roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/custom-roles)
- [Subscription Democratization](https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/design-principles#subscription-democratization)

---

### Test Harness & Validation Automation

This repository includes a PowerShell test harness under `CustomRoles/Tests` that validates the enforced restrictions of the `Restricted Subscription Owner` custom role across 15 requirement categories (Authorization + 14 networking/control areas).

Key scripts:

- `Test-CustomRole.ps1` – Orchestrates all phases (environment init, role assignment, phased tests, export, cleanup).
- `Initialize-TestEnvironment.ps1` – Creates an isolated test resource group, a time-scoped service principal, and prerequisite network artifacts. All resource names are suffixed with a timestamp (`yyyyMMdd-HHmmss`) for uniqueness and safe re-runs.
- `Test-AuthorizationRestrictions.ps1` / `Test-NetworkingRestrictions.ps1` – Execute granular PASS / FAIL / ERROR checks against blocked operations.
- `Clear-TestEnvironment.ps1` – Performs safe cleanup (replaces deprecated `Cleanup-TestEnvironment.ps1`). Handles resource group deletion and service principal removal with retry and pre-removal of role assignments.
- `Export-TestResults.ps1` – Exports structured results for audit purposes.

Safety features:

- `-SafetyPrompts` switch adds interactive Y/N confirmations for service principal creation, context switching, and cleanup deletion operations.
- `-Interactive` switch enables granular test selection via menu (choose specific requirements to test).
- Defensive checks ensure only the temporary service principal's RBAC assignments are created/removed; no existing user RBAC is altered.
- Retry logic on service principal deletion mitigates eventual consistency delays in Azure AD.
- Resource provider registration validation with optional auto-registration.

Additional test execution notes:

- If you omit `-Location` or pass an empty string, the script displays an indexed list of available Azure regions and prompts you to choose.
- At completion, Phase 6 invokes `Clear-TestEnvironment` unless `-SkipCleanup` is provided.
- Backward compatibility: The previous `Cleanup-TestEnvironment.ps1` was removed; any external automation should update references to `Clear-TestEnvironment.ps1` and the function `Clear-TestEnvironment`.

#### Skipped / Excluded Tests

Some operations are intentionally skipped because they require provider or infrastructure prerequisites not feasible in an ephemeral validation run or because a resource failed to reach a ready provisioning state within a bounded wait window:

- **ExpressRoute Circuit (Requirement #2)** – Needs a valid service provider service key plus physical provisioning; reported as SKIPPED with reason.
- **Virtual Network Tap (Requirement #12)** – Requires a target NIC/VM and packet capture configuration; reported as SKIPPED with reason.

Skip entries appear in output with a gray preface line and are included in the exported results for audit transparency.

These appear near the top of Requirement #10 logic and inside the initialization script. Increasing the timeout is helpful in regions with elevated provisioning latency.

Why bounded polling?

- Ensures determinism and prevents runaway waits in CI.
- Distinguishes genuine RBAC denial from transient platform provisioning.
- Captures platform instability (timeouts) as SKIPPED rather than FAIL to avoid false negatives.

Future enhancements under consideration:

- Optional parameter to treat readiness timeouts as ERROR (strict mode).
- Emit per-resource provisioning and deletion duration metrics.
- Centralized generic `Wait-AzResourceSucceeded` helper for reuse across all network resource types.
- Automatic hub connection teardown (if added in extended tests) before delete verification.

#### Test Coverage: Create / Modify / Delete Operations

The test harness validates RBAC restrictions across three operation types for most resource categories:

| Requirement | Resource Type | Create | Modify | Delete | Notes |
|-------------|---------------|--------|--------|--------|-------|
| **#1** | Virtual Networks | ✓ | ✓ | ✓ | Full CRUD coverage |
| | VNET Peering | ✓ | - | - | Single-op test (create blocked) |
| **#2** | VPN Gateway | ✓ | - | - | Create-only (modify/delete slow to test) |
| **#3** | Route Tables | ✓ | ✓ | ✓ | Full CRUD coverage |
| **#4** | Front Door | ✓ | - | - | Create-only (modify/delete slow to test) |
| | CDN Profile | ✓ | - | - | Create-only (modify/delete slow to test) |
| **#5** | Load Balancer | ✓ | - | - | Create-only (modify/delete slow to test) |
| | Application Gateway | ✓ | - | - | Create-only (modify/delete slow to test) |
| **#6** | Private Endpoint | ✓ | - | - | Create-only (modify/delete slow to test) |
| | Private Link Service | ✓ | - | - | Create-only (modify/delete slow to test) |
| **#7** | NAT Gateway | ✓ | ✓ | ✓ | Full CRUD coverage (Tier 1) |
| **#8** | Network Watcher | ✓ | ✓ | ✓ | Full CRUD coverage (Tier 1) |
| **#9** | Service Endpoint Policy | ✓ | ✓ | ✓ | Full CRUD coverage (Tier 1) |
| **#10** | Virtual WAN | ✓ | - | - | Create-only test (RBAC denial only) |
| | Virtual Hub | - | - | - | Not tested (hard dependency on Virtual WAN) |
| **#11** | Traffic Manager | ✓ | ✓ | ✓ | Full CRUD coverage (Tier 1) |
| **#13** | Firewall Policy | ✓ | ✓ | ✓ | Full CRUD coverage (Tier 1) |
| | IP Group | ✓ | ✓ | ✓ | Full CRUD coverage (Tier 1) |
| | Azure Firewall | ✓ | - | - | Create-only (5–8 min provision time) |
| **#14** | DDoS Protection Plan | ✓ | - | - | Create-only test (RBAC denial only; no provisioning or cost incurred). |

**Tier 1 Resources:** Fast-provisioning resources (~2.5 min total) that support full create/modify/delete testing with minimal cost (~$0.05 per test run).

**Tier 2 Resources (Create-Only):** Slow-provisioning or expensive resources where modify/delete tests are excluded to avoid long setup times (5–45 minutes) or high costs.

##### Tag Modification Behavior

The modify tests for resources with limited mutable properties (Network Watcher, Firewall Policy, Service Endpoint Policy, DDoS Plan) use tag updates via `Set-Az*` cmdlets to validate RBAC denial. These cmdlets require the resource-specific `/write` permission (e.g., `Microsoft.Network/firewallPolicies/write`), which is blocked by the `NotActions` list.

**Note:** Users with this restricted role can still modify tags using the dedicated tag API (`Update-AzTag`), which requires only `Microsoft.Resources/tags/write` (not blocked by this role). This is by design, as tag modifications:

- Do not alter network functionality or routing
- Are commonly used for cost allocation and governance
- Are auditable via Activity Log

If your compliance requirements demand zero mutations to network resource metadata, add `Microsoft.Resources/tags/write` to the `NotActions` list (note: this blocks tagging on all subscription resources, not just networking).

### Change Log (Recent)

- 2025-11-06: **Resource provider registration validation** – Added `Test-AzureProviderRegistration` function with interactive prompt to auto-register Microsoft.Network and Microsoft.Storage providers if not registered. Improves first-run experience and provides clear guidance when providers are missing.
- 2025-11-06: **Virtual WAN/Hub simplification** – Changed Requirement #10 to create-only tests (RBAC denial only) to eliminate complex lifecycle testing (20+ min execution time eliminated). Removed baseline Virtual WAN/Hub provisioning from setup, removed routing-aware cleanup logic (Wait-VirtualHubDeletable, WAN deletion gating), updated menu and coverage table to reflect create-only testing.
- 2025-11-06: Removed DDoS skip-by-default behavior; Requirement #14 now always executes RBAC create denial test (no provisioning, no cost). Enhanced Virtual Hub deletion wait with routing status polling (up to 900s) and elapsed-time progress messaging.
- 2025-11-05: Added Tier 1 modify/delete test coverage for 8 resource types (NAT Gateway, Network Watcher, Service Endpoint Policy, Virtual WAN, Virtual Hub, Traffic Manager, Firewall Policy, IP Group). Enhanced unique resource naming across all provisioned test resources.
- 2025-11-05: Replaced cleanup function with `Clear-TestEnvironment`; added robust public IP resolution, fixed Application Gateway SKU binding, NAT Gateway & Firewall parameter corrections, added README test harness section.
- 2025-11-04: Added `-SafetyPrompts`, unique timestamp-based naming, and comprehensive networking restriction tests.

**Last Updated:** November 6, 2025
