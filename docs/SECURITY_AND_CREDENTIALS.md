# Security & Credentials Strategy

## Principles
1.  **Least Privilege**: The Service Account (`SVC_SIMTREE_RO`) must have ONLY `CONNECT` and `SELECT` permissions on the production schema. No `INSERT/UPDATE/DELETE`.
2.  **No Plaintext Secrets**: Passwords must never appear in scripts, config files, or logs.
3.  **Traceability**: All automated actions are logged and hashed via RunManifest (audit trail).

## Recommended Credential Storage: Windows Credential Manager

This is the preferred method for Windows Server environments.

### Setup (IT Ops)
Run as the Service Account (requires logging in as that user or using `runas` to seed):
```powershell
# Store Oracle Password
$Credential = Get-Credential "OracleProdUser"
[System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Credential.Password) | Out-Null # Mem cleanup check
Export-Clixml -InputObject $Credential -Path "C:\Secure\OracleCred.xml" 
# OR use Windows CredMan if available via VaultCmd
cmdkey /add:SimTreeNavOracle /user:OracleProdUser /pass:********
```

*Note: Since headless service accounts often struggle with DPAPI (Export-Clixml) across sessions if profile loading isn't configured, we recommend **Option B (Encrypted File with ACL)** for robustness if CredMan is flaky.*

### Option B: Encrypted File (Recommended Default)
We use a standard AES-encrypted key file protected by NTFS permissions.

1.  **Create Key**:
    ```powershell
    $Key = New-Object Byte[] 32
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($Key)
    $Key | Set-Content "C:\Secure\SimTreeNav.key" -Encoding Byte
    # ACL: SYSTEM Full, Administrators Full, SVC_SIMTREE_RO Read. NO ONE ELSE.
    ```
2.  **Encrypt & Store Password**:
    ```powershell
    $Pass = ConvertTo-SecureString "YourPassword" -AsPlainText -Force
    $Encrypted = ConvertFrom-SecureString $Pass -Key (Get-Content "C:\Secure\SimTreeNav.key" -Encoding Byte)
    $Encrypted | Set-Content "C:\Secure\OraclePassword.txt"
    ```

### How Scripts Read Credentials
Scripts accept a `-CredentialPath` or look in default secure locations. They decrpyt in-memory only.

```powershell
# Example logic in dashboard-task.ps1
$Key = Get-Content "C:\Secure\SimTreeNav.key" -Encoding Byte
$PassStr = Get-Content "C:\Secure\OraclePassword.txt" | ConvertTo-SecureString -Key $Key
$Cred = New-Object PsCredential("OracleProdUser", $PassStr)
```

## Output Security
- **Share/IIS Permissions**:
  - `SVC_SIMTREE_RO`: **Modify** (to write output).
  - `Domain Users` (or Site Viewers): **Read & Execute** (to view dashboard).
  - No Write access for Viewers.

## Audit Trail
- **RunManifest**: Every execution produces `run-manifest.json` containing:
  - Timestamp
  - Machine Name / User
  - Script Version (Hash)
  - Parameter Inputs
- **Logs**: Retained for 30 days in `out/logs/`.
