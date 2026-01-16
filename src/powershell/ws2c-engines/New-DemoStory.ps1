<#
.SYNOPSIS
    Generates demo data for testing WS2C engines.
    
.DESCRIPTION
    Creates a complete set of demo data including nodes, timeline,
    and engine outputs with intentional compliance failures,
    similarity hits, and critical anomalies.
    
.PARAMETER OutDir
    Output directory for the demo files.
    
.PARAMETER Seed
    Optional random seed for deterministic output.
    
.EXAMPLE
    New-DemoStory -OutDir ./demo-data -Seed 42
#>

function New-DemoStory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutDir,
        
        [Parameter(Mandatory = $false)]
        [int]$Seed = 0
    )
    
    # Set random seed for determinism
    if ($Seed -ne 0) {
        $script:random = [System.Random]::new($Seed)
    } else {
        $script:random = [System.Random]::new()
    }
    
    # Ensure output directory exists
    if (-not (Test-Path $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
    
    # Generate nodes
    $nodes = Generate-DemoNodes
    
    # Generate timeline with intentional anomalies
    $timeline = Generate-DemoTimeline -Nodes $nodes
    
    # Write nodes.json
    $nodesPath = Join-Path $OutDir "nodes.json"
    $nodes | ConvertTo-Json -Depth 10 | Set-Content -Path $nodesPath -Encoding UTF8
    
    # Write timeline.json
    $timelinePath = Join-Path $OutDir "timeline.json"
    $timeline | ConvertTo-Json -Depth 10 | Set-Content -Path $timelinePath -Encoding UTF8
    
    # Generate template with stricter rules (to cause compliance failures)
    $templatePath = Join-Path $OutDir "template.json"
    $template = Generate-StrictTemplate
    $template | ConvertTo-Json -Depth 10 | Set-Content -Path $templatePath -Encoding UTF8
    
    # Run compliance check
    $compliancePath = Join-Path $OutDir "compliance.json"
    . "$PSScriptRoot\Test-TemplateCompliance.ps1"
    Test-TemplateCompliance -NodesPath $nodesPath -TemplatePath $templatePath -OutPath $compliancePath
    
    # Run similarity search (on first station)
    $similarPath = Join-Path $OutDir "similar.json"
    . "$PSScriptRoot\Find-Similar.ps1"
    $stationNode = $nodes | Where-Object { $_.nodeType -eq "Station" } | Select-Object -First 1
    if ($stationNode) {
        Find-Similar -NodesPath $nodesPath -NodeId $stationNode.id -Top 10 -OutPath $similarPath
    } else {
        # Fallback: create minimal similar.json
        @{
            sourceNodeId = "1"
            candidates = @()
            algorithm = @{ useShapeHash = $true; useAttributeHash = $true }
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $similarPath -Encoding UTF8
    }
    
    # Run anomaly detection
    $anomaliesPath = Join-Path $OutDir "anomalies.json"
    . "$PSScriptRoot\Detect-Anomalies.ps1"
    Detect-Anomalies -NodesPath $nodesPath -TimelinePath $timelinePath -OutPath $anomaliesPath
    
    # Create bundle with all sections
    $bundlePath = Join-Path $OutDir "bundle.json"
    . "$PSScriptRoot\Export-Bundle.ps1"
    Export-Bundle -NodesPath $nodesPath `
        -CompliancePath $compliancePath `
        -SimilarPath $similarPath `
        -AnomaliesPath $anomaliesPath `
        -TimelinePath $timelinePath `
        -OutPath $bundlePath
    
    return $true
}

function Generate-DemoNodes {
    $nodes = @()
    $nodeId = 1
    
    # Project root
    $nodes += @{
        id = "$nodeId"
        name = "DemoProject"
        nodeType = "Project"
        parentId = $null
        attributes = @{ version = "1.0" }
    }
    $projectId = "$nodeId"
    $nodeId++
    
    # Plant
    $nodes += @{
        id = "$nodeId"
        name = "Plant_Detroit"
        nodeType = "Plant"
        parentId = $projectId
        attributes = @{ location = "Detroit"; capacity = 1000 }
    }
    $plantId = "$nodeId"
    $nodeId++
    
    # Two lines
    foreach ($lineNum in 1..2) {
        $nodes += @{
            id = "$nodeId"
            name = "Line_00$lineNum"
            nodeType = "Line"
            parentId = $plantId
            attributes = @{ cycleTime = 120 }
        }
        $lineId = "$nodeId"
        $nodeId++
        
        # 3 stations per line (similar structure for similarity testing)
        foreach ($stationNum in 1..3) {
            $nodes += @{
                id = "$nodeId"
                name = "Station_$($lineNum)0$stationNum"
                nodeType = "Station"
                parentId = $lineId
                attributes = @{ cycleTime = 60; workers = 2 }
            }
            $stationId = "$nodeId"
            $nodeId++
            
            # Robot per station
            $nodes += @{
                id = "$nodeId"
                name = "Robot_$($lineNum)0$stationNum"
                nodeType = "Robot"
                parentId = $stationId
                attributes = @{ model = "KUKA KR-16"; payload = 16 }
            }
            $nodeId++
            
            # Device per station
            $nodes += @{
                id = "$nodeId"
                name = "Device_$($lineNum)0$stationNum"
                nodeType = "Device"
                parentId = $stationId
                attributes = @{ type = "Welder" }
            }
            $nodeId++
        }
    }
    
    # Intentional naming violation (for compliance failure)
    $nodes += @{
        id = "$nodeId"
        name = "invalid name with spaces!@#"
        nodeType = "Device"
        parentId = $nodes[3].id  # Under first station
        attributes = @{}
    }
    $nodeId++
    
    # Another naming violation
    $nodes += @{
        id = "$nodeId"
        name = "   "  # Whitespace only
        nodeType = "Tool"
        parentId = $nodes[3].id
        attributes = @{}
    }
    $nodeId++
    
    # Extra type not in template (for extras detection)
    $nodes += @{
        id = "$nodeId"
        name = "Conveyor_001"
        nodeType = "Conveyor"
        parentId = $plantId
        attributes = @{}
    }
    $nodeId++
    
    return $nodes
}

function Generate-DemoTimeline {
    param(
        [array]$Nodes
    )
    
    $timeline = @()
    $changeId = 1
    $baseDate = [DateTime]::new(2024, 1, 1, 9, 0, 0)
    
    # Normal changes
    $timeline += @{
        changeId = "c$changeId"
        timestamp = $baseDate.ToString("yyyy-MM-ddTHH:mm:ss")
        nodeId = $Nodes[0].id
        changeType = "modify"
        user = "user1"
        details = @{ field = "name"; oldValue = "Demo"; newValue = "DemoProject" }
    }
    $changeId++
    
    $timeline += @{
        changeId = "c$changeId"
        timestamp = $baseDate.AddHours(1).ToString("yyyy-MM-ddTHH:mm:ss")
        nodeId = $Nodes[3].id
        changeType = "add"
        user = "user1"
        details = @{}
    }
    $changeId++
    
    # Mass delete spike (5 deletes in 30 seconds - triggers anomaly)
    $deleteBase = $baseDate.AddDays(1).AddHours(9)
    for ($i = 0; $i -lt 6; $i++) {
        $timeline += @{
            changeId = "c$changeId"
            timestamp = $deleteBase.AddSeconds($i * 5).ToString("yyyy-MM-ddTHH:mm:ss")
            nodeId = "deleted_$($i + 100)"
            changeType = "delete"
            user = "user2"
            details = @{}
        }
        $changeId++
    }
    
    # Oscillation pattern (move node back and forth 4 times)
    $oscillateBase = $baseDate.AddDays(2).AddHours(10)
    $oscillateNodeId = $Nodes[4].id  # A robot
    $parentA = $Nodes[3].id  # Station 1
    $parentB = $Nodes[2].id  # Line
    
    for ($i = 0; $i -lt 4; $i++) {
        $oldP = if ($i % 2 -eq 0) { $parentA } else { $parentB }
        $newP = if ($i % 2 -eq 0) { $parentB } else { $parentA }
        
        $timeline += @{
            changeId = "c$changeId"
            timestamp = $oscillateBase.AddMinutes($i * 5).ToString("yyyy-MM-ddTHH:mm:ss")
            nodeId = $oscillateNodeId
            changeType = "move"
            user = "user1"
            details = @{ oldParentId = $oldP; newParentId = $newP }
        }
        $changeId++
    }
    
    # Transform outlier (extreme translation)
    $timeline += @{
        changeId = "c$changeId"
        timestamp = $baseDate.AddDays(3).AddHours(14).ToString("yyyy-MM-ddTHH:mm:ss")
        nodeId = $Nodes[4].id
        changeType = "transform"
        user = "user3"
        details = @{
            translation = @{ x = 99999; y = 88888; z = 77777 }
            rotation = @{ x = 0; y = 0; z = 0 }
        }
    }
    $changeId++
    
    # Sort by timestamp for determinism
    $timeline = $timeline | Sort-Object { $_.timestamp }, { $_.changeId }
    
    return $timeline
}

function Generate-StrictTemplate {
    return [ordered]@{
        name = "StrictDemoTemplate"
        version = "1.0"
        rootType = "Project"
        requiredTypes = @(
            @{ nodeType = "Plant"; min = 1; max = 1 }
            @{ nodeType = "Line"; min = 2; max = 2 }
            @{ nodeType = "Station"; min = 6; max = 6 }
            @{ nodeType = "Robot"; min = 6; max = 6 }
            @{ nodeType = "Device"; min = 6; max = 6 }
        )
        requiredLinks = @(
            @{ from = "Project"; to = "Plant" }
            @{ from = "Plant"; to = "Line" }
            @{ from = "Line"; to = "Station" }
            @{ from = "Station"; to = "Robot" }
            @{ from = "Station"; to = "Device" }
        )
        namingRules = @(
            @{ nodeType = "Station"; pattern = "^Station_\d{3}$" }
            @{ nodeType = "Robot"; pattern = "^Robot_\d{3}$" }
            @{ nodeType = "Device"; pattern = "^Device_\d{3}$" }
            @{ nodeType = "Line"; pattern = "^Line_\d{3}$" }
            @{ nodeType = "Plant"; pattern = "^Plant_\w+$" }
        )
        allowedExtras = $false  # Will flag Conveyor and Tool as extras
        driftRules = @()
    }
}

# Export function for module use
Export-ModuleMember -Function New-DemoStory -ErrorAction SilentlyContinue
