<#
.SYNOPSIS
    Export test results in multiple formats

.DESCRIPTION
    Exports test results to JSON, CSV, and HTML formats for reporting and analysis
#>

function Export-TestResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$TestResults,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )

    try {
        # Create output directory if it doesn't exist
        if (-not (Test-Path $OutputPath)) {
            New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        }

        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

        # Export JSON
        $jsonPath = Join-Path $OutputPath "TestResults_$timestamp.json"
        $TestResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
        Write-Host "  → JSON report: $jsonPath" -ForegroundColor Gray

        # Export CSV
        $csvPath = Join-Path $OutputPath "TestResults_$timestamp.csv"
        $TestResults.TestRun.Results | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        Write-Host "  → CSV report: $csvPath" -ForegroundColor Gray

        # Export HTML
        $htmlPath = Join-Path $OutputPath "TestResults_$timestamp.html"
        $html = Generate-HTMLReport -TestResults $TestResults
        $html | Out-File -FilePath $htmlPath -Encoding UTF8
        Write-Host "  → HTML report: $htmlPath" -ForegroundColor Gray

        # Export summary text file
        $summaryPath = Join-Path $OutputPath "TestSummary_$timestamp.txt"
        $summary = Generate-SummaryReport -TestResults $TestResults
        $summary | Out-File -FilePath $summaryPath -Encoding UTF8
        Write-Host "  → Summary report: $summaryPath" -ForegroundColor Gray

    } catch {
        Write-Host "  ✗ Error exporting results: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Generate-HTMLReport {
    param([hashtable]$TestResults)

    $passedTests  = ($TestResults.TestRun.Results | Where-Object { $_.Status -eq "PASS" }).Count
    $failedTests  = ($TestResults.TestRun.Results | Where-Object { $_.Status -eq "FAIL" }).Count
    $errorTests   = ($TestResults.TestRun.Results | Where-Object { $_.Status -eq "ERROR" }).Count
    $skippedTests = ($TestResults.TestRun.Results | Where-Object { $_.Status -eq "SKIPPED" }).Count
    $totalTests = $TestResults.TestRun.Summary.TotalTests

    $passPercentage = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 2) } else { 0 }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>RBAC Test Results - $($TestResults.TestRun.CustomRoleName)</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .container { max-width: 1400px; margin: 0 auto; background-color: white; padding: 30px; box-shadow: 0 0 10px rgba(0,0,0,0.1); }
        h1 { color: #0078d4; border-bottom: 3px solid #0078d4; padding-bottom: 10px; }
        h2 { color: #333; margin-top: 30px; border-bottom: 2px solid #e0e0e0; padding-bottom: 5px; }
        .summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 20px; margin: 20px 0; }
        .summary-card { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; text-align: center; }
        .summary-card.passed { background: linear-gradient(135deg, #11998e 0%, #38ef7d 100%); }
        .summary-card.failed { background: linear-gradient(135deg, #eb3349 0%, #f45c43 100%); }
    .summary-card.error { background: linear-gradient(135deg, #f09819 0%, #edde5d 100%); }
    .summary-card.skipped { background: linear-gradient(135deg, #6c757d 0%, #95a5a6 100%); }
        .summary-card h3 { margin: 0 0 10px 0; font-size: 16px; opacity: 0.9; }
        .summary-card .number { font-size: 36px; font-weight: bold; margin: 0; }
        .info-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 15px; margin: 20px 0; }
        .info-item { padding: 10px; background-color: #f8f9fa; border-left: 4px solid #0078d4; }
        .info-item strong { color: #0078d4; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background-color: #0078d4; color: white; padding: 12px; text-align: left; font-weight: 600; }
        td { padding: 10px; border-bottom: 1px solid #e0e0e0; }
        tr:hover { background-color: #f8f9fa; }
        .status-pass { color: #28a745; font-weight: bold; }
        .status-fail { color: #dc3545; font-weight: bold; }
        .status-error { color: #ffc107; font-weight: bold; }
        .status-skipped { color: #6c757d; font-weight: bold; }
        .requirement-badge { display: inline-block; background-color: #0078d4; color: white; padding: 2px 8px; border-radius: 12px; font-size: 12px; margin-right: 5px; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 2px solid #e0e0e0; text-align: center; color: #666; font-size: 14px; }
        .filter-buttons { margin: 20px 0; }
        .filter-btn { padding: 8px 16px; margin-right: 10px; border: none; border-radius: 4px; cursor: pointer; font-weight: bold; }
        .filter-btn.all { background-color: #6c757d; color: white; }
        .filter-btn.pass { background-color: #28a745; color: white; }
        .filter-btn.fail { background-color: #dc3545; color: white; }
        .filter-btn.error { background-color: #ffc107; color: black; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔒 RBAC Test Results</h1>
        <p style="font-size: 18px; color: #666;">Custom Role: <strong>$($TestResults.TestRun.CustomRoleName)</strong></p>
        
        <div class="info-grid">
            <div class="info-item"><strong>Test Date:</strong> $($TestResults.TestRun.Timestamp)</div>
            <div class="info-item"><strong>Subscription:</strong> $($TestResults.TestRun.Subscription)</div>
            <div class="info-item"><strong>Location:</strong> $($TestResults.TestRun.Location)</div>
            <div class="info-item"><strong>Test Identity:</strong> $($TestResults.TestRun.TestIdentity)</div>
            <div class="info-item"><strong>Duration:</strong> $($TestResults.TestRun.Duration)</div>
        </div>

        <h2>Summary</h2>
        <div class="summary">
            <div class="summary-card">
                <h3>Total Tests</h3>
                <p class="number">$totalTests</p>
            </div>
            <div class="summary-card passed">
                <h3>Passed</h3>
                <p class="number">$passedTests</p>
                <p>$passPercentage%</p>
            </div>
            <div class="summary-card failed">
                <h3>Failed</h3>
                <p class="number">$failedTests</p>
            </div>
            <div class="summary-card error">
                <h3>Errors</h3>
                <p class="number">$errorTests</p>
            </div>
            <div class="summary-card skipped">
                <h3>Skipped</h3>
                <p class="number">$skippedTests</p>
            </div>
        </div>

        <h2>Detailed Results</h2>
        <table id="resultsTable">
            <thead>
                <tr>
                    <th>Req</th>
                    <th>Category</th>
                    <th>Action</th>
                    <th>Operation</th>
                    <th>Expected</th>
                    <th>Actual</th>
                    <th>Status</th>
                    <th>Duration</th>
                </tr>
            </thead>
            <tbody>
"@

    foreach ($result in $TestResults.TestRun.Results) {
        $statusClass = switch ($result.Status) {
            "PASS"    { "status-pass" }
            "FAIL"    { "status-fail" }
            "ERROR"   { "status-error" }
            "SKIPPED" { "status-skipped" }
        }

        $statusIcon = switch ($result.Status) {
            "PASS"    { "✓" }
            "FAIL"    { "✗" }
            "ERROR"   { "⚠" }
            "SKIPPED" { "⧗" }
        }

        $html += @"
                <tr class="$($result.Status.ToLower())">
                    <td><span class="requirement-badge">#$($result.Requirement)</span></td>
                    <td>$($result.Category)</td>
                    <td style="font-family: monospace; font-size: 11px;">$($result.Action)</td>
                    <td><strong>$($result.Operation)</strong></td>
                    <td>$($result.ExpectedResult)</td>
                    <td>$($result.ActualResult)</td>
                    <td class="$statusClass">$statusIcon $($result.Status)</td>
                    <td>$($result.Duration)</td>
                </tr>
"@
    }

    $html += @"
            </tbody>
        </table>

        <div class="footer">
            <p>Generated by Restricted Subscription Owner RBAC Test Suite</p>
            <p>Azure Cloud Adoption Framework - Landing Zone Identity & Access Management</p>
        </div>
    </div>
</body>
</html>
"@

    return $html
}

function Generate-SummaryReport {
    param([hashtable]$TestResults)

        $summary = @"
═══════════════════════════════════════════════════════════════
  RBAC TEST SUMMARY REPORT
═══════════════════════════════════════════════════════════════

Custom Role: $($TestResults.TestRun.CustomRoleName)
Test Date: $($TestResults.TestRun.Timestamp)
Subscription: $($TestResults.TestRun.Subscription)
Duration: $($TestResults.TestRun.Duration)

───────────────────────────────────────────────────────────────
TEST RESULTS
───────────────────────────────────────────────────────────────
Total Tests:  $($TestResults.TestRun.Summary.TotalTests)
Passed:       $($TestResults.TestRun.Summary.Passed)
Failed:       $($TestResults.TestRun.Summary.Failed)
Errors:       $($TestResults.TestRun.Summary.Errors)
Skipped:      $($TestResults.TestRun.Summary.Skipped)

───────────────────────────────────────────────────────────────
RESULTS BY REQUIREMENT
───────────────────────────────────────────────────────────────
"@

    $requirementGroups = $TestResults.TestRun.Results | Group-Object -Property Requirement | Sort-Object Name
    foreach ($group in $requirementGroups) {
        $reqPassed = ($group.Group | Where-Object { $_.Status -eq "PASS" }).Count
        $reqFailed = ($group.Group | Where-Object { $_.Status -eq "FAIL" }).Count
    $reqErrors = ($group.Group | Where-Object { $_.Status -eq "ERROR" }).Count
    $reqSkipped = ($group.Group | Where-Object { $_.Status -eq "SKIPPED" }).Count
        $reqTotal = $group.Count

        $summary += @"

Requirement #$($group.Name): $($group.Group[0].Category)
    Total: $reqTotal | Passed: $reqPassed | Failed: $reqFailed | Errors: $reqErrors | Skipped: $reqSkipped
"@
    }

    if ($TestResults.TestRun.Summary.Failed -gt 0) {
        $summary += @"


───────────────────────────────────────────────────────────────
FAILED TESTS
───────────────────────────────────────────────────────────────
"@
        $failedTests = $TestResults.TestRun.Results | Where-Object { $_.Status -eq "FAIL" }
        foreach ($test in $failedTests) {
            $summary += @"

[Req #$($test.Requirement)] $($test.Operation)
  Category: $($test.Category)
  Action: $($test.Action)
  Error: $($test.ErrorMessage)
"@
        }
    }

    if ($TestResults.TestRun.Summary.Errors -gt 0) {
        $summary += @"


───────────────────────────────────────────────────────────────
ERROR TESTS
───────────────────────────────────────────────────────────────
"@
        $errorTests = $TestResults.TestRun.Results | Where-Object { $_.Status -eq "ERROR" }
        foreach ($test in $errorTests) {
            $summary += @"

[Req #$($test.Requirement)] $($test.Operation)
  Category: $($test.Category)
  Action: $($test.Action)
  Error: $($test.ErrorMessage)
"@
        }
    }

        if ($TestResults.TestRun.Summary.Skipped -gt 0) {
                $summary += @"


───────────────────────────────────────────────────────────────
SKIPPED TESTS (Not executed - environment/provider prerequisite)
───────────────────────────────────────────────────────────────
"@
                $skippedTests = $TestResults.TestRun.Results | Where-Object { $_.Status -eq "SKIPPED" }
                foreach ($test in $skippedTests) {
                        $summary += @"

[Req #$($test.Requirement)] $($test.Operation)
    Category: $($test.Category)
    Action: $($test.Action)
    Reason: $($test.ErrorMessage)
"@
                }
        }

        $summary += @"


═══════════════════════════════════════════════════════════════
"@

    return $summary
}
