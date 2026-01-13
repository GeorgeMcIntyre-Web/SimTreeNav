# Project Reorganization Script
# Organizes PsSchemaBug project into best practices folder structure for Git publication

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PsSchemaBug Project Reorganization" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "Stop"

# Create directory structure
Write-Host "Creating folder structure..." -ForegroundColor Yellow
$folders = @(
    "src\powershell\main",
    "src\powershell\utilities",
    "src\powershell\database",
    "docs\investigation",
    "docs\api",
    "config",
    "data\icons",
    "data\output",
    "queries\icon-extraction",
    "queries\tree-navigation",
    "queries\analysis",
    "queries\investigation",
    "tests",
    "scripts"
)

foreach ($folder in $folders) {
    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
        Write-Host "  Created: $folder" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Moving files to organized structure..." -ForegroundColor Yellow

# Move main PowerShell scripts
Write-Host "  Moving main scripts..." -ForegroundColor Cyan
$mainScripts = @(
    "tree-viewer-launcher.ps1",
    "generate-tree-html.ps1",
    "generate-full-tree-html.ps1",
    "extract-icons-hex.ps1"
)
foreach ($script in $mainScripts) {
    if (Test-Path $script) {
        Move-Item $script "src\powershell\main\" -Force
        Write-Host "    $script -> src\powershell\main\" -ForegroundColor Gray
    }
}

# Move utility scripts
Write-Host "  Moving utility scripts..." -ForegroundColor Cyan
$utilityScripts = @(
    "common-queries.ps1",
    "icon-mapping.ps1",
    "query-db.ps1",
    "explore-db.ps1"
)
foreach ($script in $utilityScripts) {
    if (Test-Path $script) {
        Move-Item $script "src\powershell\utilities\" -Force
        Write-Host "    $script -> src\powershell\utilities\" -ForegroundColor Gray
    }
}

# Move database scripts
Write-Host "  Moving database scripts..." -ForegroundColor Cyan
$dbScripts = @(
    "install-oracle-client.ps1",
    "setup-env-vars.ps1",
    "connect-db.ps1",
    "test-connection.ps1"
)
foreach ($script in $dbScripts) {
    if (Test-Path $script) {
        Move-Item $script "src\powershell\database\" -Force
        Write-Host "    $script -> src\powershell\database\" -ForegroundColor Gray
    }
}

# Move documentation
Write-Host "  Moving documentation..." -ForegroundColor Cyan
$mainDocs = @(
    "QUICK-START-GUIDE.md",
    "DATABASE-STRUCTURE-SUMMARY.md",
    "README-ORACLE-SETUP.md"
)
foreach ($doc in $mainDocs) {
    if (Test-Path $doc) {
        Move-Item $doc "docs\" -Force
        Write-Host "    $doc -> docs\" -ForegroundColor Gray
    }
}

# Move investigation docs
$investigationDocs = @(
    "ICON-EXTRACTION-ATTEMPTS.md",
    "ICON-EXTRACTION-SUCCESS.md",
    "README-ICONS.md",
    "CUSTOM-ORDERING-SOLUTION.md",
    "NODE-ORDERING-FIX.md",
    "ORDERING-INVESTIGATION-RESULTS.md",
    "ORDERING-SOLUTION-OPTIONS.md"
)
foreach ($doc in $investigationDocs) {
    if (Test-Path $doc) {
        Move-Item $doc "docs\investigation\" -Force
        Write-Host "    $doc -> docs\investigation\" -ForegroundColor Gray
    }
}

# Move API docs
$apiDocs = @(
    "QUERY-EXAMPLES.md",
    "PROJECT-NAMES-SUMMARY.md"
)
foreach ($doc in $apiDocs) {
    if (Test-Path $doc) {
        Move-Item $doc "docs\api\" -Force
        Write-Host "    $doc -> docs\api\" -ForegroundColor Gray
    }
}

# Move config files
Write-Host "  Moving configuration files..." -ForegroundColor Cyan
$configFiles = @(
    "database-servers.json",
    "tree-viewer-config.json",
    "tnsnames.ora.template"
)
foreach ($file in $configFiles) {
    if (Test-Path $file) {
        Move-Item $file "config\" -Force
        Write-Host "    $file -> config\" -ForegroundColor Gray
    }
}

# Move data files
Write-Host "  Moving data files..." -ForegroundColor Cyan
$dataFiles = @(
    "extracted-type-ids.json",
    "all-icons.csv"
)
foreach ($file in $dataFiles) {
    if (Test-Path $file) {
        Move-Item $file "data\" -Force
        Write-Host "    $file -> data\" -ForegroundColor Gray
    }
}

# Move icons (already in icons/ folder, just move the folder)
if (Test-Path "icons") {
    Write-Host "  Icons already in icons/ folder" -ForegroundColor Cyan
    # Icons folder will be moved at the end
}

# Move HTML outputs
Write-Host "  Moving HTML outputs..." -ForegroundColor Cyan
$htmlFiles = Get-ChildItem -Filter "*.html"
foreach ($file in $htmlFiles) {
    Move-Item $file.FullName "data\output\" -Force
    Write-Host "    $file -> data\output\" -ForegroundColor Gray
}

# Organize SQL queries
Write-Host "  Organizing SQL queries..." -ForegroundColor Cyan

# Icon extraction queries
$iconQueries = Get-ChildItem -Filter "*.sql" | Where-Object {
    $_.Name -match "icon" -or $_.Name -match "df.*icon" -or $_.Name -match "extract.*icon"
}
foreach ($file in $iconQueries) {
    Move-Item $file.FullName "queries\icon-extraction\" -Force
    Write-Host "    $file -> queries\icon-extraction\" -ForegroundColor Gray
}

# Tree navigation queries
$treeQueries = Get-ChildItem -Filter "*.sql" | Where-Object {
    $_.Name -match "tree" -or $_.Name -match "navigation" -or $_.Name -match "get-.*tree" -or $_.Name -match "find-.*tree"
}
foreach ($file in $treeQueries) {
    Move-Item $file.FullName "queries\tree-navigation\" -Force
    Write-Host "    $file -> queries\tree-navigation\" -ForegroundColor Gray
}

# Analysis and check queries
$analysisQueries = Get-ChildItem -Filter "*.sql" | Where-Object {
    $_.Name -match "^check-" -or $_.Name -match "^analyze-" -or $_.Name -match "^compare-" -or $_.Name -match "^deep-"
}
foreach ($file in $analysisQueries) {
    Move-Item $file.FullName "queries\analysis\" -Force
    Write-Host "    $file -> queries\analysis\" -ForegroundColor Gray
}

# Investigation queries (remaining)
$investigationQueries = Get-ChildItem -Filter "*.sql"
foreach ($file in $investigationQueries) {
    Move-Item $file.FullName "queries\investigation\" -Force
    Write-Host "    $file -> queries\investigation\" -ForegroundColor Gray
}

# Move test files
Write-Host "  Moving test files..." -ForegroundColor Cyan
$testFiles = @(
    "test-toggle.html",
    "icon-test.html"
)
foreach ($file in $testFiles) {
    if (Test-Path $file) {
        Move-Item $file "tests\" -Force
        Write-Host "    $file -> tests\" -ForegroundColor Gray
    }
}

# Move text outputs to tests (they're investigation outputs)
Write-Host "  Moving investigation output files..." -ForegroundColor Cyan
$txtFiles = Get-ChildItem -Filter "*.txt"
foreach ($file in $txtFiles) {
    if ($file.Name -notlike "tree-data-*") {
        Move-Item $file.FullName "tests\" -Force
        Write-Host "    $file -> tests\" -ForegroundColor Gray
    }
}

# Move tree data files to data/output
$treeDataFiles = Get-ChildItem -Filter "tree-data-*.txt"
foreach ($file in $treeDataFiles) {
    Move-Item $file.FullName "data\output\" -Force
    Write-Host "    $file -> data\output\" -ForegroundColor Gray
}

# Move log files to tests
Write-Host "  Moving log files..." -ForegroundColor Cyan
$logFiles = Get-ChildItem -Filter "*.log"
foreach ($file in $logFiles) {
    Move-Item $file.FullName "tests\" -Force
    Write-Host "    $file -> tests\" -ForegroundColor Gray
}

# Move project-specific files
Write-Host "  Moving project-specific files..." -ForegroundColor Cyan
$projectFiles = @(
    "J7337_Rosslyn-Navigation-Tree.md"
)
foreach ($file in $projectFiles) {
    if (Test-Path $file) {
        Move-Item $file "docs\api\" -Force
        Write-Host "    $file -> docs\api\" -ForegroundColor Gray
    }
}

# Handle icons folder
if (Test-Path "icons") {
    Write-Host "  Moving icons folder..." -ForegroundColor Cyan
    # Remove data\icons if it exists (empty)
    if (Test-Path "data\icons") {
        Remove-Item "data\icons" -Force -Recurse
    }
    Move-Item "icons" "data\icons" -Force
    Write-Host "    icons\ -> data\icons\" -ForegroundColor Gray
}

# Keep tnsnames.ora in root (user-specific, will be in .gitignore)
if (Test-Path "tnsnames.ora") {
    Write-Host "  Keeping tnsnames.ora in root (user-specific)" -ForegroundColor Yellow
}

# Move this reorganization script to scripts/
Write-Host "  Moving this script to scripts/..." -ForegroundColor Cyan
if (Test-Path "scripts\reorganize-project.ps1") {
    Remove-Item "scripts\reorganize-project.ps1" -Force
}
Copy-Item $PSCommandPath "scripts\reorganize-project.ps1" -Force

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Reorganization Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Review the organized structure" -ForegroundColor White
Write-Host "  2. Run: .\scripts\create-gitignore.ps1" -ForegroundColor White
Write-Host "  3. Run: .\scripts\create-readme.ps1" -ForegroundColor White
Write-Host "  4. Initialize Git: git init" -ForegroundColor White
Write-Host "  5. Commit: git add . && git commit -m 'Initial commit'" -ForegroundColor White
Write-Host ""
