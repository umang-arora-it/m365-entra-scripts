<#
.SYNOPSIS
    Exports MFA registration status for all users in an Entra ID tenant.
.DESCRIPTION
    Connects to Microsoft Graph and retrieves MFA method registration
    details for all users. Exports results to a CSV file.
.NOTES
    Required role: Reports Reader or Security Reader
    Module: Microsoft.Graph
#>

Connect-MgGraph -Scopes "UserAuthenticationMethod.Read.All", "User.Read.All"

$users = Get-MgUser -All -Property Id, DisplayName, UserPrincipalName, AccountEnabled

$results = foreach ($user in $users) {
    $methods = Get-MgUserAuthenticationMethod -UserId $user.Id
    $hasMFA = $methods.Count -gt 1  # Password alone = 1 method

    [PSCustomObject]@{
        DisplayName       = $user.DisplayName
        UPN               = $user.UserPrincipalName
        AccountEnabled    = $user.AccountEnabled
        MFARegistered     = $hasMFA
        MethodCount       = $methods.Count
    }
}

$results | Export-Csv -Path "MFA_Status_Report.csv" -NoTypeInformation
Write-Host "Export complete. Total users: $($results.Count)"
