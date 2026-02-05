# fix-dbca-java.ps1
# Fix hardcoded Java path in dbca.bat

$dbcaPath = "F:\Oracle\WINDOWS.X64_193000_db_home\bin\dbca.bat"

# Read content
$content = Get-Content $dbcaPath -Raw

# Replace hardcoded Java path
$oldJavaPath = '"C:\app09\oracle\base\product\19.0.0\dbhome_1\jdk\jre\BIN\JAVA"'
$newJavaPath = '"%OH%\jdk\jre\BIN\JAVA"'

$content = $content.Replace($oldJavaPath, $newJavaPath)

# Write back
$content | Set-Content $dbcaPath -NoNewline

Write-Host "Fixed Java path in dbca.bat:" -ForegroundColor Yellow
Write-Host "  Old: $oldJavaPath" -ForegroundColor Red
Write-Host "  New: $newJavaPath" -ForegroundColor Green

# Verify
Write-Host ""
Write-Host "Verification:" -ForegroundColor Cyan
Get-Content $dbcaPath | Select-String "JAVA"
