### **Synopsis of the Script Function:**

This PowerShell script is designed to **revoke all active sign-in sessions** for one or more Azure AD users and prompt the script runner to manually instruct each user to **reset their password**. The script first checks if the necessary Microsoft Graph PowerShell modules are installed and then establishes a connection to Microsoft Graph with the required scopes. It retrieves and displays the user's last password change timestamp, revokes the user's sign-in sessions, and verifies the success of the revocation by querying Azure AD audit logs. Finally, it prompts the script runner to manually inform the user to reset their password for enhanced security.

### **Detailed Description of the Script:**

1. **Administrative Privilege Check (`Test-IsAdmin`)**:
   The script begins by ensuring it is being run with elevated privileges (as an administrator). This is essential for installing modules or running commands that interact with Microsoft Graph.

2. **Module Installation and Verification (`Ensure-Module`)**:
   - The `Ensure-Module` function is called to check if the necessary PowerShell modules (such as **Microsoft.Graph.Authentication**, **Microsoft.Graph.Users**, and **Microsoft.Graph.Reports**) are installed.
   - If any required module is missing, the script installs it using the **`Install-Module`** cmdlet.
   
3. **Setting Execution Policy**:
   - The script temporarily sets the PowerShell execution policy to **RemoteSigned** to allow scripts to run in the session, ensuring that remote scripts with valid signatures can be executed.

4. **Microsoft Graph Connection**:
   - The script connects to **Microsoft Graph** using the **`Connect-MgGraph`** cmdlet with the scopes **User.Read.All**, **AuditLog.Read.All**, and **Directory.Read.All** to retrieve user information, audit logs, and revoke sessions.
   - If the connection fails, an error message is displayed, and the script exits.

5. **Main Loop for Processing Users**:
   - The script enters a loop where it processes one or more users by prompting for their **User Principal Name (UPN)** or **ObjectID**.
   
6. **Querying the User's Last Sign-In Activity**:
   - Before revoking the user's sessions, the script queries **Azure AD sign-in logs** for the user's most recent sign-in activity using **`Get-MgAuditLogSignIn`**. It retrieves details such as the sign-in time, status, application used, and IP address.
   - The results are displayed in a table for the script runner’s reference.

7. **Revoking All Sign-In Sessions**:
   - The script revokes all active sign-in sessions for the specified user by calling **`Revoke-MgUserSignInSession`**.
   - This action invalidates all refresh tokens, forcing the user to reauthenticate on their next login.

8. **Retrieving the User’s Last Password Change Timestamp**:
   - After revoking the sign-in sessions, the script retrieves the user's **last password change timestamp** using **`Get-MgUser`** with the `passwordLastSet` property.
   - The date and time of the last password update are displayed. If this information is unavailable, the script provides an error message.
   
9. **Password Reset Instruction**:
   - The script runner is explicitly instructed to inform the user to manually reset their password. This message is highlighted for urgency, ensuring the script runner takes immediate action to further secure the user account.

10. **Waiting for Session Revocation to Propagate**:
    - To allow the session revocation to propagate through Azure AD, the script pauses for 30 seconds using **`Start-Sleep`**.

11. **Querying the Audit Logs for Revocation Confirmation**:
    - The script queries **Azure AD audit logs** to check if the session revocation event has been logged. The audit log query uses **`Get-MgAuditLogDirectoryAudit`** to look for the "Revoke sign-in sessions" activity.
    - If audit logs confirm the revocation, the details are displayed. If no audit events are found, the script issues a warning, prompting the script runner to verify the success of the revocation.

12. **Querying the User's Post-Revocation Sign-In Activity**:
    - The script checks the user's sign-in activity again to ensure no new sign-ins have occurred since the session revocation. If the sign-in timestamp remains unchanged, the user might still have valid access tokens, and the script informs the runner accordingly.

13. **Prompt for Additional Users**:
    - After processing the current user, the script prompts the runner to decide whether to revoke sessions for another user. The loop repeats if more users need to be processed.
   
14. **Completion Message**:
    - Once all users have been processed, the script displays a final message indicating that the script execution is complete.

### **Key Script Components**:
1. **User Session Revocation**:
   - The script ensures that user sessions are revoked, forcing users to reauthenticate.
   
2. **Manual Password Reset Notification**:
   - The script runner is prompted to ensure that users reset their passwords, which adds an additional layer of security by invalidating any remaining valid access tokens.

3. **Audit Logging**:
   - By querying the audit logs, the script helps verify that session revocation events were successfully logged.

4. **Last Password Change Timestamp**:
   - Displaying the last password change timestamp helps the script runner assess whether the user’s password has been changed recently and whether further action is required.

### **Use Case**:
This script is ideal for system administrators looking to revoke user sessions in Azure AD without using overly powerful permissions like **User.ReadWrite.All**. Instead, it focuses on revoking sessions and guiding the administrator to enforce password resets manually.
