<#
.SYNOPSIS
    Azure Security Posture Audit Script
.DESCRIPTION
    Audits MFA status, Defender Secure Score, RBAC assignments,
    NSG open ports, and storage account public access.
    Outputs findings to console and exports a CSV summary.
.EXAMPLE
    .\security-audit.ps1
#>

param(
    [string]$OutputPath = "."
)

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$findings = [System.Collections.Generic.List[PSObject]]::new()

function Add-Finding {
    param($Category, $Severity, $Resource, $Issue, $Recommendation)
    $findings.Add([PSCustomObject]@{
        Category       = $Category
        Severity       = $Severity
        Resource       = $Resource
        Issue          = $Issue
        Recommendation = $Recommendation
    })
}

Write-Host "`n[Security Audit] Azure Security Posture Check" -ForegroundColor Cyan

# ─── 1. Defender Secure Score ─────────────────────────────────────────────
Write-Host "`n[1/5] Defender for Cloud — Secure Score..." -ForegroundColor Yellow

$scores = Get-AzSecuritySecureScore -ErrorAction SilentlyContinue
foreach ($score in $scores) {
    $pct = [math]::Round($score.Percentage * 100, 1)
    $color = if ($pct -ge 75) { "Green" } elseif ($pct -ge 50) { "Yellow" } else { "Red" }
    Write-Host "  $($score.DisplayName): $pct% ($($score.Score)/$($score.MaxScore))" -ForegroundColor $color

    if ($pct -lt 75) {
        Add-Finding "Defender" "High" $score.DisplayName "Secure Score below 75% ($pct%)" "Review and remediate top Defender recommendations"
    }
}

# Top recommendations
$recs = Get-AzSecurityTask -ErrorAction SilentlyContinue | 
    Where-Object { $_.State -ne "Resolved" } |
    Select-Object RecommendationName, ResourceType, State |
    Sort-Object RecommendationName

Write-Host "  Open Recommendations: $($recs.Count)" -ForegroundColor $(if ($recs.Count -gt 10) {"Red"} else {"Yellow"})

# ─── 2. MFA Status ────────────────────────────────────────────────────────
Write-Host "`n[2/5] Checking Conditional Access / MFA Policies..." -ForegroundColor Yellow

# Requires Microsoft.Graph module
if (Get-Module -ListAvailable -Name Microsoft.Graph.Identity.SignIns) {
    try {
        $caPolicies = Get-MgIdentityConditionalAccessPolicy -ErrorAction Stop
        $mfaPolicies = $caPolicies | Where-Object {
            $_.GrantControls.BuiltInControls -contains "mfa" -and $_.State -eq "enabled"
        }
        Write-Host "  Active MFA CA Policies: $($mfaPolicies.Count)" -ForegroundColor $(if ($mfaPolicies.Count -gt 0) {"Green"} else {"Red"})

        if ($mfaPolicies.Count -eq 0) {
            Add-Finding "Identity" "Critical" "Conditional Access" "No MFA Conditional Access policy enabled" "Create and enable a CA policy requiring MFA for all users"
        }
    } catch {
        Write-Host "  Graph connection not available — skipping MFA check" -ForegroundColor Gray
    }
} else {
    Write-Host "  Microsoft.Graph module not installed — skipping MFA check" -ForegroundColor Gray
    Write-Host "  Install with: Install-Module Microsoft.Graph -Scope CurrentUser" -ForegroundColor Gray
}

# ─── 3. RBAC — Over-Privileged Accounts ──────────────────────────────────
Write-Host "`n[3/5] RBAC Role Assignments..." -ForegroundColor Yellow

$ownerAssignments = Get-AzRoleAssignment | Where-Object { $_.RoleDefinitionName -eq "Owner" }
Write-Host "  Owner assignments: $($ownerAssignments.Count)" -ForegroundColor $(if ($ownerAssignments.Count -gt 3) {"Red"} else {"Green"})

foreach ($assignment in $ownerAssignments) {
    Write-Host "    👤 $($assignment.DisplayName) ($($assignment.SignInName)) — Scope: $($assignment.Scope)" -ForegroundColor Yellow
    if ($assignment.Scope -eq "/subscriptions/$($(Get-AzContext).Subscription.Id)") {
        Add-Finding "RBAC" "High" $assignment.DisplayName "Owner role at subscription scope" "Apply least privilege — reduce to Contributor or custom role where possible"
    }
}

$contributorAssignments = Get-AzRoleAssignment | Where-Object { $_.RoleDefinitionName -eq "Contributor" }
Write-Host "  Contributor assignments: $($contributorAssignments.Count)" -ForegroundColor White

# ─── 4. NSG — Open Dangerous Ports ──────────────────────────────────────
Write-Host "`n[4/5] NSG — Checking for Open Dangerous Ports..." -ForegroundColor Yellow

$dangerousPorts = @("22", "3389", "23", "21", "1433", "3306", "5432", "6379")
$nsgs = Get-AzNetworkSecurityGroup

foreach ($nsg in $nsgs) {
    foreach ($rule in $nsg.SecurityRules) {
        if ($rule.Direction -eq "Inbound" -and $rule.Access -eq "Allow") {
            $isOpenToInternet = ($rule.SourceAddressPrefix -eq "*" -or $rule.SourceAddressPrefix -eq "Internet" -or $rule.SourceAddressPrefix -eq "0.0.0.0/0")
            if ($isOpenToInternet) {
                foreach ($port in $dangerousPorts) {
                    if ($rule.DestinationPortRange -eq "*" -or $rule.DestinationPortRange -eq $port -or $rule.DestinationPortRanges -contains $port) {
                        Write-Host "  ⚠️  $($nsg.Name) allows port $port from Internet (Rule: $($rule.Name))" -ForegroundColor Red
                        Add-Finding "Network" "Critical" $nsg.Name "Port $port open to Internet via rule '$($rule.Name)'" "Restrict source to specific IP range or remove rule"
                    }
                }
            }
        }
    }
}

# ─── 5. Storage — Public Access ──────────────────────────────────────────
Write-Host "`n[5/5] Storage Accounts — Public Access Check..." -ForegroundColor Yellow

$storageAccounts = Get-AzStorageAccount
foreach ($sa in $storageAccounts) {
    if ($sa.AllowBlobPublicAccess -eq $true) {
        Write-Host "  ⚠️  $($sa.StorageAccountName) has public blob access ENABLED" -ForegroundColor Red
        Add-Finding "Storage" "High" $sa.StorageAccountName "Blob public access is enabled" "Set AllowBlobPublicAccess=false unless explicitly required"
    } else {
        Write-Host "  ✅ $($sa.StorageAccountName) — public access disabled" -ForegroundColor Green
    }

    if ($sa.EnableHttpsTrafficOnly -eq $false) {
        Add-Finding "Storage" "Medium" $sa.StorageAccountName "HTTP traffic allowed (HTTPS not enforced)" "Enable HTTPS-only traffic on storage account"
    }
}

# ─── Summary ──────────────────────────────────────────────────────────────
Write-Host "`n─── FINDINGS SUMMARY ─────────────────────────────────────────────" -ForegroundColor Cyan

$critical = $findings | Where-Object { $_.Severity -eq "Critical" }
$high     = $findings | Where-Object { $_.Severity -eq "High" }
$medium   = $findings | Where-Object { $_.Severity -eq "Medium" }

Write-Host "  🔴 Critical : $($critical.Count)" -ForegroundColor Red
Write-Host "  🟠 High     : $($high.Count)" -ForegroundColor DarkYellow
Write-Host "  🟡 Medium   : $($medium.Count)" -ForegroundColor Yellow
Write-Host "  Total       : $($findings.Count)" -ForegroundColor White

$csvPath = Join-Path $OutputPath "security-audit_$timestamp.csv"
$findings | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "`n✅ Findings exported: $csvPath" -ForegroundColor Green
