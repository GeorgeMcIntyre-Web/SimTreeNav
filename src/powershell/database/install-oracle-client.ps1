# Oracle 12c Instant Client Installation Script for Windows
# This script downloads and installs Oracle Instant Client for terminal access

param(
    [string]$InstallPath = "C:\Oracle\instantclient_12_2",
    [switch]$SkipDownload = $false
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Oracle 12c Instant Client Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if running as Administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "WARNING: Not running as Administrator. Some operations may require elevation." -ForegroundColor Yellow
    Write-Host ""
}

# Create installation directory
Write-Host "Creating installation directory: $InstallPath" -ForegroundColor Green
New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null

# Download URLs for Oracle Instant Client 12.2.0.1.0 (64-bit)
# Note: These are the direct download links - user may need to accept Oracle license
$baseUrl = "https://download.oracle.com/otn/nt/instantclient/122010"
$packages = @(
    @{Name = "Basic Package"; File = "instantclient-basic-windows.x64-12.2.0.1.0.zip"; Required = $true},
    @{Name = "SQL*Plus Package"; File = "instantclient-sqlplus-windows.x64-12.2.0.1.0.zip"; Required = $true},
    @{Name = "Tools Package"; File = "instantclient-tools-windows.x64-12.2.0.1.0.zip"; Required = $false}
)

$downloadDir = Join-Path $env:TEMP "oracle-instantclient-downloads"
New-Item -ItemType Directory -Force -Path $downloadDir | Out-Null

if (-not $SkipDownload) {
    Write-Host ""
    Write-Host "Downloading Oracle Instant Client packages..." -ForegroundColor Green
    Write-Host "NOTE: You may need to accept Oracle's license agreement." -ForegroundColor Yellow
    Write-Host ""
    
    foreach ($package in $packages) {
        if ($package.Required) {
            $url = "$baseUrl/$($package.File)"
            $outputPath = Join-Path $downloadDir $package.File
            
            Write-Host "Downloading $($package.Name)..." -ForegroundColor Cyan
            Write-Host "  URL: $url" -ForegroundColor Gray
            Write-Host "  Save to: $outputPath" -ForegroundColor Gray
            
            try {
                # Use Invoke-WebRequest with proper headers
                $headers = @{
                    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                }
                
                # Note: Oracle downloads may require authentication/cookies
                # User may need to download manually from Oracle website
                Write-Host "  Attempting download..." -ForegroundColor Yellow
                
                # Try to download - if this fails, provide manual instructions
                try {
                    Invoke-WebRequest -Uri $url -OutFile $outputPath -Headers $headers -UseBasicParsing
                    Write-Host "  ✓ Downloaded successfully" -ForegroundColor Green
                } catch {
                    Write-Host "  ✗ Automatic download failed (Oracle may require manual download)" -ForegroundColor Red
                    Write-Host "  Please download manually from:" -ForegroundColor Yellow
                    Write-Host "    https://www.oracle.com/database/technologies/instant-client/winx64-64-downloads.html" -ForegroundColor Yellow
                    Write-Host "  Required files:" -ForegroundColor Yellow
                    Write-Host "    - instantclient-basic-windows.x64-12.2.0.1.0.zip" -ForegroundColor Yellow
                    Write-Host "    - instantclient-sqlplus-windows.x64-12.2.0.1.0.zip" -ForegroundColor Yellow
                    Write-Host ""
                    Write-Host "  Place downloaded files in: $downloadDir" -ForegroundColor Yellow
                    Write-Host "  Then run this script again with -SkipDownload parameter" -ForegroundColor Yellow
                    exit 1
                }
            } catch {
                Write-Host "  ✗ Error downloading: $_" -ForegroundColor Red
                exit 1
            }
        }
    }
} else {
    Write-Host "Skipping download. Using files in: $downloadDir" -ForegroundColor Yellow
}

# Extract packages
Write-Host ""
Write-Host "Extracting Oracle Instant Client packages..." -ForegroundColor Green

$requiredFiles = @(
    "instantclient-basic-windows.x64-12.2.0.1.0.zip",
    "instantclient-sqlplus-windows.x64-12.2.0.1.0.zip"
)

foreach ($file in $requiredFiles) {
    $zipPath = Join-Path $downloadDir $file
    if (Test-Path $zipPath) {
        Write-Host "Extracting $file..." -ForegroundColor Cyan
        Expand-Archive -Path $zipPath -DestinationPath $InstallPath -Force
    } else {
        Write-Host "✗ Required file not found: $file" -ForegroundColor Red
        Write-Host "  Expected location: $zipPath" -ForegroundColor Yellow
        exit 1
    }
}

# Move files from subdirectory to main directory if needed
$subDirs = Get-ChildItem -Path $InstallPath -Directory | Where-Object { $_.Name -like "instantclient_*" }
if ($subDirs.Count -gt 0) {
    Write-Host "Moving files from subdirectory..." -ForegroundColor Cyan
    $subDir = $subDirs[0].FullName
    Get-ChildItem -Path $subDir | Move-Item -Destination $InstallPath -Force
    Remove-Item -Path $subDir -Force
}

# Create Network/Admin directory for TNS configuration
$networkAdminPath = Join-Path $InstallPath "network\admin"
New-Item -ItemType Directory -Force -Path $networkAdminPath | Out-Null
Write-Host "Created TNS configuration directory: $networkAdminPath" -ForegroundColor Green

# Copy tnsnames.ora if it exists in current directory
$localTnsFile = Join-Path $PSScriptRoot "tnsnames.ora"
if (Test-Path $localTnsFile) {
    $targetTnsFile = Join-Path $networkAdminPath "tnsnames.ora"
    Copy-Item -Path $localTnsFile -Destination $targetTnsFile -Force
    Write-Host "Copied tnsnames.ora to: $targetTnsFile" -ForegroundColor Green
} else {
    Write-Host "NOTE: tnsnames.ora not found in script directory. You may need to configure it manually." -ForegroundColor Yellow
}

# Set environment variables
Write-Host ""
Write-Host "Setting environment variables..." -ForegroundColor Green

$envVars = @{
    "ORACLE_HOME" = $InstallPath
    "TNS_ADMIN" = $networkAdminPath
}

foreach ($var in $envVars.GetEnumerator()) {
    Write-Host "  Setting $($var.Key) = $($var.Value)" -ForegroundColor Cyan
    
    # Set for current session
    [Environment]::SetEnvironmentVariable($var.Key, $var.Value, "Process")
    
    # Set for user (persistent)
    [Environment]::SetEnvironmentVariable($var.Key, $var.Value, "User")
    
    # Set for system (requires admin)
    if ($isAdmin) {
        [Environment]::SetEnvironmentVariable($var.Key, $var.Value, "Machine")
    }
}

# Add to PATH
$binPath = Join-Path $InstallPath "bin"
if ($env:PATH -notlike "*$binPath*") {
    Write-Host "  Adding $binPath to PATH" -ForegroundColor Cyan
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $newPath = "$currentPath;$binPath"
    [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    
    if ($isAdmin) {
        $currentPathMachine = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        $newPathMachine = "$currentPathMachine;$binPath"
        [Environment]::SetEnvironmentVariable("PATH", $newPathMachine, "Machine")
    }
    
    # Update current session PATH
    $env:PATH = "$env:PATH;$binPath"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Oracle Instant Client installed to: $InstallPath" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Configure tnsnames.ora in: $networkAdminPath" -ForegroundColor White
Write-Host "2. Restart your terminal/PowerShell to load new environment variables" -ForegroundColor White
Write-Host "3. Test connection using: sqlplus username/password@tnsname" -ForegroundColor White
Write-Host ""
Write-Host "To verify installation, run:" -ForegroundColor Yellow
Write-Host "  sqlplus -V" -ForegroundColor White
Write-Host ""
