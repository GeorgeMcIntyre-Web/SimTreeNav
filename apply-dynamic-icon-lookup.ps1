# Apply dynamic icon lookup to all remaining TO_CHAR(cd.TYPE_ID) in SQL file
$ErrorActionPreference = "Stop"

$sqlFile = "get-tree-DESIGN12-18140190.sql"

Write-Host "Reading SQL file..." -ForegroundColor Cyan
$content = Get-Content $sqlFile -Raw

# Pattern to find and replace
$oldPattern = "    TO_CHAR(cd.TYPE_ID)`r`nFROM DESIGN12.REL_COMMON r`r`nINNER JOIN DESIGN12.(\w+) "
$newPattern = "    -- Dynamic parent class icon lookup`r`n    TO_CHAR(COALESCE(`r`n        (SELECT di.TYPE_ID FROM DESIGN12.DF_ICONS_DATA di WHERE di.TYPE_ID = cd.TYPE_ID),`r`n        (SELECT di.TYPE_ID FROM DESIGN12.DF_ICONS_DATA di WHERE di.TYPE_ID = cd.DERIVED_FROM),`r`n        cd.TYPE_ID`r`n    ))`r`nFROM DESIGN12.REL_COMMON r`r`nINNER JOIN DESIGN12.`$1 "

Write-Host "Applying dynamic icon lookup pattern..." -ForegroundColor Yellow

# Replace all remaining patterns
$content = $content -replace $oldPattern, $newPattern

Write-Host "Writing updated SQL file..." -ForegroundColor Cyan
$content | Set-Content $sqlFile -NoNewline

Write-Host "Done! All remaining TYPE_ID references updated." -ForegroundColor Green
