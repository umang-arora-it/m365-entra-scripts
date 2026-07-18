# M365 & Microsoft Entra ID — PowerShell Automation Scripts

A collection of production-ready PowerShell scripts for **Microsoft 365 administration**, **Entra ID (Azure AD) identity management**, and **security operations**. Built and maintained by [Umang Arora](https://linkedin.com/in/umang-arora-it) — Microsoft 365 Identity & Security Engineer.

---

## 📁 Scripts

| Script | Description | Module Required |
|--------|-------------|-----------------|
| [`Get-MFAStatus.ps1`](./Get-MFAStatus.ps1) | Export MFA registration status for all users — flags accounts with no MFA | Microsoft.Graph |
| [`Export-CAPolicies.ps1`](./Export-CAPolicies.ps1) | Audit and export all Conditional Access policies (enabled, report-only, disabled) | Microsoft.Graph |
| [`Get-StaleGuests.ps1`](./Get-StaleGuests.ps1) | Identify guest/B2B accounts inactive for 90+ days — supports auto-disable | Microsoft.Graph |
| [`Set-BulkLicenseAssignment.ps1`](./Set-BulkLicenseAssignment.ps1) | Bulk assign, remove, or swap M365 licenses from a CSV via Microsoft Graph API | Microsoft.Graph |
| [`Get-MailboxPermissions.ps1`](./Get-MailboxPermissions.ps1) | Export Full Access, Send As, and Send on Behalf permissions across all mailboxes | ExchangeOnlineManagement |
| [`Get-SignInLogAnalysis.ps1`](./Get-SignInLogAnalysis.ps1) | Analyze Entra ID sign-in logs — flags failed logins, legacy auth, and risky sign-ins | Microsoft.Graph |

---

## ⚙️ Prerequisites

### PowerShell Version
- PowerShell 7.x (recommended) or Windows PowerShell 5.1

### Required Modules
```powershell
# Microsoft Graph (covers most scripts)
Install-Module Microsoft.Graph -Scope CurrentUser

# Exchange Online (for mailbox scripts)
Install-Module ExchangeOnlineManagement -Scope CurrentUser
```

### Required Entra ID Roles (minimum)
| Script | Minimum Role |
|--------|-------------|
| Get-MFAStatus | Reports Reader |
| Export-CAPolicies | Security Reader |
| Get-StaleGuests | Reports Reader |
| Set-BulkLicenseAssignment | License Administrator |
| Get-MailboxPermissions | Exchange Administrator |
| Get-SignInLogAnalysis | Reports Reader |

---

## 🚀 Quick Start

```powershell
# 1. Clone the repo
git clone https://github.com/umang-arora-it/m365-entra-scripts.git
cd m365-entra-scripts

# 2. Install required modules
Install-Module Microsoft.Graph -Scope CurrentUser
Install-Module ExchangeOnlineManagement -Scope CurrentUser

# 3. Run a script
.\Get-MFAStatus.ps1

# 4. Find your license SKU IDs (for bulk license script)
Connect-MgGraph -Scopes "Organization.Read.All"
Get-MgSubscribedSku | Select-Object SkuPartNumber, SkuId, ConsumedUnits
```

---

## 📋 Script Details

### `Get-MFAStatus.ps1`
Exports MFA registration status for all users. Flags any enabled accounts with no MFA registered — a critical security hygiene check.

```powershell
# Basic export
.\Get-MFAStatus.ps1

# Exclude disabled accounts
.\Get-MFAStatus.ps1 -ExcludeDisabledAccounts

# Custom output path
.\Get-MFAStatus.ps1 -OutputPath "C:\Reports\MFA.csv"
```

---

### `Export-CAPolicies.ps1`
Flattens all Conditional Access policies into a single CSV — useful for audits, change management, and Zero Trust reviews.

```powershell
# Export all policies
.\Export-CAPolicies.ps1

# Export only enabled policies
.\Export-CAPolicies.ps1 -EnabledOnly
```

---

### `Get-StaleGuests.ps1`
Identifies guest (B2B) accounts that haven't signed in recently. Supports optional auto-disable with `-DisableStaleGuests`.

```powershell
# Report guests inactive for 90 days (default)
.\Get-StaleGuests.ps1

# Report inactive for 60 days
.\Get-StaleGuests.ps1 -InactiveDays 60

# Report AND disable stale accounts (use -WhatIf first!)
.\Get-StaleGuests.ps1 -DisableStaleGuests -WhatIf
.\Get-StaleGuests.ps1 -DisableStaleGuests
```

---

### `Set-BulkLicenseAssignment.ps1`
Assigns or removes M365 licenses in bulk from a CSV. Supports Add, Remove, and Swap (license migration) actions.

```powershell
# Prepare your CSV (UserPrincipalName column required)
# user1@domain.com
# user2@domain.com

# Assign M365 E3 to all users in CSV
.\Set-BulkLicenseAssignment.ps1 -CsvPath ".\users.csv" -LicenseSkuId "05e9a617-0261-4cee-bb44-138d3ef5d965"

# Remove a license
.\Set-BulkLicenseAssignment.ps1 -CsvPath ".\users.csv" -LicenseSkuId "<SkuId>" -Action Remove

# Swap E1 → E3
.\Set-BulkLicenseAssignment.ps1 -CsvPath ".\users.csv" -LicenseSkuId "<E3-SkuId>" -RemoveSkuId "<E1-SkuId>" -Action Swap
```

---

### `Get-MailboxPermissions.ps1`
Audits all mailbox delegate permissions across the tenant. Useful for offboarding reviews and least-privilege audits.

```powershell
# All mailboxes
.\Get-MailboxPermissions.ps1

# Shared mailboxes only
.\Get-MailboxPermissions.ps1 -MailboxFilter SharedMailbox
```

---

### `Get-SignInLogAnalysis.ps1`
Analyzes Entra ID sign-in logs and surfaces security signals — failed logins, legacy authentication, and risky sign-ins.

```powershell
# Last 7 days (default)
.\Get-SignInLogAnalysis.ps1

# Last 30 days
.\Get-SignInLogAnalysis.ps1 -Days 30
```

---

## 🔑 Common SKU IDs (Microsoft 365)

| License | SKU ID |
|---------|--------|
| Microsoft 365 E3 | `05e9a617-0261-4cee-bb44-138d3ef5d965` |
| Microsoft 365 E5 | `06ebc4ee-1bb5-47dd-8120-11324bc54e06` |
| Microsoft 365 Business Premium | `cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46` |
| Microsoft 365 F3 | `66b55226-6b4f-492c-910c-a3b7a3c9d993` |
| Exchange Online Plan 1 | `19ec0d23-8335-4cbd-94ac-6050e30712fa` |
| Exchange Online Plan 2 | `efccb6f7-5641-4e0e-bd10-b4976e1bf68e` |
| Entra ID P2 | `84a661c4-e949-4bd2-a560-ed7766fcaf2b` |

> **Tip:** Always verify SKU IDs in your tenant using `Get-MgSubscribedSku` — they can differ by region or agreement type.

---

## 📌 Notes

- Always test scripts with `-WhatIf` before running in production
- Scripts connect interactively via `Connect-MgGraph` — no credentials are stored
- Outputs are CSV files in the current directory unless `-OutputPath` is specified
- Sign-in log retention: 30 days (free Entra ID) / 90 days (Entra ID P1/P2)

---

## 🔗 Connect

- **LinkedIn:** [linkedin.com/in/umang-arora-it](https://linkedin.com/in/umang-arora-it)
- **Email:** Umangji73@gmail.com
