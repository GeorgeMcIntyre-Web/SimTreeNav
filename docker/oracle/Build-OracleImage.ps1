# Build-OracleImage.ps1
# Builds Oracle Database 12.2.0.1 Docker image from Oracle's official Dockerfiles
#
# Prerequisites:
#   - Oracle Database 12.2.0.1 installation zip file downloaded
#   - Docker Desktop running
#
# Usage:
#   .\Build-OracleImage.ps1 -Edition SE2
#   .\Build-OracleImage.ps1 -Edition EE -ZipFile "C:\Downloads\linuxx64_12201_database.zip"

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("SE2", "EE")]
    [string]$Edition = "SE2",

    [Parameter(Mandatory=$false)]
    [string]$ZipFile,

    [string]$Version = "12.2.0.1",

    [switch]$SkipImageBuild
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Oracle Database Docker Image Builder" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Edition: $Edition" -ForegroundColor White
Write-Host "  Version: $Version" -ForegroundColor White
Write-Host ""

# Step 1: Check Docker is running
Write-Host "Checking Docker..." -ForegroundColor Yellow
try {
    docker version | Out-Null
    Write-Host "  Docker is running" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Docker is not running. Please start Docker Desktop." -ForegroundColor Red
    exit 1
}

# Step 2: Clone Oracle docker-images repo
$oracleRepoDir = Join-Path $scriptDir "oracle-docker-images"
$dockerfilesDir = Join-Path $oracleRepoDir "OracleDatabase\SingleInstance\dockerfiles"

if (-not (Test-Path $oracleRepoDir)) {
    Write-Host ""
    Write-Host "Cloning Oracle docker-images repository..." -ForegroundColor Yellow
    git clone https://github.com/oracle/docker-images.git $oracleRepoDir
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to clone Oracle repository." -ForegroundColor Red
        exit 1
    }
    Write-Host "  Repository cloned" -ForegroundColor Green
} else {
    Write-Host "Oracle docker-images repository already exists" -ForegroundColor Green
}

# Step 3: Locate or prompt for Oracle Database zip file
Write-Host ""
Write-Host "Locating Oracle Database installation file..." -ForegroundColor Yellow

if (-not $ZipFile) {
    # Check Downloads folder
    $possibleFiles = @(
        "$env:USERPROFILE\Downloads\WINDOWS.X64_193000_db_home.zip",
        "$env:USERPROFILE\Downloads\linuxx64_12201_database.zip",
        "$env:USERPROFILE\Downloads\linuxamd64_12201_database.zip"
    )

    foreach ($file in $possibleFiles) {
        if (Test-Path $file) {
            $ZipFile = $file
            Write-Host "  Found: $ZipFile" -ForegroundColor Green
            break
        }
    }
}

if (-not $ZipFile -or -not (Test-Path $ZipFile)) {
    Write-Host ""
    Write-Host "Oracle Database installation file not found." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Download from:" -ForegroundColor Cyan
    Write-Host "  https://www.oracle.com/database/technologies/oracle-database-software-downloads.html" -ForegroundColor White
    Write-Host ""
    Write-Host "Required file (Linux x64):" -ForegroundColor Cyan
    Write-Host "  - Oracle Database 12.2.0.1 - linuxx64_12201_database.zip" -ForegroundColor White
    Write-Host ""

    $ZipFile = Read-Host "Enter the full path to the Oracle Database zip file"

    if (-not (Test-Path $ZipFile)) {
        Write-Host "ERROR: File not found: $ZipFile" -ForegroundColor Red
        exit 1
    }
}

Write-Host "  Using: $ZipFile" -ForegroundColor White
Write-Host "  Size: $([math]::Round((Get-Item $ZipFile).Length / 1GB, 2)) GB" -ForegroundColor Gray

# Step 4: Copy zip file to Dockerfiles directory
Write-Host ""
Write-Host "Copying installation file to build directory..." -ForegroundColor Yellow

$targetZipPath = Join-Path $dockerfilesDir "$Version\$(Split-Path $ZipFile -Leaf)"
$targetDir = Join-Path $dockerfilesDir $Version

if (-not (Test-Path $targetDir)) {
    Write-Host "ERROR: Docker build directory not found: $targetDir" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $targetZipPath)) {
    Copy-Item $ZipFile -Destination $targetZipPath -Force
    Write-Host "  Copied to: $targetZipPath" -ForegroundColor Green
} else {
    Write-Host "  File already in build directory" -ForegroundColor Green
}

# Step 5: Build the Docker image
if ($SkipImageBuild) {
    Write-Host ""
    Write-Host "Skipping image build (-SkipImageBuild)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To build manually:" -ForegroundColor Cyan
    Write-Host "  cd $dockerfilesDir" -ForegroundColor Gray
    Write-Host "  ./buildContainerImage.sh -v $Version -$Edition" -ForegroundColor Gray
    exit 0
}

Write-Host ""
Write-Host "Building Docker image..." -ForegroundColor Yellow
Write-Host "  This will take 20-30 minutes..." -ForegroundColor Gray
Write-Host ""

Set-Location $dockerfilesDir

# Build command - using bash for the .sh script
$buildScript = "buildContainerImage.sh"
$buildArgs = "-v $Version -$($Edition.ToLower())"

# Run the build script
bash $buildScript $buildArgs.Split(' ')

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  Image Built Successfully!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""

    # Check the image name
    $imageName = "oracle/database:$Version-$($Edition.ToLower())"
    docker images $imageName --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"

    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Update docker-compose.yml to use: $imageName" -ForegroundColor White
    Write-Host "  2. Run: .\Start-OracleDocker.ps1" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "ERROR: Image build failed." -ForegroundColor Red
    Write-Host "Check the output above for errors." -ForegroundColor Yellow
    exit 1
}
