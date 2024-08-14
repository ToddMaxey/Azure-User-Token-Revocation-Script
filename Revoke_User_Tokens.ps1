# Function to check if the script is running with elevated privileges
function Test-IsAdmin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Function to check and install required modules
function Ensure-Module {
    param (
        [string]$ModuleName
    )
    
    if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
        Write-Host "Module $ModuleName is not installed. Installing..." -ForegroundColor Yellow
        Install-Module -Name $ModuleName -Force -AllowClobber
    } else {
        Write-Host "Module $ModuleName is already installed." -ForegroundColor Green
    }
}

# Set the debug preference to 'Continue' so that debug messages are shown automatically without user interaction
$DebugPreference = 'Continue'

# Check if the session is running with elevated privileges
if (-not (Test-IsAdmin)) {
    Write-Host "This script needs to be run as an administrator. Please rerun this script in an elevated PowerShell session." -ForegroundColor Red
    Write-Host "Closing Session" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit
}

# Set Execution Policy to RemoteSigned
Set-ExecutionPolicy RemoteSigned -Scope Process -Force

# Ensure required modules are installed
Ensure-Module -ModuleName "Microsoft.Graph.Authentication"
Ensure-Module -ModuleName "Microsoft.Graph.Users.Actions"
Ensure-Module -ModuleName "Microsoft.Graph.Reports"

# Connect to Microsoft Graph with the necessary scope
Connect-MgGraph -Scopes "User.RevokeSessions.All, AuditLog.Read.All, Directory.Read.All"

# Loop to revoke sessions for multiple users
do {
    # Prompt for User Principal Name (UPN) or ObjectID
    $userInput = Read-Host "Please enter the User Principal Name (UPN) or ObjectID of the user"

    # Query the user's last sign-in status before revocation
    Write-Host "Querying the user's sign-in activity before revocation..."
    $signInActivitiesBefore = Get-MgAuditLogSignIn -Filter "userPrincipalName eq '$userInput' or userId eq '$userInput'" -Top 1 | Select-Object CreatedDateTime, Status, TokenIssuerType, ResourceDisplayName, ApplicationDisplayName, IPAddress

    Write-Host "User's last sign-in activity before revocation:"
    $signInActivitiesBefore | Format-Table -AutoSize

    # Revoke the user's sign-in sessions with verbose and debug logging
    Write-Host "Revoking the user's sign-in sessions..."
    Revoke-MgUserSignInSession -UserId $userInput -Verbose -Debug

    # Pause for a few seconds to allow the revocation to propagate
    Start-Sleep -Seconds 15

    # Query the user's last sign-in status after revocation
    Write-Host "Querying the user's sign-in activity after revocation..."
    $signInActivitiesAfter = Get-MgAuditLogSignIn -Filter "userPrincipalName eq '$userInput' or userId eq '$userInput'" -Top 1 | Select-Object CreatedDateTime, Status, TokenIssuerType, ResourceDisplayName, ApplicationDisplayName, IPAddress

    Write-Host "User's last sign-in activity after revocation:"
    $signInActivitiesAfter | Format-Table -AutoSize

    # Compare before and after states to determine if the revocation was successful
    if ($signInActivitiesBefore.CreatedDateTime -eq $signInActivitiesAfter.CreatedDateTime) {
        Write-Host "No new sign-in detected after revocation. Checking Azure AD audit logs is recommended." -ForegroundColor Yellow
        # Query Azure AD audit logs for session revocation events
        Write-Host "Querying Azure AD audit logs for more details..."
        $auditLogs = Get-MgAuditLogDirectoryAudit -Filter "activityDisplayName eq 'Revoke sign-in sessions' and targetResources/any(t: t/userPrincipalName eq '$userInput')" -Top 5
        $auditLogs | Format-Table -AutoSize
    } else {
        Write-Host "The user's sign-in status has changed. The revocation was successful." -ForegroundColor Green
    }

    # Ask if there are more users to revoke
    $moreUsers = Read-Host "Are there any more users to revoke? (Yes/No)"
    $moreUsers = $moreUsers.Trim().ToLower()

    # Clear the variables for the next user
    if ($moreUsers -eq "yes") {
        Clear-Variable userInput -ErrorAction SilentlyContinue
        Clear-Variable signInActivitiesBefore -ErrorAction SilentlyContinue
        Clear-Variable signInActivitiesAfter -ErrorAction SilentlyContinue
    }

} until ($moreUsers -ne "yes")

Write-Host "Script execution completed." -ForegroundColor Green
