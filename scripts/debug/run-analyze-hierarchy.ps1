Import-Module .\src\powershell\utilities\CredentialManager.ps1 -Force
$connStr = Get-DbConnectionString -TNSName "DB01" -AsSysDBA
$env:NLS_LANG = "AMERICAN_AMERICA.UTF8"
sqlplus -S $connStr "@analyze-operation-hierarchy.sql"
