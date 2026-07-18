<#
.SYNOPSIS
    Exports all mailbox delegate permissions (Full Access, Send As, Send on Behalf) 
    across an Exchange Online tenant.

.DESCRIPTION
    Connects to Exchange Online and retrieves Full Access, Send As, and Send on Behalf
    permissions for all (or specified) mailboxes. Useful for security audits, offboarding
    reviews, and compliance reporting.

.PARAMETER MailboxFilter
    Filter mailboxes by type. Options: All, UserMailbox, SharedMailbox, RoomMailbox.
    Default: All.

.PARAMETER OutputPath
    Export path for the CSV. Defaults to .\Mailbox_Permissions_<date>.csv.

.PARAMETER ExcludeSelf
    Exclude self-permissions and system/NT AUTHORITY entries. Default: $true.

.NOTES
    Required Role : Exchange Administrator or View-Only Organization Management
    Required Module: ExchangeOnlineManagement
    Install       : Install-Module ExchangeOnlineManagement -Scope CurrentUser

.EXAMPLE
    .\Get-MailboxPermissions.ps1
    Exports permissions for all mailboxes.

.EXAMPLE
    .\Get-MailboxPermissions.ps1 -MailboxFilter SharedMailbox
    Exports permissions for shared mailboxes only — common for offboarding audits.
#>

#Requires -Modules ExchangeOnlineManagement

[CmdletBinding()]
param (
    [ValidateSet("All","UserMailbox","SharedMailbox","RoomMailbox","EquipmentMailbox")]
    [string]$MailboxFilter = "All",
    [string]$OutputPath    = ".\Mailbox_Permissions_$(Get-Date -Format 'yyyyMMdd').csv",
    [bool]$ExcludeSelf     = $true
)

Write-Host "`n[*] Connecting to Exchange Online..." -ForegroundColor Cyan
Connect-ExchangeOnline -ShowBanner:$false

Write-Host "[*] Fetching mailboxes (filter: $MailboxFilter)..." -ForegroundColor Cyan

$mailboxes = if ($MailboxFilter -eq "All") {
    Get-EXOMailbox -ResultSize Unlimited -Properties DisplayName, UserPrincipalName, RecipientTypeDetails
} else {
    Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails $MailboxFilter -Properties DisplayName, UserPrincipalName, RecipientTypeDetails
}

Write-Host "[*] Found $($mailboxes.Count) mailboxes. Retrieving permissions..." -ForegroundColor Cyan

$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$i       = 0

foreach ($mbx in $mailboxes) {
    $i++
    Write-Progress -Activity "Auditing mailbox permissions" -Status "$i / $($mailboxes.Count): $($mbx.UserPrincipalName)" -PercentComplete (($i / $mailboxes.Count) * 100)

    # ── Full Access ──
    $fullAccess = Get-EXOMailboxPermission -Identity $mbx.UserPrincipalName -ErrorAction SilentlyContinue |
        Where-Object {
            $_.AccessRights -like "*FullAccess*" -and
            (-not $ExcludeSelf -or ($_.User -ne $mbx.UserPrincipalName -and $_.User -notlike "NT AUTHORITY*"))
        }

    foreach ($perm in $fullAccess) {
        $results.Add([PSCustomObject]@{
            MailboxName    = $mbx.DisplayName
            MailboxUPN     = $mbx.UserPrincipalName
            MailboxType    = $mbx.RecipientTypeDetails
            PermissionType = "Full Access"
            DelegateUser   = $perm.User
            AccessRights   = $perm.AccessRights -join '; '
            IsInherited    = $perm.IsInherited
        })
    }

    # ── Send As ──
    $sendAs = Get-EXORecipientPermission -Identity $mbx.UserPrincipalName -ErrorAction SilentlyContinue |
        Where-Object {
            $_.AccessRights -like "*SendAs*" -and
            (-not $ExcludeSelf -or ($_.Trustee -ne $mbx.UserPrincipalName -and $_.Trustee -notlike "NT AUTHORITY*"))
        }

    foreach ($perm in $sendAs) {
        $results.Add([PSCustomObject]@{
            MailboxName    = $mbx.DisplayName
            MailboxUPN     = $mbx.UserPrincipalName
            MailboxType    = $mbx.RecipientTypeDetails
            PermissionType = "Send As"
            DelegateUser   = $perm.Trustee
            AccessRights   = $perm.AccessRights -join '; '
            IsInherited    = $perm.IsInherited
        })
    }

    # ── Send on Behalf ──
    $sendOnBehalf = (Get-EXOMailbox -Identity $mbx.UserPrincipalName -Properties GrantSendOnBehalfTo -ErrorAction SilentlyContinue).GrantSendOnBehalfTo

    foreach ($delegate in $sendOnBehalf) {
        $results.Add([PSCustomObject]@{
            MailboxName    = $mbx.DisplayName
            MailboxUPN     = $mbx.UserPrincipalName
            MailboxType    = $mbx.RecipientTypeDetails
            PermissionType = "Send on Behalf"
            DelegateUser   = $delegate
            AccessRights   = "SendOnBehalf"
            IsInherited    = $false
        })
    }
}

Write-Progress -Completed -Activity "Auditing mailbox permissions"

$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host "`n[✓] Export complete → $OutputPath" -ForegroundColor Green
Write-Host "    Total permission entries : $($results.Count)"
Write-Host "    Full Access              : $(($results | Where-Object {$_.PermissionType -eq 'Full Access'}).Count)"
Write-Host "    Send As                  : $(($results | Where-Object {$_.PermissionType -eq 'Send As'}).Count)"
Write-Host "    Send on Behalf           : $(($results | Where-Object {$_.PermissionType -eq 'Send on Behalf'}).Count)"

Disconnect-ExchangeOnline -Confirm:$false | Out-Null
