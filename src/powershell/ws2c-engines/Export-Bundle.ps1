<#
.SYNOPSIS
    Exports a complete WS2C bundle with all engine outputs.
    
.DESCRIPTION
    Creates a unified bundle JSON file that includes nodes, metadata,
    and optional compliance, similarity, and anomaly data.
    
.PARAMETER NodesPath
    Path to the nodes JSON file (required).
    
.PARAMETER CompliancePath
    Optional path to compliance results JSON.
    
.PARAMETER SimilarPath
    Optional path to similarity results JSON.
    
.PARAMETER AnomaliesPath
    Optional path to anomalies results JSON.
    
.PARAMETER TimelinePath
    Optional path to timeline JSON for metadata.
    
.PARAMETER OutPath
    Output path for the bundle JSON file.
    
.EXAMPLE
    Export-Bundle -NodesPath nodes.json -CompliancePath compliance.json -OutPath bundle.json
#>

function Export-Bundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodesPath,
        
        [Parameter(Mandatory = $false)]
        [string]$CompliancePath,
        
        [Parameter(Mandatory = $false)]
        [string]$SimilarPath,
        
        [Parameter(Mandatory = $false)]
        [string]$AnomaliesPath,
        
        [Parameter(Mandatory = $false)]
        [string]$TimelinePath,
        
        [Parameter(Mandatory = $true)]
        [string]$OutPath
    )
    
    # Guard: Check if nodes file exists
    if (-not (Test-Path $NodesPath)) {
        Write-Warning "Nodes file not found: $NodesPath"
        return $false
    }
    
    # Load nodes
    $nodes = Get-Content $NodesPath | ConvertFrom-Json
    
    # Build metadata
    $metadata = [ordered]@{
        version = "1.0.0"
        generatedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        generator = "WS2C-Engines"
        nodeCount = $nodes.Count
        sections = @()
    }
    
    # Initialize bundle
    $bundle = [ordered]@{
        metadata = $metadata
        nodes = $nodes
    }
    
    $metadata.sections += "nodes"
    
    # Add timeline if provided
    if ($TimelinePath -and (Test-Path $TimelinePath)) {
        $timeline = Get-Content $TimelinePath | ConvertFrom-Json
        $bundle["timeline"] = $timeline
        $metadata.sections += "timeline"
        $metadata["changeCount"] = $timeline.Count
    }
    
    # Add compliance if provided
    if ($CompliancePath -and (Test-Path $CompliancePath)) {
        $compliance = Get-Content $CompliancePath | ConvertFrom-Json
        $bundle["compliance"] = $compliance
        $metadata.sections += "compliance"
    }
    
    # Add similar if provided
    if ($SimilarPath -and (Test-Path $SimilarPath)) {
        $similar = Get-Content $SimilarPath | ConvertFrom-Json
        $bundle["similar"] = $similar
        $metadata.sections += "similar"
    }
    
    # Add anomalies if provided
    if ($AnomaliesPath -and (Test-Path $AnomaliesPath)) {
        $anomalies = Get-Content $AnomaliesPath | ConvertFrom-Json
        $bundle["anomalies"] = $anomalies
        $metadata.sections += "anomalies"
    }
    
    # Calculate summary statistics
    $summary = [ordered]@{
        totalNodes = $nodes.Count
        nodeTypes = @{}
    }
    
    foreach ($node in $nodes) {
        $nodeType = $node.nodeType
        if (-not $nodeType) {
            $nodeType = "Unknown"
        }
        if (-not $summary.nodeTypes.ContainsKey($nodeType)) {
            $summary.nodeTypes[$nodeType] = 0
        }
        $summary.nodeTypes[$nodeType]++
    }
    
    # Add engine summaries
    if ($bundle.ContainsKey("compliance")) {
        $summary["complianceScore"] = $bundle.compliance.score
        $summary["violations"] = $bundle.compliance.violations.Count
    }
    
    if ($bundle.ContainsKey("similar")) {
        $summary["similarCandidates"] = $bundle.similar.candidates.Count
    }
    
    if ($bundle.ContainsKey("anomalies")) {
        $summary["anomalyCount"] = $bundle.anomalies.anomalyCount
        $summary["criticalAnomalies"] = $bundle.anomalies.bySeverity.Critical
    }
    
    $bundle["summary"] = $summary
    
    # Ensure output directory exists
    $outDir = Split-Path $OutPath -Parent
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    
    # Write bundle
    $bundle | ConvertTo-Json -Depth 20 | Set-Content -Path $OutPath -Encoding UTF8
    
    return $true
}

# Export function for module use
Export-ModuleMember -Function Export-Bundle -ErrorAction SilentlyContinue
