# fix-dbca.ps1
# Fix hardcoded Oracle Home path in dbca.bat

$dbcaPath = "F:\Oracle\WINDOWS.X64_193000_db_home\bin\dbca.bat"
$backupPath = "F:\Oracle\WINDOWS.X64_193000_db_home\bin\dbca.bat.original"

# Backup original file
if (-not (Test-Path $backupPath)) {
    Copy-Item $dbcaPath $backupPath
    Write-Host "Created backup: $backupPath" -ForegroundColor Green
}

# Read content
$content = Get-Content $dbcaPath -Raw

# Replace hardcoded path
$oldPath = '@set OH=C:\app09\oracle\base\product\19.0.0\dbhome_1'
$newPath = '@set OH=F:\Oracle\WINDOWS.X64_193000_db_home'

$content = $content.Replace($oldPath, $newPath)

# Write back
$content | Set-Content $dbcaPath -NoNewline

Write-Host "Fixed dbca.bat:" -ForegroundColor Yellow
Write-Host "  Old: $oldPath" -ForegroundColor Red
Write-Host "  New: $newPath" -ForegroundColor Green

# Verify
$verification = Get-Content $dbcaPath | Select-String "^@set OH="
Write-Host "Verified: $verification" -ForegroundColor Cyan
