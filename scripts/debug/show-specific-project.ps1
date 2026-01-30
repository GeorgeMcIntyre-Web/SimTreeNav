# Show specific project by ID
param(
    [string]$TNSName = "DES_SIM_DB1_DB01",
    [string]$Schema = "DESIGN12",
    [int]$ProjectId = 18140190
)

# Import credential manager
$credManagerPath = Join-Path $PSScriptRoot "..\..\src\powershell\utilities\CredentialManager.ps1"
. $credManagerPath

Write-Host "Looking up project ID $ProjectId..." -ForegroundColor Cyan

$connStr = Get-DbConnectionString -TNSName $TNSName -AsSysDBA

$query = @"
SET PAGESIZE 1000
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON

SELECT OBJECT_ID, CAPTION_S_, CLASS_ID, NAME_S_, TO_CHAR(CREATIONDATE_DA_, 'YYYY-MM-DD') as CREATED
FROM $Schema.COLLECTION_
WHERE OBJECT_ID = $ProjectId;

EXIT;
"@

$tempFile = Join-Path $env:TEMP "show-project.sql"
$query | Out-File $tempFile -Encoding ASCII

Write-Host "Executing query..." -ForegroundColor Yellow
$result = & sqlplus -S $connStr "@$tempFile" 2>&1

Write-Host "`nResults for FORD_DEARBORN (ID: $ProjectId):" -ForegroundColor Green
$result | ForEach-Object { Write-Host $_ }

Write-Host "`n" -ForegroundColor Cyan
Write-Host "Now searching for _testing project..." -ForegroundColor Cyan

$query2 = @"
SET PAGESIZE 1000
SET LINESIZE 300
SET FEEDBACK OFF
SET HEADING ON

SELECT OBJECT_ID, CAPTION_S_, CLASS_ID, NAME_S_
FROM $Schema.COLLECTION_
WHERE CAPTION_S_ LIKE '%testing%'
   OR NAME_S_ LIKE '%testing%'
   OR CAPTION_S_ = '_testing'
   OR NAME_S_ = '_testing';

EXIT;
"@

$tempFile2 = Join-Path $env:TEMP "find-testing.sql"
$query2 | Out-File $tempFile2 -Encoding ASCII

$result2 = & sqlplus -S $connStr "@$tempFile2" 2>&1

Write-Host "`nResults for testing search:" -ForegroundColor Green
$result2 | ForEach-Object { Write-Host $_ }

Remove-Item $tempFile, $tempFile2 -ErrorAction SilentlyContinue
