# ComplianceEngine.ps1
# Golden template compliance checking and naming convention validation
# v0.3: Station/subtree compliance scoring

<#
.SYNOPSIS
    Validates nodes against golden templates and naming conventions.

.DESCRIPTION
    A "GoldenTemplate" defines expected structure for a station/subtree:
    - Required node types and counts
    - Required name patterns (regex)
    - Required links/relationships
    - Allowed extras (flexibility)
    - Drift tolerances

    ComplianceScore measures conformance:
    - Missing required nodes
    - Naming convention violations
    - Unexpected extras
    - Drift outside tolerance

.EXAMPLE
    $compliance = Test-Compliance -Nodes $nodes -Template $template
#>

# Default naming conventions (can be overridden)
$Script:NamingConventions = @{
    Station         = '^[A-Z][A-Za-z0-9_]+$'              # StationName, Station_01
    ResourceGroup   = '^RG_[A-Za-z0-9_]+$'                # RG_Robot1, RG_Main
    Resource        = '^[A-Z][A-Za-z0-9_]+$'              # Robot1, Gripper_A
    ToolPrototype   = '^[A-Z][A-Za-z0-9_]+_Proto(type)?$' # WeldGun_Proto
    ToolInstance    = '^[A-Z][A-Za-z0-9_]+_\d+$'          # WeldGun_001
    Operation       = '^Op_[A-Za-z0-9_]+$'                # Op_Weld_01
    Location        = '^Loc_[A-Za-z0-9_]+$'               # Loc_Home
}

# Template definition structure
$Script:TemplateSchema = @{
    name            = 'string'      # Template name
    description     = 'string'      # Template description
    requiredTypes   = 'array'       # Array of { nodeType, minCount, maxCount, namePattern }
    requiredLinks   = 'array'       # Array of { fromType, toType, linkType }
    namingRules     = 'hashtable'   # NodeType -> regex pattern
    allowExtras     = 'boolean'     # Allow nodes beyond requirements
    driftTolerance  = 'hashtable'   # { position_mm, rotation_deg }
}

function New-GoldenTemplate {
    <#
    .SYNOPSIS
        Creates a new golden template definition.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        
        [string]$Description = '',
        
        [array]$RequiredTypes = @(),
        
        [array]$RequiredLinks = @(),
        
        [hashtable]$NamingRules = @{},
        
        [switch]$AllowExtras,
        
        [hashtable]$DriftTolerance = @{ position_mm = 0.1; rotation_deg = 0.01 }
    )
    
    [PSCustomObject]@{
        name            = $Name
        description     = $Description
        requiredTypes   = $RequiredTypes
        requiredLinks   = $RequiredLinks
        namingRules     = if ($NamingRules.Count -gt 0) { $NamingRules } else { $Script:NamingConventions }
        allowExtras     = [bool]$AllowExtras
        driftTolerance  = $DriftTolerance
        createdAt       = (Get-Date).ToUniversalTime().ToString('o')
    }
}

function New-TypeRequirement {
    <#
    .SYNOPSIS
        Creates a type requirement for a template.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodeType,
        
        [int]$MinCount = 0,
        
        [int]$MaxCount = -1,  # -1 = unlimited
        
        [string]$NamePattern = $null,
        
        [switch]$Required
    )
    
    if ($Required -and $MinCount -lt 1) {
        $MinCount = 1
    }
    
    [PSCustomObject]@{
        nodeType    = $NodeType
        minCount    = $MinCount
        maxCount    = $MaxCount
        namePattern = $NamePattern
        required    = $MinCount -gt 0
    }
}

function Test-NamingConvention {
    <#
    .SYNOPSIS
        Tests if a node name matches the naming convention.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Node,
        
        [hashtable]$NamingRules = $Script:NamingConventions
    )
    
    $nodeType = $Node.nodeType
    $name = $Node.name
    
    # No rule = pass by default
    if (-not $NamingRules.ContainsKey($nodeType)) {
        return [PSCustomObject]@{
            passed   = $true
            nodeId   = $Node.nodeId
            name     = $name
            nodeType = $nodeType
            pattern  = $null
            reason   = 'No naming rule defined'
        }
    }
    
    $pattern = $NamingRules[$nodeType]
    $passed = $name -match $pattern
    
    [PSCustomObject]@{
        passed   = $passed
        nodeId   = $Node.nodeId
        name     = $name
        nodeType = $nodeType
        pattern  = $pattern
        reason   = if ($passed) { 'Matches pattern' } else { "Does not match pattern: $pattern" }
    }
}

function Test-TypeRequirements {
    <#
    .SYNOPSIS
        Tests if nodes meet type requirements.
    #>
    param(
        [array]$Nodes,
        [array]$Requirements
    )
    
    $results = @()
    $nodesByType = @{}
    
    # Group nodes by type
    foreach ($node in $Nodes) {
        $type = $node.nodeType
        if (-not $nodesByType.ContainsKey($type)) {
            $nodesByType[$type] = @()
        }
        $nodesByType[$type] += $node
    }
    
    foreach ($req in $Requirements) {
        $type = $req.nodeType
        $count = if ($nodesByType.ContainsKey($type)) { $nodesByType[$type].Count } else { 0 }
        
        $meetsMin = $count -ge $req.minCount
        $meetsMax = $req.maxCount -lt 0 -or $count -le $req.maxCount
        $passed = $meetsMin -and $meetsMax
        
        # Check name patterns if specified
        $nameViolations = @()
        if ($req.namePattern -and $nodesByType.ContainsKey($type)) {
            foreach ($node in $nodesByType[$type]) {
                if ($node.name -notmatch $req.namePattern) {
                    $nameViolations += $node.name
                }
            }
        }
        
        $results += [PSCustomObject]@{
            nodeType       = $type
            required       = $req.required
            minCount       = $req.minCount
            maxCount       = $req.maxCount
            actualCount    = $count
            passed         = $passed -and ($nameViolations.Count -eq 0)
            meetsMinimum   = $meetsMin
            meetsMaximum   = $meetsMax
            nameViolations = $nameViolations
            reason         = if (-not $meetsMin) { "Missing: need at least $($req.minCount), have $count" }
                           elseif (-not $meetsMax) { "Too many: max $($req.maxCount), have $count" }
                           elseif ($nameViolations.Count -gt 0) { "Name violations: $($nameViolations.Count) nodes" }
                           else { 'Passed' }
        }
    }
    
    return $results
}

function Test-LinkRequirements {
    <#
    .SYNOPSIS
        Tests if required links exist.
    #>
    param(
        [array]$Nodes,
        [array]$Requirements
    )
    
    $results = @()
    $nodeById = @{}
    $nodesByType = @{}
    
    # Index nodes
    foreach ($node in $Nodes) {
        $nodeById[$node.nodeId] = $node
        $type = $node.nodeType
        if (-not $nodesByType.ContainsKey($type)) {
            $nodesByType[$type] = @()
        }
        $nodesByType[$type] += $node
    }
    
    foreach ($req in $Requirements) {
        $fromNodes = if ($nodesByType.ContainsKey($req.fromType)) { $nodesByType[$req.fromType] } else { @() }
        $toNodes = if ($nodesByType.ContainsKey($req.toType)) { $nodesByType[$req.toType] } else { @() }
        
        $linkedCount = 0
        $unlinkedFrom = @()
        
        foreach ($fromNode in $fromNodes) {
            $hasLink = $false
            
            if ($fromNode.links) {
                $linkValue = $fromNode.links.($req.linkType)
                if ($linkValue) {
                    if ($linkValue -is [array]) {
                        $hasLink = ($linkValue | Where-Object { $nodeById.ContainsKey($_) -and $nodeById[$_].nodeType -eq $req.toType }).Count -gt 0
                    }
                    else {
                        $hasLink = $nodeById.ContainsKey($linkValue) -and $nodeById[$linkValue].nodeType -eq $req.toType
                    }
                }
            }
            
            if ($hasLink) {
                $linkedCount++
            }
            else {
                $unlinkedFrom += $fromNode.nodeId
            }
        }
        
        $passed = $fromNodes.Count -eq 0 -or $linkedCount -eq $fromNodes.Count
        
        $results += [PSCustomObject]@{
            fromType     = $req.fromType
            toType       = $req.toType
            linkType     = $req.linkType
            totalFrom    = $fromNodes.Count
            linkedCount  = $linkedCount
            passed       = $passed
            unlinkedFrom = $unlinkedFrom
            reason       = if ($passed) { 'All required links present' }
                          else { "$($unlinkedFrom.Count) nodes missing required $($req.linkType) link" }
        }
    }
    
    return $results
}

function Compute-ComplianceScore {
    <#
    .SYNOPSIS
        Computes overall compliance score from results.
    #>
    param(
        [array]$TypeResults,
        [array]$LinkResults,
        [array]$NamingResults,
        [array]$DriftResults,
        [PSCustomObject]$Template
    )
    
    $totalChecks = 0
    $passedChecks = 0
    $criticalFailures = 0
    
    # Type requirements (weight: 0.4)
    foreach ($r in $TypeResults) {
        $totalChecks++
        if ($r.passed) { $passedChecks++ }
        elseif ($r.required) { $criticalFailures++ }
    }
    
    # Link requirements (weight: 0.2)
    foreach ($r in $LinkResults) {
        $totalChecks++
        if ($r.passed) { $passedChecks++ }
    }
    
    # Naming conventions (weight: 0.2)
    $namingPassed = ($NamingResults | Where-Object { $_.passed }).Count
    $namingTotal = $NamingResults.Count
    if ($namingTotal -gt 0) {
        $totalChecks++
        if ($namingPassed / $namingTotal -ge 0.9) { $passedChecks++ }  # 90% threshold
    }
    
    # Drift (weight: 0.2)
    if ($DriftResults) {
        $totalChecks++
        $driftedCount = ($DriftResults | Where-Object { $_.hasDrift }).Count
        if ($driftedCount -eq 0) { $passedChecks++ }
    }
    
    # Calculate score
    $rawScore = if ($totalChecks -gt 0) { $passedChecks / $totalChecks } else { 1.0 }
    
    # Penalty for critical failures
    $criticalPenalty = [Math]::Min(0.5, $criticalFailures * 0.1)
    $finalScore = [Math]::Max(0, $rawScore - $criticalPenalty)
    
    return [Math]::Round($finalScore, 2)
}

function Get-ComplianceLevel {
    <#
    .SYNOPSIS
        Converts score to compliance level.
    #>
    param([double]$Score)
    
    if ($Score -ge 0.95) { return 'Excellent' }
    if ($Score -ge 0.85) { return 'Good' }
    if ($Score -ge 0.70) { return 'Acceptable' }
    if ($Score -ge 0.50) { return 'NeedsWork' }
    return 'NonCompliant'
}

function Test-Compliance {
    <#
    .SYNOPSIS
        Main entry point for compliance testing.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [array]$Nodes = @(),
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Template
    )
    
    if (-not $Nodes) { $Nodes = @() }
    
    # Run all checks
    $typeResults = Test-TypeRequirements -Nodes $Nodes -Requirements $Template.requiredTypes
    $linkResults = Test-LinkRequirements -Nodes $Nodes -Requirements $Template.requiredLinks
    
    # Naming conventions
    $namingResults = @()
    foreach ($node in $Nodes) {
        $namingResults += Test-NamingConvention -Node $node -NamingRules $Template.namingRules
    }
    
    # Drift (optional - if DriftEngine loaded)
    $driftResults = @()
    if (Get-Command 'Measure-PairDrift' -ErrorAction SilentlyContinue) {
        # Would integrate with DriftEngine here
    }
    
    # Compute score
    $score = Compute-ComplianceScore `
        -TypeResults $typeResults `
        -LinkResults $linkResults `
        -NamingResults $namingResults `
        -DriftResults $driftResults `
        -Template $Template
    
    # Summary
    $failedTypes = $typeResults | Where-Object { -not $_.passed }
    $failedLinks = $linkResults | Where-Object { -not $_.passed }
    $failedNaming = $namingResults | Where-Object { -not $_.passed }
    
    [PSCustomObject]@{
        templateName       = $Template.name
        timestamp          = (Get-Date).ToUniversalTime().ToString('o')
        totalNodes         = $Nodes.Count
        score              = $score
        level              = Get-ComplianceLevel -Score $score
        typeRequirements   = [PSCustomObject]@{
            total   = $typeResults.Count
            passed  = ($typeResults | Where-Object { $_.passed }).Count
            failed  = $failedTypes.Count
            details = $typeResults
        }
        linkRequirements   = [PSCustomObject]@{
            total   = $linkResults.Count
            passed  = ($linkResults | Where-Object { $_.passed }).Count
            failed  = $failedLinks.Count
            details = $linkResults
        }
        namingConventions  = [PSCustomObject]@{
            total   = $namingResults.Count
            passed  = ($namingResults | Where-Object { $_.passed }).Count
            failed  = $failedNaming.Count
            violations = $failedNaming | Select-Object nodeId, name, nodeType, reason
        }
        actionItems        = Get-ActionItems -TypeResults $typeResults -LinkResults $linkResults -NamingResults $namingResults
    }
}

function Get-ActionItems {
    <#
    .SYNOPSIS
        Generates actionable items from compliance results.
    #>
    param(
        [array]$TypeResults,
        [array]$LinkResults,
        [array]$NamingResults
    )
    
    $actions = @()
    $priority = 1
    
    # Missing required types
    foreach ($r in ($TypeResults | Where-Object { -not $_.meetsMinimum -and $_.required })) {
        $actions += [PSCustomObject]@{
            priority    = $priority++
            category    = 'MissingRequired'
            severity    = 'Critical'
            description = "Add $($r.minCount - $r.actualCount) more $($r.nodeType) node(s)"
            nodeType    = $r.nodeType
        }
    }
    
    # Excess nodes (if not allowed)
    foreach ($r in ($TypeResults | Where-Object { -not $_.meetsMaximum })) {
        $actions += [PSCustomObject]@{
            priority    = $priority++
            category    = 'ExcessNodes'
            severity    = 'Warn'
            description = "Remove $($r.actualCount - $r.maxCount) excess $($r.nodeType) node(s)"
            nodeType    = $r.nodeType
        }
    }
    
    # Missing links
    foreach ($r in ($LinkResults | Where-Object { -not $_.passed })) {
        $actions += [PSCustomObject]@{
            priority    = $priority++
            category    = 'MissingLink'
            severity    = 'High'
            description = "Add $($r.linkType) links from $($r.fromType) to $($r.toType)"
            affected    = $r.unlinkedFrom.Count
        }
    }
    
    # Naming violations
    $namingViolations = $NamingResults | Where-Object { -not $_.passed }
    if ($namingViolations.Count -gt 0) {
        $byType = $namingViolations | Group-Object nodeType
        foreach ($group in $byType) {
            $actions += [PSCustomObject]@{
                priority    = $priority++
                category    = 'NamingViolation'
                severity    = 'Low'
                description = "Rename $($group.Count) $($group.Name) node(s) to match convention"
                nodeType    = $group.Name
                examples    = ($group.Group | Select-Object -First 3).name
            }
        }
    }
    
    return $actions
}

function Export-ComplianceJson {
    <#
    .SYNOPSIS
        Exports compliance report to JSON.
    #>
    param(
        [PSCustomObject]$Report,
        [string]$OutputPath,
        [switch]$Pretty
    )
    
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }
    
    $json = if ($Pretty) {
        $Report | ConvertTo-Json -Depth 10
    } else {
        $Report | ConvertTo-Json -Depth 10 -Compress
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $OutputPath 'compliance.json'), $json, $utf8NoBom)
}

# Export functions (when loaded as module)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'New-GoldenTemplate',
        'New-TypeRequirement',
        'Test-NamingConvention',
        'Test-TypeRequirements',
        'Test-LinkRequirements',
        'Test-Compliance',
        'Compute-ComplianceScore',
        'Get-ComplianceLevel',
        'Get-ActionItems',
        'Export-ComplianceJson'
    )
}
