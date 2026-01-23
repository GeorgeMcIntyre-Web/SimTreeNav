<#
.SYNOPSIS
    STUB: RunManifest library helper functions.
    NOTE: This is a Phase 2 STUB. It currently does nothing but define empty functions.

.DESCRIPTION
    Intended to manage the creation and updates of run-manifest.json.

.EXAMPLE
    Import-Module .\RunManifest.ps1
    New-RunManifest -RunId (New-Guid)
#>

function New-RunManifest {
    param(
        [Parameter(Mandatory=$true)]
        [Guid]$RunId,

        [Parameter(Mandatory=$true)]
        [string]$Trigger
    )
    Write-Warning "New-RunManifest: Not implemented (Stub)"
}

function Add-RunArtifact {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ManifestPath,

        [Parameter(Mandatory=$true)]
        [string]$ArtifactPath,

        [Parameter(Mandatory=$true)]
        [string]$Type
    )
    Write-Warning "Add-RunArtifact: Not implemented (Stub)"
}

function Close-RunManifest {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ManifestPath,

        [string]$Status = "SUCCESS",

        [int]$ExitCode = 0
    )
    Write-Warning "Close-RunManifest: Not implemented (Stub)"
}

Export-ModuleMember -Function New-RunManifest, Add-RunArtifact, Close-RunManifest
