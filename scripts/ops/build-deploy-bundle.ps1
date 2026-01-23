<#
.SYNOPSIS
    Builds the production deployment bundle for SimTreeNav.
    Copies required artifacts to a deployment root and generates a manifest.

.PARAMETER Param
    RepoRoot - Source repository logic (Default: current location)
    DeployRoot - Destination for the bundle (Default: .\out\staging_root\SimTreeNav)
    OutDir - Directory for logs/temp outputs (Default: ./out)
    Smoke - Run in validation mode (asserts files exist)

.EXAMPLE
    ./build-deploy-bundle.ps1 -Smoke
#>

param(
    [string]$RepoRoot = ".",
    [string]$DeployRoot = ".\out\staging_root\SimTreeNav",
    [string]$OutDir = "./out",
    [switch]$Smoke
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
    # Resolve Paths
    $RepoRoot = Resolve-Path $RepoRoot
    if (-not (Test-Path $DeployRoot)) { New-Item -Path $DeployRoot -ItemType Directory -Force | Out-Null }
    $DeployRoot = Resolve-Path $DeployRoot
    
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
        @{ Src="scripts/lib/*.ps1"; Dest="scripts/lib" }, # Assuming lib exists, handle if empty
        
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
        @{ Src="docs/GO_LIVE_COMMANDS.md"; Dest="docs" }
    )

    $manifest = @()

    foreach ($item in $copyList) {
        $srcPath = Join-Path $RepoRoot $item.Src
        $destPath = Join-Path $DeployRoot $item.Dest
        
        # Handle wildcard checks manually to avoid errors if no files match
        if ($item.Src.Contains("*")) {
           $files = Get-ChildItem -Path $srcPath -ErrorAction SilentlyContinue
           if ($files) {
               Copy-Item -Path $srcPath -Destination $destPath -Force
               foreach ($f in $files) {
                   $manifest += "UserFile|$($f.Name)|$(Get-Date)"
                   Write-Log "Copied: $($f.Name)"
               }
           } else {
               Write-Log "No files found for pattern: $($item.Src)" "WARNING"
           }
        } else {
            if (Test-Path $srcPath) {
                Copy-Item -Path $srcPath -Destination $destPath -Force
                $fname = Split-Path $srcPath -Leaf
                $manifest += "UserFile|$fname|$(Get-Date)"
                Write-Log "Copied: $fname"
            } else {
                # Optional files allowed to be missing?
                if ($item.Src -match "GO_LIVE_COMMANDS") {
                    # Might not exist yet
                } else {
                   # Write-Log "Source missing: $srcPath" "WARNING"
                }
            }
        }
    }

    # 3. Manifest Generation
    $manifestPath = Join-Path $DeployRoot "bundle-manifest.txt"
    $manifest | Sort-Object | Set-Content -Path $manifestPath
    Write-Log "Manifest generated at $manifestPath"

    # 4. Smoke Test Mode
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
        
        Write-Log "Smoke Test Passed."
    }

    Write-Log "Build Complete."
    exit 0

} catch {
    Write-Log "Build FAILED: $_" "ERROR"
    exit 1
}
