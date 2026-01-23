<#
.SYNOPSIS
    RunManifest library helper functions.

.DESCRIPTION
    Manages the creation and updates of run-manifest.json.

.EXAMPLE
    Import-Module .\RunManifest.ps1
    New-RunManifest -OutDir ".\out" -SchemaVersion "1.0.0" -Source "Agent02"
#>

function New-RunManifest {
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutDir,

        [Parameter(Mandatory=$true)]
        [string]$SchemaVersion,

        [Parameter(Mandatory=$true)]
        [string]$Source
    )

    $jsonDir = Join-Path $OutDir "json"
    if (-not (Test-Path $jsonDir)) {
        New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null
    }

    $manifestPath = Join-Path $jsonDir "run-manifest.json"
    
    $manifest = @{
        schemaVersion = $SchemaVersion
        source        = $Source
        machineName   = $env:COMPUTERNAME
        user          = $env:USERNAME
        createdAt     = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        runId         = [Guid]::NewGuid().ToString()
        artifacts     = @()
    }

    $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding UTF8
    Write-Output $manifestPath
}

function Add-RunArtifact {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ManifestPath,

        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [string]$SchemaVersion,

        [Parameter(Mandatory=$true)]
        [ValidateSet("html","json","zip","log")]
        [string]$Kind
    )

    if (-not (Test-Path $ManifestPath)) {
        Throw "Manifest not found at $ManifestPath"
    }

    if (-not (Test-Path $Path)) {
        Throw "Artifact file not found at $Path"
    }

    $fileInfo = Get-Item $Path
    $hash = Get-FileHash -Path $Path -Algorithm SHA256
    
    # Calculate relative path from manifest directory (or output root)
    # Assuming ManifestPath is inside OutDir/json/run-manifest.json
    # and we want relative path from OutDir.
    # But user req says "relativePath". simpler to make it relative to the OutDir root.
    # Let's assume standard structure: OutDir/json/run-manifest.json.
    # We try to find relative path from the grand-parent of manifest (the OutDir).
    
    $manifestDir = Split-Path $ManifestPath
    $outDir = Split-Path $manifestDir # Go up one level from 'json'
    
    # If path is not under outDir, just use name or make it relative if possible
    # Use Resolve-Path to handle potential relative paths provided in arguments
    $absPath = $fileInfo.FullName
    $absOutDir = (Resolve-Path $outDir).Path
    
    if ($absPath.StartsWith($absOutDir)) {
         $relativePath = $absPath.Substring($absOutDir.Length + 1).Replace("\", "/")
    } else {
        $relativePath = $fileInfo.Name
    }

    $artifact = @{
        relativePath  = $relativePath
        sha256        = $hash.Hash
        bytes         = $fileInfo.Length
        modifiedAt    = $fileInfo.LastWriteTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
        schemaVersion = $SchemaVersion
        kind          = $Kind
    }

    $content = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
    
    # Add to artifacts array (convert to arraylist to easy add, or just +=)
    if ($null -eq $content.artifacts) {
        $content.artifacts = @()
    }
    
    $content.artifacts += $artifact
    
    # Sort artifacts by relativePath for deterministic output
    $content.artifacts = $content.artifacts | Sort-Object relativePath

    $content | ConvertTo-Json -Depth 10 | Set-Content -Path $ManifestPath -Encoding UTF8
}

function Finalize-RunManifest {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ManifestPath
    )
    # Optional: Stamp totals or status. For now, just ensuring it exists is enough.
    if (-not (Test-Path $ManifestPath)) {
        Throw "Manifest not found at $ManifestPath"
    }
    
    # We could add a 'completedAt' timestamp here
    $content = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json
    $content | Add-Member -MemberType NoteProperty -Name "completedAt" -Value ((Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")) -Force
    
    $content | ConvertTo-Json -Depth 10 | Set-Content -Path $ManifestPath -Encoding UTF8
}


