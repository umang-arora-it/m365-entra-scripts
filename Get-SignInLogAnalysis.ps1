<#
.SYNOPSIS
    Pulls and analyzes Microsoft Entra ID sign-in logs for failed logins,
    risky sign-ins, legacy auth attempts, and geographic anomalies.

.DESCRIPTION
    Retrieves sign-in logs from Microsoft Graph and produces a summarized
    security report. Flags legacy authentication (a common attack vector),
    failed logins, MFA challenges, and sign-ins from high-risk locations.
    Ideal for weekly security reviews and SOC reporting.

.PARAMETER Days
    Number of days of sign-in history to analyze. Default: 7. Max: 30.

.PARAMETER OutputPath
    CSV export path. Defaults to .\SignIn_Analysis_<date>.csv.

.PARAMETER TopFailedUsers
    How many top-failed-login users to highlight in the console summary. Default: 10.

.NOTES
    Required Role : Reports Reader or Security Reader
    Required Module: Microsoft.Graph
    Install       : Install-Module Microsoft.Graph -Scope CurrentUser
    Note          : Sign-in logs are only retained for 30 days on free Entra / 90 days on P1/P2.

.EXAMPLE
    .\Get-SignInLogAnalysis.ps1 -Days 7
    Analyzes the last 7 days of sign-in activity.
#>

#Requires -Modules Microsoft.Graph.Reports, Microsoft.Graph.Identity.SignIns

[CmdletBinding()]
param (
    [ValidateRange(1,30)]
    [int]$Days            = 7,
    [string]$OutputPath   = ".\SignIn_Analysis_$(Get-Date -Format 'yyyyMMdd').csv",
    [int]$TopFailedUsers  = 10
)

$startDate = (Get-Date).AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "`n[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "AuditLog.Read.All", "Directory.Read.All" -NoWelcome

Write-Host "[*] Fetching sign-in logs for last $Days days (from $startDate)..." -ForegroundColor Cyan

$signIns = Get-MgAuditLogSignIn -All -Filter "createdDateTime ge $startDate" `
    -Property createdDateTime, userDisplayName, userPrincipalName, appDisplayName, `
              ipAddress, location, status, authenticationRequirement, `
              clientAppUsed, conditionalAccessStatus, riskLevelDuringSignIn, `
              riskLevelAggregated, isInteractive, resourceDisplayName

Write-Host "[*] Retrieved $($signIns.Count) sign-in events. Analyzing..." -ForegroundColor Cyan

# Legacy auth client apps (commonly targeted by password spray / brute force)
$legacyClients = @(
    "Exchange ActiveSync","IMAP4","POP3","SMTP","Autodiscover",
    "Exchange Online PowerShell","Other clients","Authenticated SMTP",
    "Exchange Web Services","Mapi","Offline Address Book"
)

$results = foreach ($s in $signIns) {
    $failed       = $s.Status.ErrorCode -ne 0
    $isLegacyAuth = $s.ClientAppUsed -in $legacyClients
    $isRisky      = $s.RiskLevelDuringSignIn -in @("medium","high","hidden","unknownFutureValue")

    [PSCustomObject]@{
        Timestamp           = $s.CreatedDateTime
        UserDisplayName     = $s.UserDisplayName
        UPN                 = $s.UserPrincipalName
        AppName             = $s.AppDisplayName
        ResourceName        = $s.ResourceDisplayName
        ClientApp           = $s.ClientAppUsed
        IsLegacyAuth        = $isLegacyAuth
        IsInteractive       = $s.IsInteractive
        IPAddress           = $s.IpAddress
        Country             = $s.Location.CountryOrRegion
        City                = $s.Location.City
        Status              = if ($failed) { "Failed" } else { "Success" }
        ErrorCode           = $s.Status.ErrorCode
        FailureReason       = $s.Status.FailureReason
        MFARequired         = $s.AuthenticationRequirement
        CAStatus            = $s.ConditionalAccessStatus
        RiskLevelSignIn     = $s.RiskLevelDuringSignIn
        RiskLevelAggregated = $s.RiskLevelAggregated
        Flags               = (@(
            if ($failed)        { "FAILED" }
            if ($isLegacyAuth)  { "LEGACY-AUTH" }
            if ($isRisky)       { "RISKY" }
        ) -join ', ')
    }
}

$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

# ── Console Summary ──
$failed     = $results | Where-Object { $_.Status -eq "Failed" }
$legacy     = $results | Where-Object { $_.IsLegacyAuth -eq $true }
$risky      = $results | Where-Object { $_.RiskLevelSignIn -in @("medium","high") }
$countries  = $results | Group-Object Country | Sort-Object Count -Descending | Select-Object -First 5

Write-Host "`n════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SIGN-IN ANALYSIS SUMMARY ($Days days)" -ForegroundColor Cyan
Write-Host "════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Total events    : $($results.Count)"
Write-Host "  Failed logins   : $($failed.Count)" -ForegroundColor $(if ($failed.Count -gt 0) { "Red" } else { "Green" })
Write-Host "  Legacy auth     : $($legacy.Count)" -ForegroundColor $(if ($legacy.Count -gt 0) { "Yellow" } else { "Green" })
Write-Host "  Risky sign-ins  : $($risky.Count)" -ForegroundColor $(if ($risky.Count -gt 0) { "Red" } else { "Green" })

Write-Host "`n  Top $TopFailedUsers users with failed logins:" -ForegroundColor Yellow
$failed | Group-Object UPN | Sort-Object Count -Descending | Select-Object -First $TopFailedUsers |
    ForEach-Object { Write-Host "    $($_.Count)x  $($_.Name)" -ForegroundColor DarkYellow }

Write-Host "`n  Sign-ins by country (top 5):" -ForegroundColor Cyan
$countries | ForEach-Object { Write-Host "    $($_.Count)x  $($_.Name)" }

Write-Host "`n[✓] Full report → $OutputPath" -ForegroundColor Green

Disconnect-MgGraph | Out-Null
