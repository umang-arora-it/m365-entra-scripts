<#
.SYNOPSIS
    Reports guest (B2B) accounts that have been inactive for a specified number of days.

.DESCRIPTION
    Queries Microsoft Entra ID for all external/guest accounts and checks their last
    sign-in activity. Flags accounts with no sign-in within the threshold period.
    Useful for periodic guest access reviews and Zero Trust hygiene.

.PARAMETER InactiveDays
    Number of days of inactivity to flag a guest account as stale. Default: 90.

.PARAMETER OutputPath
    Path for the CSV export. Defaults to .\Stale_Guests_<date>.csv

.PARAMETER DisableStaleGuests
    If specified, will DISABLE (not delete) stale guest accounts after exporting.
    Use with caution — always review the CSV export first.

.NOTES
    Required Role : Reports Reader + User Administrator (if using -DisableStaleGuests)
    Required Module: Microsoft.Graph
    Install       : Install-Module Microsoft.Graph -Scope CurrentUser

.EXAMPLE
    .\Get-StaleGuests.ps1
    Reports guests inactive for 90+ days.

.EXAMPLE
    .\Get-StaleGuests.ps1 -InactiveDays 60 -OutputPath "C:\Reports\Guests.csv"
    Reports guests inactive for 60+ days, exports to custom path.
#>

#Requires -Modules Microsoft.Graph.Users, Microsoft.Graph.Reports

[CmdletBinding(SupportsShouldProcess)]
param (
    [int]$InactiveDays  = 90,
    [string]$OutputPath = ".\Stale_Guests_$(Get-Date -Format 'yyyyMMdd').csv",
    [switch]$DisableStaleGuests
)

$cutoffDate = (Get-Date).AddDays(-$InactiveDays)

Write-Host "`n[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan
$scopes = @("User.Read.All", "AuditLog.Read.All")
if ($DisableStaleGuests) { $scopes += "User.ReadWrite.All" }
Connect-MgGraph -Scopes $scopes -NoWelcome

Write-Host "[*] Fetching all guest accounts..." -ForegroundColor Cyan
$guests = Get-MgUser -All -Filter "userType eq 'Guest'" `
    -Property Id, DisplayName, UserPrincipalName, Mail, AccountEnabled, `
              CreatedDateTime, SignInActivity, Department, CompanyName

Write-Host "[*] Found $($guests.Count) guest accounts. Analyzing activity..." -ForegroundColor Cyan

$results = foreach ($guest in $guests) {
    $lastSignIn = $guest.SignInActivity.LastSignInDateTime
    $lastNonInteractive = $guest.SignInActivity.LastNonInteractiveSignInDateTime

    # Use most recent of the two sign-in types
    $mostRecent = @($lastSignIn, $lastNonInteractive) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1

    $daysSinceSignIn = if ($mostRecent) {
        [math]::Round(((Get-Date) - $mostRecent).TotalDays)
    } else {
        999  # Never signed in
    }

    $isStale = $mostRecent -lt $cutoffDate -or $null -eq $mostRecent

    [PSCustomObject]@{
        DisplayName             = $guest.DisplayName
        UPN                     = $guest.UserPrincipalName
        ExternalEmail           = $guest.Mail
        CompanyName             = $guest.CompanyName
        Department              = $guest.Department
        AccountEnabled          = $guest.AccountEnabled
        CreatedDate             = $guest.CreatedDateTime
        LastInteractiveSignIn   = $lastSignIn
        LastNonInteractiveSignIn= $lastNonInteractive
        DaysSinceLastSignIn     = $daysSinceSignIn
        IsStale                 = $isStale
        StaleFlag               = if ($isStale) { "⚠ STALE ($daysSinceSignIn days)" } else { "" }
        UserId                  = $guest.Id
    }
}

# Export full report
$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

$staleAccounts = $results | Where-Object { $_.IsStale -eq $true }
$neverSignedIn = $results | Where-Object { $_.DaysSinceLastSignIn -eq 999 }

Write-Host "`n[✓] Export complete → $OutputPath" -ForegroundColor Green
Write-Host "    Total guests    : $($results.Count)"
Write-Host "    Stale (>$InactiveDays days): $($staleAccounts.Count)" -ForegroundColor Yellow
Write-Host "    Never signed in : $($neverSignedIn.Count)" -ForegroundColor Red

# Optionally disable stale accounts
if ($DisableStaleGuests -and $staleAccounts.Count -gt 0) {
    Write-Host "`n[!] -DisableStaleGuests specified. Disabling $($staleAccounts.Count) stale guests..." -ForegroundColor Yellow
    foreach ($acct in $staleAccounts) {
        if ($PSCmdlet.ShouldProcess($acct.UPN, "Disable guest account")) {
            Update-MgUser -UserId $acct.UserId -AccountEnabled:$false
            Write-Host "    Disabled: $($acct.UPN)" -ForegroundColor DarkYellow
        }
    }
    Write-Host "[✓] Done. Review $OutputPath and validate changes in Entra ID." -ForegroundColor Green
}

Disconnect-MgGraph | Out-Null
