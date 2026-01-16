# Utility script to batch-update all scripts to use credential manager
# This is a helper script for the credential system migration

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Batch Update Scripts" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Files to update and their patterns
$filesToUpdate = @(
    @{
        Path = "src/powershell/main/extract-icons-hex.ps1"
        Pattern = '$result = sqlplus -S sys/change_on_install@$TNSName AS SYSDBA "@$testFile" 2>&1'
        Replacement = @'
try {
    $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
} catch {
    Write-Warning "Failed to get credentials, using default"
    $connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
}
$result = sqlplus -S $connectionString "@$testFile" 2>&1
'@
        AddImport = $true
    },
    @{
        Path = "src/powershell/main/extract-icons-hex.ps1"
        Pattern = '$result = sqlplus -S sys/change_on_install@$TNSName AS SYSDBA "@$allIconsFile" 2>&1'
        Replacement = @'
try {
    $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
} catch {
    Write-Warning "Failed to get credentials, using default"
    $connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
}
$result = sqlplus -S $connectionString "@$allIconsFile" 2>&1
'@
    }
)

$importBlock = @'

# Import credential manager
$credManagerPath = Join-Path $PSScriptRoot "..\utilities\CredentialManager.ps1"
if (Test-Path $credManagerPath) {
    Import-Module $credManagerPath -Force
} else {
    Write-Warning "Credential manager not found. Falling back to default password."
}
'@

# Process each file
foreach ($file in $filesToUpdate) {
    $filePath = Join-Path $PSScriptRoot "..\..\..\" $file.Path

    if (-not (Test-Path $filePath)) {
        Write-Warning "File not found: $filePath"
        continue
    }

    Write-Host "Processing: $($file.Path)" -ForegroundColor Yellow

    $content = Get-Content $filePath -Raw

    # Add import if needed
    if ($file.AddImport) {
        # Find where to insert (after param block)
        if ($content -match '(?s)(param\s*\([^)]*\)\s*)') {
            $insertPoint = $matches[0].Length
            $content = $content.Substring(0, $insertPoint) + $importBlock + $content.Substring($insertPoint)
            Write-Host "  ✓ Added credential manager import" -ForegroundColor Green
        }
    }

    # Replace pattern
    if ($content -like "*$($file.Pattern)*") {
        $content = $content -replace [regex]::Escape($file.Pattern), $file.Replacement
        Write-Host "  ✓ Updated credential usage" -ForegroundColor Green

        # Save file
        $content | Out-File $filePath -Encoding UTF8 -NoNewline
    } else {
        Write-Host "  ⚠ Pattern not found (may already be updated)" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "✓ Batch update complete!" -ForegroundColor Green
