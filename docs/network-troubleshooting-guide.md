# Azure Network Troubleshooting Guide

A practical reference for diagnosing and resolving common Azure networking issues.

---

## Quick Diagnostic Decision Tree

```
VM can't connect?
│
├── Can it ping another VM in the same VNet?
│   ├── YES → Issue is external (NSG, routing, DNS)
│   └── NO  → Issue is internal (VM config, OS firewall, NIC)
│
├── Can it reach Azure services (storage, SQL)?
│   ├── YES → Internet-only block (check NSG outbound, UDR)
│   └── NO  → Check Service Endpoints or Private Endpoints
│
└── DNS resolving correctly?
    ├── YES → TCP-level block (NSG, firewall appliance)
    └── NO  → DNS config issue (custom DNS server, private zones)
```

---

## Common Issues & Resolutions

### 1. VM Cannot Reach Internet

**Symptoms:** Outbound HTTP/HTTPS fails, Windows Update fails, package manager errors.

**Diagnosis Steps:**
```powershell
# Test outbound connectivity
Test-NetConnection -ComputerName "8.8.8.8" -Port 443

# Check if a UDR (Route Table) is redirecting traffic
Get-AzRouteTable -ResourceGroupName "<rg>" | Get-AzRouteConfig

# Check NSG outbound rules
Get-AzNetworkSecurityGroup -Name "<nsg-name>" -ResourceGroupName "<rg>" |
    Select-Object -ExpandProperty SecurityRules |
    Where-Object { $_.Direction -eq "Outbound" } |
    Format-Table Name, Priority, Access, DestinationAddressPrefix, DestinationPortRange
```

**Common Causes:**
- NSG outbound deny rule blocking port 443
- User Defined Route (UDR) sending traffic to a firewall/NVA that is down
- Azure Firewall policy blocking outbound traffic

---

### 2. VNet Peering Not Working

**Symptoms:** VMs in peered VNets cannot communicate.

**Diagnosis Steps:**
```powershell
# Check peering status (must be "Connected" on BOTH sides)
Get-AzVirtualNetworkPeering -ResourceGroupName "<rg>" -VirtualNetworkName "<vnet>"

# Verify "Allow forwarded traffic" and "Allow gateway transit" settings
$peering = Get-AzVirtualNetworkPeering -ResourceGroupName "<rg>" `
    -VirtualNetworkName "<vnet>" -Name "<peering-name>"
$peering | Select-Object AllowVirtualNetworkAccess, AllowForwardedTraffic, AllowGatewayTransit, UseRemoteGateways
```

**Checklist:**
- [ ] Peering state = "Connected" on both VNets
- [ ] "Allow virtual network access" = Enabled
- [ ] Address spaces do not overlap
- [ ] NSG rules allow traffic between the two VNet CIDRs

---

### 3. DNS Resolution Failure

**Symptoms:** Name resolution fails; nslookup returns NXDOMAIN or times out.

**Diagnosis Steps:**
```powershell
# Test DNS from the VM
Resolve-DnsName -Name "myapp.internal.contoso.com" -Server "168.63.129.16"  # Azure DNS
Resolve-DnsName -Name "myapp.internal.contoso.com" -Server "<custom-dns-ip>"

# Check VNet DNS server setting
(Get-AzVirtualNetwork -Name "<vnet>" -ResourceGroupName "<rg>").DhcpOptions.DnsServers
```

**Common Causes:**
- VNet pointing to a custom DNS server that is down or misconfigured
- Azure Private DNS Zone not linked to the VNet
- Forwarder not configured on custom DNS for Azure internal domains

**Fix — Link Private DNS Zone:**
```powershell
New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName "<rg>" `
    -ZoneName "privatelink.blob.core.windows.net" `
    -Name "vnet-link-blob" `
    -VirtualNetworkId (Get-AzVirtualNetwork -Name "<vnet>" -ResourceGroupName "<rg>").Id `
    -EnableRegistration $false
```

---

### 4. Cannot Access Azure SQL / Storage via Private Endpoint

**Symptoms:** Private endpoint deployed but connection still fails or resolves to public IP.

**Diagnosis Steps:**
```powershell
# Verify private endpoint DNS resolution
Resolve-DnsName "mystorageaccount.blob.core.windows.net"
# Should return a 10.x.x.x private IP — if it returns 52.x.x.x it's going public

# Check private endpoint connection state
Get-AzPrivateEndpointConnection -PrivateLinkResourceId "<resource-id>"
# State must be "Approved"
```

**Checklist:**
- [ ] Private DNS Zone exists for the service (e.g. `privatelink.blob.core.windows.net`)
- [ ] DNS Zone is linked to the VNet
- [ ] Private endpoint NIC has an IP in the VNet subnet
- [ ] NSG on private endpoint subnet doesn't block the traffic
- [ ] Resource firewall allows VNet or "Selected Networks" with the correct subnet

---

### 5. High Latency Between Regions

**Diagnosis:**
1. **Azure Network Watcher → Connection Monitor** — Set up continuous latency monitoring between source VM and target endpoint.
2. Check if traffic is hairpinning through a hub VNet (add direct peering if needed).
3. Use **Azure Front Door** or **Traffic Manager** for latency-based routing across regions.

```powershell
# One-off latency check
Test-NetConnection -ComputerName "<remote-vm-ip>" -Port 443 -InformationLevel Detailed
```

---

## Useful Azure Networking Commands Reference

```powershell
# List all VNets and their address spaces
Get-AzVirtualNetwork | Select-Object Name, ResourceGroupName, Location, `
    @{N="AddressSpace"; E={$_.AddressSpace.AddressPrefixes -join ", "}}

# List all NSGs and associated subnets
Get-AzNetworkSecurityGroup | Select-Object Name, ResourceGroupName, `
    @{N="Subnets"; E={$_.Subnets.Id -join ", "}}

# Enable NSG flow logs (requires Storage Account + Network Watcher)
Set-AzNetworkWatcherFlowLog -NetworkWatcherName "<nw-name>" `
    -ResourceGroupName "<rg>" `
    -TargetResourceId "<nsg-resource-id>" `
    -StorageId "<storage-account-id>" `
    -EnableFlowLog $true `
    -EnableTrafficAnalytics $true `
    -Workspace "<log-analytics-workspace-id>"

# Trace effective routes on a NIC
Get-AzEffectiveRouteTable -NetworkInterfaceName "<nic-name>" -ResourceGroupName "<rg>" |
    Format-Table AddressPrefix, NextHopType, NextHopIpAddress, State

# Trace effective NSG rules on a NIC
Get-AzEffectiveNetworkSecurityGroup -NetworkInterfaceName "<nic-name>" -ResourceGroupName "<rg>"
```

---

*Part of the [Azure IT Admin Baseline](../README.md) project.*
