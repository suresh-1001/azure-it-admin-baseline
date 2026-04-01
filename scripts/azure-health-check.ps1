<#
.SYNOPSIS
    Azure IT Admin — Service Health & Infrastructure Diagnostics
.DESCRIPTION
    Performs a full sweep of Azure service health, resource health, active alerts,
    and VM status. Outputs a timestamped HTML report to the current directory.
.PARAMETER SubscriptionId
    Target Azure Subscription ID (defaults to current context)
.PARAMETER OutputPath
    Directory to save the HTML report (defaults to current directory)
.EXAMPLE
    .\azure-health-check.ps1 -SubscriptionId "xxxx-xxxx" -OutputPath "C:\Reports"
#>

param(
    [string]$SubscriptionId = "",
    [string]$OutputPath = "."
)

# ─── Connect & Context ──────────────────────────────────────────────────────
Write-Host "`n[Azure Health Check] Starting..." -ForegroundColor Cyan

if (-not (Get-AzContext)) {
    Write-Host "Not logged in. Running Connect-AzAccount..." -ForegroundColor Yellow
    Connect-AzAccount
}

if ($SubscriptionId) {
    Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}

$context = Get-AzContext
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$reportFile = Join-Path $OutputPath "azure-health-report_$timestamp.html"

Write-Host "Subscription : $($context.Subscription.Name)" -ForegroundColor Green
Write-Host "Tenant       : $($context.Tenant.Id)" -ForegroundColor Green

# ─── Collect Data ───────────────────────────────────────────────────────────

## 1. Resource Groups
Write-Host "`n[1/5] Fetching Resource Groups..." -ForegroundColor Cyan
$resourceGroups = Get-AzResourceGroup | Select-Object ResourceGroupName, Location, Tags

## 2. Virtual Machines
Write-Host "[2/5] Fetching VM Status..." -ForegroundColor Cyan
$vms = Get-AzVM -Status | Select-Object Name, ResourceGroupName, Location,
    @{N="PowerState"; E={$_.PowerState}},
    @{N="ProvisioningState"; E={$_.ProvisioningState}}

## 3. Active Alerts
Write-Host "[3/5] Fetching Active Alerts..." -ForegroundColor Cyan
$alerts = Get-AzAlert -State "Active" -ErrorAction SilentlyContinue |
    Select-Object Name, Severity, Description, StartDateTime

## 4. Defender Secure Score
Write-Host "[4/5] Fetching Defender Secure Score..." -ForegroundColor Cyan
$secureScore = Get-AzSecuritySecureScore -ErrorAction SilentlyContinue |
    Select-Object DisplayName, Score, MaxScore, Percentage

## 5. Public IP Addresses
Write-Host "[5/5] Fetching Public IPs..." -ForegroundColor Cyan
$publicIPs = Get-AzPublicIpAddress | Select-Object Name, ResourceGroupName,
    @{N="IPAddress"; E={$_.IpAddress}},
    @{N="AllocationMethod"; E={$_.PublicIpAllocationMethod}}

# ─── Build HTML Report ──────────────────────────────────────────────────────
Write-Host "`nGenerating HTML report..." -ForegroundColor Cyan

$html = @"
<!DOCTYPE html>
<html>
<head>
  <title>Azure Health Report — $timestamp</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 30px; color: #333; }
    h1 { color: #0078d4; }
    h2 { color: #005a9e; border-bottom: 2px solid #0078d4; padding-bottom: 5px; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 30px; }
    th { background: #0078d4; color: white; padding: 8px 12px; text-align: left; }
    td { padding: 7px 12px; border-bottom: 1px solid #ddd; }
    tr:nth-child(even) { background: #f5f5f5; }
    .running { color: green; font-weight: bold; }
    .stopped { color: red; font-weight: bold; }
    .header-meta { color: #666; font-size: 14px; margin-bottom: 30px; }
  </style>
</head>
<body>
  <h1>☁️ Azure Health Report</h1>
  <div class="header-meta">
    Subscription: <strong>$($context.Subscription.Name)</strong> &nbsp;|&nbsp;
    Generated: <strong>$timestamp</strong>
  </div>

  <h2>Resource Groups ($($resourceGroups.Count))</h2>
  <table>
    <tr><th>Name</th><th>Location</th></tr>
    $(($resourceGroups | ForEach-Object { "<tr><td>$($_.ResourceGroupName)</td><td>$($_.Location)</td></tr>" }) -join "`n")
  </table>

  <h2>Virtual Machines ($($vms.Count))</h2>
  <table>
    <tr><th>Name</th><th>Resource Group</th><th>Location</th><th>Power State</th></tr>
    $(($vms | ForEach-Object {
        $stateClass = if ($_.PowerState -match "running") { "running" } else { "stopped" }
        "<tr><td>$($_.Name)</td><td>$($_.ResourceGroupName)</td><td>$($_.Location)</td><td class='$stateClass'>$($_.PowerState)</td></tr>"
    }) -join "`n")
  </table>

  <h2>Active Alerts ($($alerts.Count))</h2>
  <table>
    <tr><th>Name</th><th>Severity</th><th>Description</th><th>Started</th></tr>
    $(($alerts | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.Severity)</td><td>$($_.Description)</td><td>$($_.StartDateTime)</td></tr>" }) -join "`n")
  </table>

  <h2>Defender Secure Score</h2>
  <table>
    <tr><th>Initiative</th><th>Score</th><th>Max Score</th><th>Percentage</th></tr>
    $(($secureScore | ForEach-Object { "<tr><td>$($_.DisplayName)</td><td>$($_.Score)</td><td>$($_.MaxScore)</td><td>$([math]::Round($_.Percentage * 100, 1))%</td></tr>" }) -join "`n")
  </table>

  <h2>Public IP Addresses ($($publicIPs.Count))</h2>
  <table>
    <tr><th>Name</th><th>Resource Group</th><th>IP Address</th><th>Allocation</th></tr>
    $(($publicIPs | ForEach-Object { "<tr><td>$($_.Name)</td><td>$($_.ResourceGroupName)</td><td>$($_.IPAddress)</td><td>$($_.AllocationMethod)</td></tr>" }) -join "`n")
  </table>
</body>
</html>
"@

$html | Out-File -FilePath $reportFile -Encoding UTF8
Write-Host "`n✅ Report saved: $reportFile" -ForegroundColor Green
