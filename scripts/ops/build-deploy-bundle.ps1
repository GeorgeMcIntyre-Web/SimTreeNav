<#
.SYNOPSIS
    Builds the production deployment bundle for SimTreeNav.
    Copies required artifacts to a deployment root and generates a manifest.

.PARAMETER Param
    RepoRoot - Source repository logic (Default: current location)
    DeployRoot - Destination for the bundle (Default: .\out\staging_root\SimTreeNav)
    OutDir - Directory for logs/temp outputs (Default: ./out)
    Smoke - Run in validation mode (asserts files exist)
    Zip - Create a zip file of the bundle
    ZipPath - Path to the zip output (Default: .\out\SimTreeNav_bundle.zip)

.EXAMPLE
    ./build-deploy-bundle.ps1 -Smoke
    ./build-deploy-bundle.ps1 -Zip -Smoke
#>

param(
    [string]$RepoRoot = ".",
    [string]$DeployRoot = ".\out\staging_root\SimTreeNav",
    [string]$OutDir = "./out",
    [switch]$Smoke,
    [switch]$Zip,
    [string]$ZipPath = ".\out\SimTreeNav_bundle.zip"
)

$ErrorActionPreference = "Stop"

function Write-Log {
    param([string]$Message, [string]$Level="INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] [$Level] $Message"
    Write-Host $logMsg
    if ($global:LogFile) { Add-Content -Path $global:LogFile -Value $logMsg }
}

try {
    # Resolve Paths (AbsolutePath Fix)
    # Using [System.IO.Path]::GetFullPath ensures clean absolute paths without unintended concatenation
    $currentLoc = Get-Location
    $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $currentLoc $RepoRoot))
    $DeployRoot = [System.IO.Path]::GetFullPath((Join-Path $currentLoc $DeployRoot))
    $OutDir = [System.IO.Path]::GetFullPath((Join-Path $currentLoc $OutDir))
    
    # Ensure DeployRoot parent exists if needed, then create DeployRoot
    if (-not (Test-Path $DeployRoot)) { New-Item -Path $DeployRoot -ItemType Directory -Force | Out-Null }
    
    # Setup Logging
    $logDir = Join-Path $DeployRoot "out\logs"
    if (-not (Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }
    $global:LogFile = Join-Path $logDir "build-deploy-bundle.log"
    
    Write-Log "Starting Build-Deploy-Bundle..."
    Write-Log "Source: $RepoRoot"
    Write-Log "Destination: $DeployRoot"

    # 1. Structure Creation
    $folders = @(
        "dashboard",
        "out\html", "out\json", "out\zips", "out\logs", "out\reports",
        "config",
        "scripts\ops",
        "scripts\lib",
        "docs"
    )
    foreach ($f in $folders) {
        $p = Join-Path $DeployRoot $f
        if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null }
    }

    # 2. File Copying (Allowlist)
    $copyList = @(
        # Scripts
        @{ Src="scripts/ops/*.ps1"; Dest="scripts/ops" },
        @{ Src="scripts/lib/*.ps1"; Dest="scripts/lib" }, 
        
        # Config
        @{ Src="config/production.template.json"; Dest="config/production.template.json" },
        
        # Docs
        @{ Src="docs/PRODUCTION_KICKOFF_CHECKLIST.md"; Dest="docs" },
        @{ Src="docs/TASK_SCHEDULER_JOBS.md"; Dest="docs" },
        @{ Src="docs/PRODUCTION_DEPLOYMENT_PLAN.md"; Dest="docs" },
        @{ Src="docs/PRODUCTION_RUNBOOK.md"; Dest="docs" },
        @{ Src="docs/SECURITY_AND_CREDENTIALS.md"; Dest="docs" },
        @{ Src="docs/UAT_PLAN_AND_SURVEY.md"; Dest="docs" },
        @{ Src="docs/UAT_FEEDBACK_SUMMARY.md"; Dest="docs" },
        @{ Src="docs/GO_LIVE_COMMANDS.md"; Dest="docs" },
        @{ Src="docs/IT_SERVER_RUN_SCRIPTED.md"; Dest="docs" },
        @{ Src="docs/PRODUCTION_SERVER_EVIDENCE.md"; Dest="docs" },
        @{ Src="docs/GO_NO_GO_GATE.md"; Dest="docs" },
        @{ Src="docs/IT_HANDOFF_MESSAGE.md"; Dest="docs" },
        @{ Src="docs/PRODUCTION_REHEARSAL_REPORT.md"; Dest="docs" }
    )

    $manifest = @()

    foreach ($item in $copyList) {
        $srcPath = Join-Path $RepoRoot $item.Src
        $destPath = Join-Path $DeployRoot $item.Dest
        
        if ($item.Src.Contains("*")) {
           $files = Get-ChildItem -Path $srcPath -ErrorAction SilentlyContinue
           if ($files) {
               Copy-Item -Path $srcPath -Destination $destPath -Force
               foreach ($f in $files) {
                   $manifest += "UserFile|$($f.Name)|$(Get-Date)"
                   Write-Log "Copied: $($f.Name)"
               }
           } else {
               # Write-Log "No files found for pattern: $($item.Src)" "WARNING"
           }
        } else {
            if (Test-Path $srcPath) {
                Copy-Item -Path $srcPath -Destination $destPath -Force
                $fname = Split-Path $srcPath -Leaf
                $manifest += "UserFile|$fname|$(Get-Date)"
                Write-Log "Copied: $fname"
            }
        }
    }

    # 3. Manifest Generation
    $manifestPath = Join-Path $DeployRoot "bundle-manifest.txt"
    $manifest | Sort-Object | Set-Content -Path $manifestPath
    Write-Log "Manifest generated at $manifestPath"

    # 4. Zip Creation (Optional)
    if ($Zip) {
        $ZipPath = [System.IO.Path]::GetFullPath((Join-Path $currentLoc $ZipPath))
        # Ensure parent of zip exists
        $zipParent = Split-Path $ZipPath
        if (-not (Test-Path $zipParent)) { New-Item -Path $zipParent -ItemType Directory -Force | Out-Null }
        if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

        Write-Log "Creating Zip: $ZipPath"
        Compress-Archive -Path "$DeployRoot\*" -DestinationPath $ZipPath -Force
        
        $hashObj = Get-FileHash -Path $ZipPath -Algorithm SHA256
        $hashStr = "$($hashObj.Algorithm) Hash: $($hashObj.Hash)"
        Write-Log $hashStr
        
        # Save hash for easy reference
        $hashPath = Join-Path $logDir "bundle-hash.txt"
        Set-Content -Path $hashPath -Value $hashStr
    }

    # 5. Smoke Test Mode
    if ($Smoke) {
        Write-Log "Performing Smoke Test Validation..."
        
        # Check Critical Files
        $critFiles = @(
            "scripts\ops\install-scheduled-tasks.ps1",
            "scripts\ops\validate-environment.ps1",
            "config\production.template.json"
        )
        
        foreach ($c in $critFiles) {
            $cp = Join-Path $DeployRoot $c
            if (-not (Test-Path $cp)) {
                throw "Smoke validation failed. Missing: $c"
            }
        }
        
        if (-not (Test-Path $manifestPath)) { throw "Missing bundle manifest" }
        
        if ($Zip) {
             if (-not (Test-Path $ZipPath)) { throw "Zip file missing." }
        }

        Write-Log "Smoke Test Passed."
    }

    Write-Log "Build Complete."
    exit 0

} catch {
    Write-Log "Build FAILED: $_" "ERROR"
    exit 1
}
