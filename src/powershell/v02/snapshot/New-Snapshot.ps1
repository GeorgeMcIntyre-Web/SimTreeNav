# New-Snapshot.ps1
# Generates a deterministic snapshot of the tree structure
# Output: nodes.json + meta.json in timestamped directory

<#
.SYNOPSIS
    Creates a snapshot of the current tree state.

.DESCRIPTION
    Queries the database and generates a deterministic snapshot containing:
    - nodes.json: All nodes in canonical format
    - meta.json: Metadata about the snapshot (db, schema, timestamp, etc.)
    - edges.json: Optional edge list (if -IncludeEdges)

.EXAMPLE
    .\New-Snapshot.ps1 -TNSName "DB01" -Schema "DESIGN12" -ProjectId "18140190" -Label "manual"

.EXAMPLE
    .\New-Snapshot.ps1 -TNSName "DB01" -Schema "DESIGN12" -ProjectId "18140190" -OutDir "./snapshots" -Label "hourly"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TNSName,
    
    [Parameter(Mandatory = $true)]
    [string]$Schema,
    
    [Parameter(Mandatory = $true)]
    [string]$ProjectId,
    
    [string]$ProjectName = '',
    
    [string]$OutDir = './snapshots',
    
    [string]$Label = 'snapshot',
    
    [switch]$IncludeEdges,
    
    [switch]$Pretty,
    
    [string]$ConfigFile = ''
)

$ErrorActionPreference = 'Stop'

# Import modules
$scriptRoot = $PSScriptRoot
$nodeContractPath = Join-Path $scriptRoot '..\core\NodeContract.ps1'
$credManagerPath = Join-Path $scriptRoot '..\..\utilities\CredentialManager.ps1'

if (Test-Path $nodeContractPath) {
    . $nodeContractPath
} else {
    Write-Error "NodeContract.ps1 not found at: $nodeContractPath"
    return
}

if (Test-Path $credManagerPath) {
    Import-Module $credManagerPath -Force
}

# Load configuration
function Get-SnapshotConfig {
    param([string]$ConfigPath)
    
    $defaultConfig = @{
        deterministic = $true
        prettyPrint = $true
        includeEdges = $false
    }
    
    if (-not $ConfigPath) {
        $ConfigPath = Join-Path $scriptRoot '..\..\..\..\config\simtreenav.config.json'
    }
    
    if (Test-Path $ConfigPath) {
        try {
            $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
            return $config.snapshots
        } catch {
            Write-Warning "Failed to load config: $_"
        }
    }
    
    return [PSCustomObject]$defaultConfig
}

# Generate timestamp for folder name (deterministic format)
function Get-SnapshotTimestamp {
    Get-Date -Format 'yyyyMMdd_HHmmss'
}

# Execute extraction query and return pipe-delimited lines
function Get-TreeData {
    param(
        [string]$TNSName,
        [string]$Schema,
        [string]$ProjectId
    )
    
    Write-Host "  Extracting tree data from $Schema..." -ForegroundColor Cyan
    
    # Build extraction query (simplified version for snapshot)
    $sqlQuery = @"
SET PAGESIZE 50000
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

-- Root node
SELECT '0|0|$ProjectId|' || NVL(c.CAPTION_S_, 'Project') || '|' || NVL(c.CAPTION_S_, 'Project') || '|' || NVL(c.EXTERNALID_S_, '') || '|0|' || NVL(cd.NAME, 'class PmProject') || '|' || NVL(cd.NICE_NAME, 'Project') || '|' || TO_CHAR(NVL(cd.TYPE_ID, 0))
FROM $Schema.COLLECTION_ c
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE c.OBJECT_ID = $ProjectId;

-- Level 1: Direct children
SELECT '1|$ProjectId|' || r.OBJECT_ID || '|' || NVL(c.CAPTION_S_, 'Unnamed') || '|' || NVL(c.CAPTION_S_, 'Unnamed') || '|' || NVL(c.EXTERNALID_S_, '') || '|' || TO_CHAR(NVL(r.SEQ_NUMBER, 0)) || '|' || NVL(cd.NAME, 'class PmNode') || '|' || NVL(cd.NICE_NAME, 'Unknown') || '|' || TO_CHAR(NVL(cd.TYPE_ID, 0))
FROM $Schema.REL_COMMON r
LEFT JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE r.FORWARD_OBJECT_ID = $ProjectId
ORDER BY r.SEQ_NUMBER, c.OBJECT_ID;

-- Level 2+: Hierarchical query
SELECT LEVEL || '|' || PRIOR c.OBJECT_ID || '|' || c.OBJECT_ID || '|' || NVL(c.CAPTION_S_, 'Unnamed') || '|' || NVL(c.CAPTION_S_, 'Unnamed') || '|' || NVL(c.EXTERNALID_S_, '') || '|' || TO_CHAR(NVL(r.SEQ_NUMBER, 0)) || '|' || NVL(cd.NAME, 'class PmNode') || '|' || NVL(cd.NICE_NAME, 'Unknown') || '|' || TO_CHAR(NVL(cd.TYPE_ID, 0))
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
START WITH r.FORWARD_OBJECT_ID = $ProjectId
CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
ORDER SIBLINGS BY NVL(c.MODIFICATIONDATE_DA_, TO_DATE('1900-01-01', 'YYYY-MM-DD')), c.OBJECT_ID;

-- Study nodes (specialized tables)
SELECT '999|' || r.FORWARD_OBJECT_ID || '|' || r.OBJECT_ID || '|' || NVL(rs.NAME_S_, 'Unnamed') || '|' || NVL(rs.NAME_S_, 'Unnamed') || '|' || NVL(rs.EXTERNALID_S_, '') || '|' || TO_CHAR(NVL(r.SEQ_NUMBER, 0)) || '|' || NVL(cd.NAME, 'class RobcadStudy') || '|' || NVL(cd.NICE_NAME, 'RobcadStudy') || '|' || TO_CHAR(NVL(cd.TYPE_ID, 0))
FROM $Schema.REL_COMMON r
INNER JOIN $Schema.ROBCADSTUDY_ rs ON r.OBJECT_ID = rs.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
WHERE r.FORWARD_OBJECT_ID IN (
    SELECT c.OBJECT_ID FROM $Schema.COLLECTION_ c
    INNER JOIN $Schema.REL_COMMON r2 ON c.OBJECT_ID = r2.OBJECT_ID
    START WITH r2.FORWARD_OBJECT_ID = $ProjectId
    CONNECT BY NOCYCLE PRIOR r2.OBJECT_ID = r2.FORWARD_OBJECT_ID
);

-- ToolPrototype nodes
SELECT '999|' || r.FORWARD_OBJECT_ID || '|' || tp.OBJECT_ID || '|' || NVL(tp.CAPTION_S_, NVL(tp.NAME_S_, 'Unnamed Tool')) || '|' || NVL(tp.NAME_S_, 'Unnamed') || '|' || NVL(tp.EXTERNALID_S_, '') || '|' || TO_CHAR(NVL(r.SEQ_NUMBER, 0)) || '|' || NVL(cd.NAME, 'class ToolPrototype') || '|' || NVL(cd.NICE_NAME, 'ToolPrototype') || '|' || TO_CHAR(NVL(cd.TYPE_ID, 0))
FROM $Schema.TOOLPROTOTYPE_ tp
INNER JOIN $Schema.REL_COMMON r ON tp.OBJECT_ID = r.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON tp.CLASS_ID = cd.TYPE_ID
WHERE r.FORWARD_OBJECT_ID IN (
    SELECT c.OBJECT_ID FROM $Schema.COLLECTION_ c
    INNER JOIN $Schema.REL_COMMON r2 ON c.OBJECT_ID = r2.OBJECT_ID
    START WITH r2.FORWARD_OBJECT_ID = $ProjectId
    CONNECT BY NOCYCLE PRIOR r2.OBJECT_ID = r2.FORWARD_OBJECT_ID
);

-- Resource nodes
SELECT '999|' || r.FORWARD_OBJECT_ID || '|' || res.OBJECT_ID || '|' || NVL(res.CAPTION_S_, NVL(res.NAME_S_, 'Unnamed Resource')) || '|' || NVL(res.NAME_S_, 'Unnamed') || '|' || NVL(res.EXTERNALID_S_, '') || '|' || TO_CHAR(NVL(r.SEQ_NUMBER, 0)) || '|' || NVL(cd.NAME, 'class Resource') || '|' || NVL(cd.NICE_NAME, 'Resource') || '|' || TO_CHAR(NVL(cd.TYPE_ID, 0))
FROM $Schema.RESOURCE_ res
INNER JOIN $Schema.REL_COMMON r ON res.OBJECT_ID = r.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON res.CLASS_ID = cd.TYPE_ID
WHERE r.FORWARD_OBJECT_ID IN (
    SELECT c.OBJECT_ID FROM $Schema.COLLECTION_ c
    INNER JOIN $Schema.REL_COMMON r2 ON c.OBJECT_ID = r2.OBJECT_ID
    START WITH r2.FORWARD_OBJECT_ID = $ProjectId
    CONNECT BY NOCYCLE PRIOR r2.OBJECT_ID = r2.FORWARD_OBJECT_ID
);

EXIT;
"@
    
    # Write SQL to temp file
    $sqlFile = Join-Path $env:TEMP "snapshot_query_$(Get-Date -Format 'yyyyMMddHHmmss').sql"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($sqlFile, $sqlQuery, $utf8NoBom)
    
    # Execute query
    $env:NLS_LANG = "AMERICAN_AMERICA.UTF8"
    
    try {
        $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
    } catch {
        Write-Warning "Failed to get credentials, using default"
        $connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
    }
    
    $result = sqlplus -S $connectionString "@$sqlFile" 2>&1
    
    # Cleanup
    Remove-Item $sqlFile -ErrorAction SilentlyContinue
    
    # Parse output - filter valid lines
    $lines = @()
    foreach ($line in $result) {
        $trimmed = $line.ToString().Trim()
        if ($trimmed -match '^\d+\|\d+\|' -and $trimmed -notmatch 'ERROR|SP2') {
            $lines += $trimmed
        }
    }
    
    Write-Host "    Extracted $($lines.Count) nodes" -ForegroundColor Gray
    return $lines
}

# Main snapshot generation
function New-TreeSnapshot {
    param(
        [string]$TNSName,
        [string]$Schema,
        [string]$ProjectId,
        [string]$ProjectName,
        [string]$OutDir,
        [string]$Label,
        [bool]$IncludeEdges,
        [bool]$Pretty
    )
    
    $timestamp = Get-SnapshotTimestamp
    $snapshotDir = Join-Path $OutDir "${timestamp}_${Label}"
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  SimTreeNav Snapshot Generator" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Target: $Schema / $ProjectId" -ForegroundColor White
    Write-Host "  Output: $snapshotDir" -ForegroundColor White
    Write-Host ""
    
    # Create output directory
    if (-not (Test-Path $snapshotDir)) {
        New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
    }
    
    # Extract tree data
    $lines = Get-TreeData -TNSName $TNSName -Schema $Schema -ProjectId $ProjectId
    
    if ($lines.Count -eq 0) {
        Write-Error "No data extracted from database"
        return $null
    }
    
    # Convert to canonical nodes
    Write-Host "  Converting to canonical format..." -ForegroundColor Cyan
    $nodes = @()
    $edges = @()
    
    foreach ($line in $lines) {
        $node = ConvertFrom-PipeDelimited -Line $line -Schema $Schema
        if ($node) {
            $nodes += $node
            
            # Track edges if requested
            if ($IncludeEdges -and $node.parentId) {
                $edges += [PSCustomObject]@{
                    source = $node.parentId
                    target = $node.nodeId
                    type   = 'parent-child'
                }
            }
        }
    }
    
    # Compute paths
    Write-Host "  Computing node paths..." -ForegroundColor Cyan
    $nodes = Compute-NodePaths -Nodes $nodes
    
    # Sort nodes by ID for deterministic output
    $sortedNodes = $nodes | Sort-Object { [long]$_.nodeId }
    
    # Generate metadata
    $meta = [PSCustomObject]@{
        version       = '0.2.0'
        timestamp     = (Get-Date).ToUniversalTime().ToString('o')
        label         = $Label
        source        = [PSCustomObject]@{
            tnsName   = $TNSName
            schema    = $Schema
            projectId = $ProjectId
            projectName = $ProjectName
        }
        stats         = [PSCustomObject]@{
            totalNodes = $nodes.Count
            nodeTypes  = ($nodes | Group-Object nodeType | ForEach-Object {
                [PSCustomObject]@{ type = $_.Name; count = $_.Count }
            })
        }
        queryVersion  = '1.0'
        deterministic = $true
    }
    
    # Write files
    Write-Host "  Writing snapshot files..." -ForegroundColor Cyan
    
    $jsonDepth = 10
    $nodesJson = if ($Pretty) {
        $sortedNodes | ConvertTo-Json -Depth $jsonDepth
    } else {
        $sortedNodes | ConvertTo-Json -Depth $jsonDepth -Compress
    }
    
    $metaJson = if ($Pretty) {
        $meta | ConvertTo-Json -Depth $jsonDepth
    } else {
        $meta | ConvertTo-Json -Depth $jsonDepth -Compress
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $snapshotDir 'nodes.json'), $nodesJson, $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $snapshotDir 'meta.json'), $metaJson, $utf8NoBom)
    
    if ($IncludeEdges) {
        $sortedEdges = $edges | Sort-Object source, target
        $edgesJson = if ($Pretty) {
            $sortedEdges | ConvertTo-Json -Depth $jsonDepth
        } else {
            $sortedEdges | ConvertTo-Json -Depth $jsonDepth -Compress
        }
        [System.IO.File]::WriteAllText((Join-Path $snapshotDir 'edges.json'), $edgesJson, $utf8NoBom)
    }
    
    Write-Host ""
    Write-Host "  Snapshot complete!" -ForegroundColor Green
    Write-Host "    Nodes: $($nodes.Count)" -ForegroundColor Gray
    Write-Host "    Path:  $snapshotDir" -ForegroundColor Gray
    Write-Host ""
    
    return [PSCustomObject]@{
        Path       = $snapshotDir
        Timestamp  = $timestamp
        NodeCount  = $nodes.Count
        Meta       = $meta
    }
}

# Load config
$config = Get-SnapshotConfig -ConfigPath $ConfigFile

# Run snapshot
$prettyPrint = if ($PSBoundParameters.ContainsKey('Pretty')) { $Pretty } else { $config.prettyPrint }
$includeEdgesFlag = if ($PSBoundParameters.ContainsKey('IncludeEdges')) { $IncludeEdges } else { $config.includeEdges }

$result = New-TreeSnapshot `
    -TNSName $TNSName `
    -Schema $Schema `
    -ProjectId $ProjectId `
    -ProjectName $ProjectName `
    -OutDir $OutDir `
    -Label $Label `
    -IncludeEdges $includeEdgesFlag `
    -Pretty $prettyPrint

# Return result for pipeline
$result
