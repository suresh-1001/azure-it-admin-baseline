<#
.SYNOPSIS
    Azure Network Troubleshooting Toolkit
.DESCRIPTION
    Automated diagnostics for Azure networking issues: VNet peering, NSG rules,
    DNS resolution, connectivity tests, and latency checks.
.PARAMETER ResourceGroup
    Resource group containing the target VM or resource
.PARAMETER VMName
    Name of the VM to run diagnostics from (requires Network Watcher)
.EXAMPLE
    .\network-troubleshoot.ps1 -ResourceGroup "rg-networking-prod" -VMName "vm-web-01"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,

    [string]$VMName = "",
    [string]$TargetAddress = "8.8.8.8",
    [int]$TargetPort = 443
)

Write-Host "`n[Network Troubleshoot] Azure Network Diagnostics" -ForegroundColor Cyan
Write-Host "Resource Group : $ResourceGroup" -ForegroundColor Green
Write-Host "Target Address : $TargetAddress`:$TargetPort`n" -ForegroundColor Green

# ─── 1. VNet Peering Status ────────────────────────────────────────────────
Write-Host "─── [1] VNet Peering Status ──────────────────────────────────────" -ForegroundColor Yellow

$vnets = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
foreach ($vnet in $vnets) {
    $peerings = Get-AzVirtualNetworkPeering -ResourceGroupName $ResourceGroup -VirtualNetworkName $vnet.Name
    if ($peerings) {
        foreach ($peer in $peerings) {
            $status = $peer.PeeringState
            $color = if ($status -eq "Connected") { "Green" } else { "Red" }
            Write-Host "  $($vnet.Name) <-> $($peer.RemoteVirtualNetwork.Id.Split('/')[-1]) : $status" -ForegroundColor $color
        }
    } else {
        Write-Host "  $($vnet.Name): No peerings configured" -ForegroundColor Gray
    }
}

# ─── 2. NSG Rules Summary ─────────────────────────────────────────────────
Write-Host "`n─── [2] NSG Rules Summary ────────────────────────────────────────" -ForegroundColor Yellow

$nsgs = Get-AzNetworkSecurityGroup -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue
foreach ($nsg in $nsgs) {
    Write-Host "`n  NSG: $($nsg.Name)" -ForegroundColor Cyan
    $inbound = $nsg.SecurityRules | Where-Object { $_.Direction -eq "Inbound" } | 
        Sort-Object Priority |
        Select-Object Name, Priority, Protocol, SourceAddressPrefix, DestinationPortRange, Access
    
    $inbound | Format-Table -AutoSize | Out-String | ForEach-Object { Write-Host "  $_" }
}

# ─── 3. DNS Resolution Test ───────────────────────────────────────────────
Write-Host "─── [3] DNS Resolution Test ──────────────────────────────────────" -ForegroundColor Yellow

$dnsHosts = @(
    "portal.azure.com",
    "management.azure.com",
    "login.microsoftonline.com",
    $TargetAddress
)

foreach ($host in $dnsHosts) {
    try {
        $result = Resolve-DnsName -Name $host -ErrorAction Stop | Select-Object -First 1
        Write-Host "  ✅ $host -> $($result.IPAddress)" -ForegroundColor Green
    } catch {
        Write-Host "  ❌ $host -> FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ─── 4. TCP Connectivity Test ─────────────────────────────────────────────
Write-Host "`n─── [4] TCP Connectivity Tests ───────────────────────────────────" -ForegroundColor Yellow

$endpoints = @(
    @{ Host = "portal.azure.com";           Port = 443 },
    @{ Host = "management.azure.com";       Port = 443 },
    @{ Host = "login.microsoftonline.com";  Port = 443 },
    @{ Host = $TargetAddress;               Port = $TargetPort }
)

foreach ($ep in $endpoints) {
    $result = Test-NetConnection -ComputerName $ep.Host -Port $ep.Port -WarningAction SilentlyContinue
    if ($result.TcpTestSucceeded) {
        Write-Host "  ✅ $($ep.Host):$($ep.Port) — REACHABLE (RTT: $($result.PingReplyDetails.RoundtripTime)ms)" -ForegroundColor Green
    } else {
        Write-Host "  ❌ $($ep.Host):$($ep.Port) — UNREACHABLE" -ForegroundColor Red
    }
}

# ─── 5. Network Watcher IP Flow Verify (if VM specified) ──────────────────
if ($VMName) {
    Write-Host "`n─── [5] Network Watcher — IP Flow Verify ─────────────────────────" -ForegroundColor Yellow

    $vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VMName -ErrorAction SilentlyContinue
    if ($vm) {
        $nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroup |
            Where-Object { $_.VirtualMachine.Id -eq $vm.Id } | Select-Object -First 1

        if ($nic) {
            $privateIP = $nic.IpConfigurations[0].PrivateIpAddress
            Write-Host "  VM: $VMName | Private IP: $privateIP" -ForegroundColor Cyan

            # Get or create Network Watcher
            $nw = Get-AzNetworkWatcher | Where-Object { $_.Location -eq $vm.Location } | Select-Object -First 1
            if ($nw) {
                try {
                    $flowTest = Test-AzNetworkWatcherIPFlow `
                        -NetworkWatcher $nw `
                        -TargetVirtualMachineId $vm.Id `
                        -Direction "Outbound" `
                        -Protocol "TCP" `
                        -RemoteIPAddress $TargetAddress `
                        -LocalIPAddress $privateIP `
                        -LocalPort "0" `
                        -RemotePort "$TargetPort" `
                        -ErrorAction Stop

                    $color = if ($flowTest.Access -eq "Allow") { "Green" } else { "Red" }
                    Write-Host "  IP Flow ($privateIP -> $TargetAddress`:$TargetPort): $($flowTest.Access) via $($flowTest.RuleName)" -ForegroundColor $color
                } catch {
                    Write-Host "  IP Flow test failed: $($_.Exception.Message)" -ForegroundColor Red
                }
            } else {
                Write-Host "  Network Watcher not found in region $($vm.Location)" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host "  VM '$VMName' not found in $ResourceGroup" -ForegroundColor Red
    }
}

Write-Host "`n✅ Network diagnostics complete." -ForegroundColor Green
