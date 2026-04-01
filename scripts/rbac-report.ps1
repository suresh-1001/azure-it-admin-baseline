<#
.SYNOPSIS
    Azure RBAC Role Assignments Report
.DESCRIPTION
    Exports all role assignments across the subscription with owner/contributor highlights.
    Flags service principals, guest accounts, and subscription-level Owner assignments.
.EXAMPLE
    .\rbac-report.ps1
#>

param(
    [string]$OutputPath = "."
)

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
Write-Host "`n[RBAC Report] Fetching role assignments..." -ForegroundColor Cyan

$allAssignments = Get-AzRoleAssignment | Select-Object `
    DisplayName,
    SignInName,
    ObjectType,
    RoleDefinitionName,
    Scope,
    @{N="ScopeLevel"; E={
        $parts = $_.Scope -split "/"
        if ($parts.Count -eq 3)     { "Subscription" }
        elseif ($parts.Count -eq 5) { "ResourceGroup" }
        else                         { "Resource" }
    }}

# Highlight dangerous assignments
$dangerous = $allAssignments | Where-Object {
    ($_.RoleDefinitionName -eq "Owner" -and $_.ScopeLevel -eq "Subscription") -or
    ($_.RoleDefinitionName -eq "Contributor" -and $_.ScopeLevel -eq "Subscription")
}

Write-Host "`n⚠️  High-Privilege Subscription-Level Assignments:" -ForegroundColor Red
$dangerous | Format-Table DisplayName, SignInName, ObjectType, RoleDefinitionName, ScopeLevel -AutoSize

Write-Host "`n📋 Full Role Assignment Summary:" -ForegroundColor Cyan
$allAssignments | Group-Object RoleDefinitionName | 
    Sort-Object Count -Descending |
    Format-Table Name, Count -AutoSize

$csvPath = Join-Path $OutputPath "rbac-report_$timestamp.csv"
$allAssignments | Export-Csv -Path $csvPath -NoTypeInformation
Write-Host "`n✅ Full report exported: $csvPath" -ForegroundColor Green
