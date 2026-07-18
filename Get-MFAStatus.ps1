<#
.SYNOPSIS
    Exports MFA registration status for all users in a Microsoft Entra ID tenant.

.DESCRIPTION
    Connects to Microsoft Graph and retrieves authentication method registration
    details for every user. Outputs a CSV report showing who has MFA registered,
    what methods they use, and flags accounts with no MFA (password only).

.NOTES
    Required Role : Reports Reader or Security Reader (minimum)
    Required Module: Microsoft.Graph
    Install       : Install-Module Microsoft.Graph -Scope CurrentUser

.EXAMPLE
    .\Get-MFAStatus.ps1
    Exports to MFA_Status_Report_<date>.csv in the current directory.
#>

#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Identity.SignIns

[CmdletBinding()]
param (
    [string]$OutputPath = ".\MFA_Status_Report_$(Get-Date -Format 'yyyyMMdd').csv",
    [switch]$ExcludeDisabledAccounts
)

Write-Host "`n[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "UserAuthenticationMethod.Read.All", "User.Read.All" -NoWelcome

Write-Host "[*] Fetching all users..." -ForegroundColor Cyan
$users = Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, AccountEnabled, Department, JobTitle |
    Where-Object { -not $ExcludeDisabledAccounts -or $_.AccountEnabled -eq $true }

Write-Host "[*] Found $($users.Count) users. Retrieving MFA status..." -ForegroundColor Cyan

$results = foreach ($user in $users) {
    try {
        $methods = Get-MgUserAuthenticationMethod -UserId $user.Id -ErrorAction Stop

        # Method types (password alone means no MFA)
        $methodTypes = $methods.AdditionalProperties.'@odata.type' -replace '#microsoft.graph.', ''
        $hasMFA      = ($methods | Where-Object { $_.AdditionalProperties.'@odata.type' -ne '#microsoft.graph.passwordAuthenticationMethod' }).Count -gt 0

        [PSCustomObject]@{
            DisplayName    = $user.DisplayName
            UPN            = $user.UserPrincipalName
            Department     = $user.Department
            JobTitle       = $user.JobTitle
            AccountEnabled = $user.AccountEnabled
            MFARegistered  = $hasMFA
            MethodCount    = $methods.Count
            Methods        = ($methodTypes -join '; ')
            RiskFlag       = if (-not $hasMFA -and $user.AccountEnabled) { "⚠ NO MFA" } else { "" }
        }
    }
    catch {
        Write-Warning "Could not retrieve methods for $($user.UserPrincipalName): $_"
    }
}

$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

$noMFA = ($results | Where-Object { $_.RiskFlag -ne "" }).Count
Write-Host "`n[✓] Export complete → $OutputPath" -ForegroundColor Green
Write-Host "[!] Users with NO MFA: $noMFA / $($results.Count)" -ForegroundColor $(if ($noMFA -gt 0) { "Yellow" } else { "Green" })

Disconnect-MgGraph | Out-Null
