# Count studies in _testing project
param(
    [string]$TNSName = "DES_SIM_DB1_DB01",
    [string]$Schema = "DESIGN12",
    [int]$ProjectId = 18851221
)

# Import credential manager
$credManagerPath = Join-Path $PSScriptRoot "..\..\src\powershell\utilities\CredentialManager.ps1"
. $credManagerPath

Write-Host "Counting studies in _testing project (ID: $ProjectId)..." -ForegroundColor Cyan

$connStr = Get-DbConnectionString -TNSName $TNSName -AsSysDBA

$query = @"
SET PAGESIZE 1000
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON

SELECT COUNT(*) as STUDY_COUNT
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.REL_COMMON rc ON rs.OBJECT_ID = rc.OBJECT_ID
WHERE rc.FORWARD_OBJECT_ID = $ProjectId;

EXIT;
"@

$tempFile = Join-Path $env:TEMP "count-studies.sql"
$query | Out-File $tempFile -Encoding ASCII

$result = & sqlplus -S $connStr "@$tempFile" 2>&1

Write-Host "`nResult:" -ForegroundColor Green
$result | ForEach-Object { Write-Host $_ }

Remove-Item $tempFile -ErrorAction SilentlyContinue

Write-Host "`n" -ForegroundColor Cyan
Write-Host "If count is 0, the _testing project is empty." -ForegroundColor Yellow
Write-Host "You'll need to either:" -ForegroundColor Yellow
Write-Host "  1. Create a study in _testing project in Siemens" -ForegroundColor White
Write-Host "  2. Use a different project (like FORD_DEARBORN, ID: 18140190)" -ForegroundColor White
