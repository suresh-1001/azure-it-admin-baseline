# Azure Security Baseline Checklist

Use this checklist when onboarding a new Azure subscription or performing a security review.

---

## Identity & Access Management

- [ ] **Break-glass accounts** — 2 emergency admin accounts created, MFA excluded via named location, alerts configured on sign-in
- [ ] **MFA enforced** — Conditional Access policy CA001 enabled for all users
- [ ] **Legacy authentication blocked** — CA002 policy enabled
- [ ] **No permanent Global Admins** — Use PIM (Privileged Identity Management) for JIT elevation
- [ ] **Service principals** — All app registrations reviewed; unused ones removed
- [ ] **Guest access restricted** — External collaboration settings reviewed in Entra ID
- [ ] **RBAC least privilege** — No broad "Owner" at subscription scope unless required

---

## Network Security

- [ ] **NSG on every subnet** — No subnet left without an associated NSG
- [ ] **Default deny inbound** — NSG baseline applied (see `nsg-baseline-rules.json`)
- [ ] **RDP/SSH not open to Internet** — Port 3389 and 22 restricted to Jump Host IP only
- [ ] **NSG Flow Logs enabled** — Stored in Storage Account, retention ≥ 90 days
- [ ] **DDoS Protection** — Standard plan enabled on hub VNet (or Basic acknowledged as accepted risk)
- [ ] **Azure Firewall or NVA** — Deployed in hub for centralized egress control (if required)
- [ ] **Private Endpoints** — Storage, SQL, Key Vault accessed via Private Endpoint where possible

---

## Data & Storage

- [ ] **Storage public access disabled** — `AllowBlobPublicAccess = false` on all storage accounts
- [ ] **HTTPS-only enforced** — `EnableHttpsTrafficOnly = true` on all storage accounts
- [ ] **Storage SAS tokens** — No permanent SAS tokens; time-bound and scoped to minimum permissions
- [ ] **Key Vault** — Secrets, keys, and certificates stored in Key Vault; not in code or config files
- [ ] **Key Vault soft delete + purge protection** — Enabled to prevent accidental deletion
- [ ] **Disk encryption** — Azure Disk Encryption enabled on all VMs

---

## Defender for Cloud

- [ ] **Defender plans enabled** — Minimum: Servers, Storage, SQL, App Service, Key Vault
- [ ] **Auto-provisioning on** — Log Analytics agent / AMA deployed to all VMs automatically
- [ ] **Secure Score ≥ 75%** — Review and remediate Critical/High recommendations
- [ ] **Security alerts → email notifications** — Configured for Security Admins
- [ ] **Vulnerability assessment** — Enabled on all VMs (Qualys or Defender built-in)

---

## Monitoring & Logging

- [ ] **Activity Log retention** — Minimum 90 days (365 days recommended)
- [ ] **Diagnostic settings** — All resources send logs to Log Analytics Workspace
- [ ] **Azure Monitor Alerts** — Alerts on: VM deletion, NSG change, RBAC change, Key Vault access
- [ ] **Log Analytics Workspace** — Single centralized workspace per environment
- [ ] **Microsoft Sentinel** — Connected to Log Analytics (if SIEM required)

---

## Governance

- [ ] **Azure Policy** — Built-in policies assigned: Allowed locations, Require tags, Audit unencrypted disks
- [ ] **Resource tagging** — All resources tagged: `Environment`, `Owner`, `CostCenter`, `Project`
- [ ] **Management Groups** — Subscriptions organized under Management Group hierarchy
- [ ] **Azure Blueprints / Landing Zone** — Baseline applied to new subscriptions

---

## Review Frequency

| Check | Frequency |
|---|---|
| Defender Secure Score | Weekly |
| RBAC assignments | Monthly |
| Active Directory guest accounts | Monthly |
| NSG rules | Quarterly |
| CA policies | Quarterly |
| Full security checklist | Annually or after major change |

---

*Part of the [Azure IT Admin Baseline](../README.md) project.*
