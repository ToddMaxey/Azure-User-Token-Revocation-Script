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
    
    try {
        if (-not (Get-Module -ListAvailable -Name $ModuleName)) {
            Write-Host "Module $ModuleName is not installed. Installing..." -ForegroundColor Yellow
            Install-Module -Name $ModuleName -Force -AllowClobber -ErrorAction Stop
            Write-Host "Module $ModuleName installed successfully." -ForegroundColor Green
        } else {
            Write-Host "Module $ModuleName is already installed." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "Failed to install $ModuleName. Please check your connection or module source." -ForegroundColor Red
        exit
    }
}

# Default settings for Verbose and Debug modes
$VerboseMode = $false
$DebugMode = $false

# Set Execution Policy to RemoteSigned
Write-Host "Temporarily setting the Execution Policy to RemoteSigned for the current session..." -ForegroundColor Yellow
Set-ExecutionPolicy RemoteSigned -Scope Process -Force

# Ensure required modules are installed
Ensure-Module -ModuleName "Microsoft.Graph.Authentication"
Ensure-Module -ModuleName "Microsoft.Graph.Users"
Ensure-Module -ModuleName "Microsoft.Graph.Reports"

# Secure connection to Microsoft Graph
try {
    Write-Host "Connecting to Microsoft Graph with scopes: User.Read.All, AuditLog.Read.All, Directory.Read.All"
    Connect-MgGraph -Scopes "User.Read.All, AuditLog.Read.All, Directory.Read.All" -ErrorAction Stop
}
catch {
    Write-Host "Failed to connect to Microsoft Graph. Ensure you have the necessary permissions and network connectivity." -ForegroundColor Red
    exit
}

# Loop to revoke sessions for multiple users
do {
    $userInput = Read-Host "Please enter the User Principal Name (UPN) or ObjectID of the user"

    # Query the user's last sign-in status before revocation
    try {
        Write-Host "Querying the user's sign-in activity before revocation..."
        $signInActivitiesBefore = Get-MgAuditLogSignIn -Filter "userPrincipalName eq '$userInput' or userId eq '$userInput'" -Top 1 | 
        Select-Object CreatedDateTime, Status, TokenIssuerType, ResourceDisplayName, ApplicationDisplayName, IPAddress
    }
    catch {
        Write-Host "Failed to query sign-in activity for $userInput. Ensure the user exists." -ForegroundColor Red
        continue
    }

    $signInActivitiesBefore | Format-Table -AutoSize

    # Revoke all sessions for the user
    Write-Host "Revoking all sign-in sessions for the user..."
    Revoke-MgUserSignInSession -UserId $userInput -Verbose:$VerboseMode -Debug:$DebugMode
    Write-Host "Sign-in sessions have been revoked for $userInput." -ForegroundColor Yellow

    # Get the last password change timestamp
    try {
        Write-Host "Retrieving the user's last password change date..."
        $userDetails = Get-MgUser -UserId $userInput -Property passwordLastSet
        if ($userDetails.passwordLastSet) {
            Write-Host "User's password was last updated on: $($userDetails.passwordLastSet)" -ForegroundColor Green
        } else {
            Write-Host "Password change information not available for this user." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Failed to retrieve the last password change date for $userInput." -ForegroundColor Red
    }

    # Inform the script runner to have the user reset their password
    Write-Host " "
    Write-Host "[URGENT] The user's password must be reset immediately. Please inform the user to reset their password." -ForegroundColor Red
    Write-Host " "

    # Sleep to give time for token revocation to propagate
    Start-Sleep -Seconds 30  # Increased wait time for propagation

    # Query audit logs for the revocation event
    try {
        Write-Host "Querying the audit logs for the revocation event..."
        $auditLogs = Get-MgAuditLogDirectoryAudit -Filter "activityDisplayName eq 'Revoke sign-in sessions' and targetResources/any(t: t/userPrincipalName eq '$userInput')" -Top 5
        if ($auditLogs) {
            Write-Host "Revocation events found in audit logs:"
            $auditLogs | Format-Table -AutoSize
        } else {
            Write-Host "No revocation events found in the audit logs. Please ensure the revocation process completed successfully." -ForegroundColor Red
        }
    }
    catch {
        Write-Host "Failed to query audit logs for revocation events." -ForegroundColor Red
    }

    # Query the user's sign-in activity after revocation
    try {
        Write-Host "Querying the user's sign-in activity after revocation..."
        $signInActivitiesAfter = Get-MgAuditLogSignIn -Filter "userPrincipalName eq '$userInput' or userId eq '$userInput'" -Top 1 | 
        Select-Object CreatedDateTime, Status, TokenIssuerType, ResourceDisplayName, ApplicationDisplayName, IPAddress
    }
    catch {
        Write-Host "Failed to query sign-in activity after revocation for $userInput." -ForegroundColor Red
        continue
    }

    $signInActivitiesAfter | Format-Table -AutoSize

    # Verify if any new sign-ins occurred after revocation
    if ($signInActivitiesBefore.CreatedDateTime -eq $signInActivitiesAfter.CreatedDateTime) {
        Write-Host "No new sign-in detected after revocation. The user may still have valid access tokens for the session." -ForegroundColor Yellow
    } else {
        Write-Host "The user's sign-in status has changed. The revocation was successful." -ForegroundColor Green
    }

    # Skip user interaction when in Debug mode
    if (-not $DebugMode) {
        $moreUsers = Read-Host "Are there any more users to revoke? (Yes/No)"
        if ($moreUsers -match "^(n|no)$") {
            break
        }
    } else {
        # Automatically set $moreUsers to "no" during Debug mode
        $moreUsers = "no"
    }

    # Clear variables for the next user iteration
    $userInput, $signInActivitiesBefore, $signInActivitiesAfter = $null, $null, $null

} until ($moreUsers -match "^(n|no)$")

Write-Host "Script execution completed." -ForegroundColor Green
