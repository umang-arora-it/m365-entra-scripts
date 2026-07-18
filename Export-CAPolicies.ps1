<#
.SYNOPSIS
    Audits and exports all Conditional Access policies in a Microsoft Entra ID tenant.

.DESCRIPTION
    Retrieves every Conditional Access policy (enabled, disabled, and report-only)
    and exports a flattened, human-readable CSV for security review, audits, or
    change management documentation.

.NOTES
    Required Role : Security Reader or Conditional Access Administrator
    Required Module: Microsoft.Graph
    Install       : Install-Module Microsoft.Graph -Scope CurrentUser

.EXAMPLE
    .\Export-CAPolicies.ps1
    Exports to CA_Policy_Audit_<date>.csv in the current directory.

.EXAMPLE
    .\Export-CAPolicies.ps1 -OutputPath "C:\Reports\CA_Audit.csv" -EnabledOnly
    Exports only enabled policies to a custom path.
#>

#Requires -Modules Microsoft.Graph.Identity.SignIns

[CmdletBinding()]
param (
    [string]$OutputPath = ".\CA_Policy_Audit_$(Get-Date -Format 'yyyyMMdd').csv",
    [switch]$EnabledOnly
)

Write-Host "`n[*] Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Policy.Read.All" -NoWelcome

Write-Host "[*] Retrieving Conditional Access policies..." -ForegroundColor Cyan
$policies = Get-MgIdentityConditionalAccessPolicy -All

if ($EnabledOnly) {
    $policies = $policies | Where-Object { $_.State -eq "enabled" }
}

Write-Host "[*] Found $($policies.Count) policies. Processing..." -ForegroundColor Cyan

$results = foreach ($policy in $policies) {

    # Resolve included/excluded users
    $inclUsers = if ($policy.Conditions.Users.IncludeUsers -contains "All") { "All Users" }
                 else { $policy.Conditions.Users.IncludeUsers -join '; ' }

    $exclUsers = $policy.Conditions.Users.ExcludeUsers -join '; '

    # Resolve included groups
    $inclGroups = $policy.Conditions.Users.IncludeGroups -join '; '
    $exclGroups = $policy.Conditions.Users.ExcludeGroups -join '; '

    # Resolve included roles
    $inclRoles  = $policy.Conditions.Users.IncludeRoles -join '; '

    # Apps
    $inclApps   = if ($policy.Conditions.Applications.IncludeApplications -contains "All") { "All Cloud Apps" }
                  else { $policy.Conditions.Applications.IncludeApplications -join '; ' }
    $exclApps   = $policy.Conditions.Applications.ExcludeApplications -join '; '

    # Platforms
    $inclPlatforms = $policy.Conditions.Platforms.IncludePlatforms -join '; '
    $exclPlatforms = $policy.Conditions.Platforms.ExcludePlatforms -join '; '

    # Locations
    $inclLocations = $policy.Conditions.Locations.IncludeLocations -join '; '
    $exclLocations = $policy.Conditions.Locations.ExcludeLocations -join '; '

    # Grant controls
    $grantOp       = $policy.GrantControls.Operator
    $grantControls = $policy.GrantControls.BuiltInControls -join '; '
    $sessionControls = @(
        if ($policy.SessionControls.SignInFrequency.IsEnabled)    { "SignInFrequency: $($policy.SessionControls.SignInFrequency.Value) $($policy.SessionControls.SignInFrequency.Type)" }
        if ($policy.SessionControls.PersistentBrowser.IsEnabled)  { "PersistentBrowser: $($policy.SessionControls.PersistentBrowser.Mode)" }
        if ($policy.SessionControls.CloudAppSecurity.IsEnabled)   { "CloudAppSecurity" }
        if ($policy.SessionControls.ContinuousAccessEvaluation)   { "CAE" }
    ) -join '; '

    [PSCustomObject]@{
        PolicyName          = $policy.DisplayName
        State               = $policy.State          # enabled / disabled / enabledForReportingButNotEnforced
        CreatedDateTime     = $policy.CreatedDateTime
        ModifiedDateTime    = $policy.ModifiedDateTime
        IncludedUsers       = $inclUsers
        ExcludedUsers       = $exclUsers
        IncludedGroups      = $inclGroups
        ExcludedGroups      = $exclGroups
        IncludedRoles       = $inclRoles
        IncludedApps        = $inclApps
        ExcludedApps        = $exclApps
        IncludedPlatforms   = $inclPlatforms
        ExcludedPlatforms   = $exclPlatforms
        IncludedLocations   = $inclLocations
        ExcludedLocations   = $exclLocations
        GrantOperator       = $grantOp
        GrantControls       = $grantControls
        SessionControls     = $sessionControls
        SignInRiskLevels    = $policy.Conditions.SignInRiskLevels -join '; '
        UserRiskLevels      = $policy.Conditions.UserRiskLevels -join '; '
        PolicyId            = $policy.Id
    }
}

$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

$enabled      = ($results | Where-Object { $_.State -eq "enabled" }).Count
$reportOnly   = ($results | Where-Object { $_.State -eq "enabledForReportingButNotEnforced" }).Count
$disabled     = ($results | Where-Object { $_.State -eq "disabled" }).Count

Write-Host "`n[✓] Export complete → $OutputPath" -ForegroundColor Green
Write-Host "    Enabled       : $enabled" -ForegroundColor Green
Write-Host "    Report-Only   : $reportOnly" -ForegroundColor Yellow
Write-Host "    Disabled      : $disabled" -ForegroundColor Red

Disconnect-MgGraph | Out-Null
