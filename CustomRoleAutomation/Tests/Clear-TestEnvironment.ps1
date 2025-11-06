<#
.SYNOPSIS
    Clear test environment resources.
.DESCRIPTION
    Removes test resource group and service principal created during tests.
#>

function Clear-TestEnvironment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,
        [Parameter(Mandatory = $false)]
        [switch]$SafetyPrompts
    )

    try {
        Write-Host "  → Cleaning up test resources..." -ForegroundColor Gray

        # Remove test resource group
        if ($Context.ResourceGroupName) {
            $rgName = $Context.ResourceGroupName
            $proceed = $true
            if ($SafetyPrompts -or ($Context.SafetyPrompts)) {
                $resp = Read-Host "    Confirm deletion of resource group '$rgName'? (Y/N)"
                if ($resp -notin @('Y','y')) { $proceed = $false; Write-Host "    ⚠ Skipped resource group deletion by user choice" -ForegroundColor Yellow }
            }
            if ($proceed) {
                Write-Host "    Removing resource group: $rgName" -ForegroundColor Gray
                try {
                    Remove-AzResourceGroup -Name $rgName -Force -ErrorAction SilentlyContinue | Out-Null
                    Write-Host "    ✓ Resource group removed" -ForegroundColor Gray
                } catch {
                    Write-Host "    ⚠ Could not remove resource group: $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }

        # Remove service principal (only if we created it)
        if ($Context.ServicePrincipalId -and $Context.ServicePrincipalCreatedByUs) {
            $spId = $Context.ServicePrincipalId
            $appObjId = $Context.ServicePrincipalApplicationObjectId
            $proceedSp = $true
            if ($SafetyPrompts -or ($Context.SafetyPrompts)) {
                $resp = Read-Host "    Confirm deletion of TEST-CREATED service principal '$spId'? (Y/N)"
                if ($resp -notin @('Y','y')) { $proceedSp = $false; Write-Host "    ⚠ Skipped service principal deletion by user choice" -ForegroundColor Yellow }
            }
            if ($proceedSp) {
                Write-Host "    Removing service principal: $spId" -ForegroundColor Gray
                $maxAttempts = 5
                $attempt = 0
                $removed = $false
                while (-not $removed -and $attempt -lt $maxAttempts) {
                    $attempt++
                    try {
                        # Remove role assignments first (repeat every attempt in case of eventual consistency)
                        Get-AzRoleAssignment -ObjectId $spId -ErrorAction SilentlyContinue | ForEach-Object {
                            try { Remove-AzRoleAssignment -ObjectId $spId -Scope $_.Scope -RoleDefinitionId $_.RoleDefinitionId -ErrorAction SilentlyContinue | Out-Null } catch {}
                        }
                        Remove-AzADServicePrincipal -ObjectId $spId -Confirm:$false -ErrorAction Stop | Out-Null
                        # Verify removal
                        $check = Get-AzADServicePrincipal -ObjectId $spId -ErrorAction SilentlyContinue
                        if (-not $check) {
                            Write-Host "    ✓ Service principal removed (attempt $attempt)" -ForegroundColor Gray
                            $removed = $true
                        } else {
                            Write-Host "    → Principal still present after deletion attempt $attempt; waiting 8s" -ForegroundColor Yellow
                            Start-Sleep -Seconds 8
                        }
                    } catch {
                        Write-Host "    ⚠ Attempt $attempt failed to remove service principal: $($_.Exception.Message)" -ForegroundColor Yellow
                        if ($attempt -lt $maxAttempts) { Start-Sleep -Seconds 8 }
                    }
                }
                if (-not $removed) {
                    Write-Host "    ⚠ Service principal not confirmed removed after $maxAttempts attempts" -ForegroundColor Yellow
                }

                # Optional: remove backing application object if created by us and principal removed
                if ($removed -and $appObjId) {
                    try {
                        $appCheck = Get-AzADApplication -ObjectId $appObjId -ErrorAction SilentlyContinue
                        if ($appCheck) {
                            Remove-AzADApplication -ObjectId $appObjId -ErrorAction SilentlyContinue | Out-Null
                            $appVerify = Get-AzADApplication -ObjectId $appObjId -ErrorAction SilentlyContinue
                            if (-not $appVerify) { Write-Host "    ✓ Backing application object removed" -ForegroundColor Gray } else { Write-Host "    ⚠ Application object still present post-removal attempt" -ForegroundColor Yellow }
                        }
                    } catch { Write-Host "    ⚠ Failed to remove backing application object: $($_.Exception.Message)" -ForegroundColor Yellow }
                } elseif ($appObjId -and -not $removed) {
                    Write-Host "    → Skipping application removal because service principal removal not confirmed" -ForegroundColor DarkGray
                }
            }
        } elseif ($Context.ServicePrincipalId -and -not $Context.ServicePrincipalCreatedByUs) {
            Write-Host "    (Skipping deletion of pre-existing service principal)" -ForegroundColor DarkGray
        }

        Write-Host "  ✓ Cleanup completed" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Cleanup error: $($_.Exception.Message)" -ForegroundColor Red
    }
}
