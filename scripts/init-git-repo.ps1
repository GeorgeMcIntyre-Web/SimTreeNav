# Initialize Git Repository
# Sets up Git repo with proper configuration for the project

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Initialize Git Repository" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if Git is installed
try {
    $gitVersion = git --version
    Write-Host "Git version: $gitVersion" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Git is not installed or not in PATH" -ForegroundColor Red
    Write-Host "Please install Git from: https://git-scm.com/download/win" -ForegroundColor Yellow
    exit 1
}

# Check if already a Git repo
if (Test-Path ".git") {
    Write-Host "WARNING: This directory is already a Git repository" -ForegroundColor Yellow
    $response = Read-Host "Do you want to reinitialize? (y/N)"
    if ($response -ne "y") {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
    Remove-Item ".git" -Recurse -Force
}

Write-Host ""
Write-Host "Initializing Git repository..." -ForegroundColor Yellow

# Initialize repo
git init
Write-Host "  Git repository initialized" -ForegroundColor Green

# Configure Git (optional - user can override)
Write-Host ""
Write-Host "Configuring Git..." -ForegroundColor Yellow

$userName = Read-Host "Enter your Git username (or press Enter to skip)"
if ($userName) {
    git config user.name $userName
    Write-Host "  User name set: $userName" -ForegroundColor Green
}

$userEmail = Read-Host "Enter your Git email (or press Enter to skip)"
if ($userEmail) {
    git config user.email $userEmail
    Write-Host "  User email set: $userEmail" -ForegroundColor Green
}

# Set default branch to main
git branch -M main
Write-Host "  Default branch: main" -ForegroundColor Green

# Add all files
Write-Host ""
Write-Host "Adding files to staging area..." -ForegroundColor Yellow
git add .

# Show status
Write-Host ""
Write-Host "Git status:" -ForegroundColor Yellow
git status --short

# Count files
$stagedFiles = (git diff --cached --name-only).Count
Write-Host ""
Write-Host "Ready to commit: $stagedFiles files" -ForegroundColor Green

# Offer to create initial commit
Write-Host ""
$createCommit = Read-Host "Create initial commit? (Y/n)"
if ($createCommit -ne "n") {
    git commit -m "Initial commit: Siemens Process Simulation Tree Viewer

- PowerShell scripts for tree generation and icon extraction
- SQL queries for database analysis
- Documentation and investigation notes
- Configuration templates
- Project structure organized for Git publication"

    Write-Host ""
    Write-Host "Initial commit created!" -ForegroundColor Green

    # Show commit info
    git log --oneline -1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Git Repository Ready!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Create a repository on GitHub" -ForegroundColor White
Write-Host "  2. Add remote: git remote add origin <URL>" -ForegroundColor White
Write-Host "  3. Push: git push -u origin main" -ForegroundColor White
Write-Host ""
Write-Host "GitHub repository creation:" -ForegroundColor Yellow
Write-Host "  https://github.com/new" -ForegroundColor Cyan
Write-Host ""
