<#
.SYNOPSIS
    Tests nodes against a compliance template.
    
.DESCRIPTION
    Checks a node subtree against a template and produces a compliance report
    with score, missing items, violations, extras, and per-rule breakdown.
    
.PARAMETER NodesPath
    Path to the nodes JSON file.
    
.PARAMETER TemplatePath
    Path to the template JSON file.
    
.PARAMETER OutPath
    Output path for the compliance results JSON file.
    
.EXAMPLE
    Test-TemplateCompliance -NodesPath nodes.json -TemplatePath template.json -OutPath compliance.json
#>

function Test-TemplateCompliance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NodesPath,
        
        [Parameter(Mandatory = $true)]
        [string]$TemplatePath,
        
        [Parameter(Mandatory = $true)]
        [string]$OutPath
    )
    
    # Guard: Check if files exist
    if (-not (Test-Path $NodesPath)) {
        Write-Warning "Nodes file not found: $NodesPath"
        return $false
    }
    
    if (-not (Test-Path $TemplatePath)) {
        Write-Warning "Template file not found: $TemplatePath"
        return $false
    }
    
    # Load data
    $nodes = Get-Content $NodesPath | ConvertFrom-Json
    $template = Get-Content $TemplatePath | ConvertFrom-Json
    
    # Initialize results
    $missing = @()
    $violations = @()
    $extras = @()
    $perRule = @()
    
    # Build node lookup
    $nodeMap = @{}
    foreach ($node in $nodes) {
        $nodeMap[$node.id] = $node
    }
    
    # 1. Check requiredTypes
    $typeCounts = @{}
    foreach ($node in $nodes) {
        $nodeType = $node.nodeType
        if (-not $nodeType) {
            $nodeType = "Unknown"
        }
        if (-not $typeCounts.ContainsKey($nodeType)) {
            $typeCounts[$nodeType] = 0
        }
        $typeCounts[$nodeType]++
    }
    
    $typeRulesPassed = 0
    $typeRulesTotal = 0
    
    if ($template.requiredTypes) {
        foreach ($req in $template.requiredTypes) {
            $typeRulesTotal++
            $nodeType = $req.nodeType
            $minCount = if ($req.min) { $req.min } else { 0 }
            $maxCount = if ($req.max) { $req.max } else { [int]::MaxValue }
            
            $actualCount = if ($typeCounts.ContainsKey($nodeType)) { $typeCounts[$nodeType] } else { 0 }
            
            $rulePassed = $true
            
            if ($actualCount -lt $minCount) {
                $missing += @{
                    nodeType = $nodeType
                    required = $minCount
                    actual = $actualCount
                    message = "Missing $($minCount - $actualCount) $nodeType node(s)"
                }
                $rulePassed = $false
            }
            
            if ($actualCount -gt $maxCount) {
                # Find extra node IDs
                $typeNodes = $nodes | Where-Object { $_.nodeType -eq $nodeType } | Select-Object -Skip $maxCount
                foreach ($extraNode in $typeNodes) {
                    $extras += @{
                        nodeId = $extraNode.id
                        nodeType = $nodeType
                        message = "Extra $nodeType node exceeds maximum of $maxCount"
                    }
                }
                $rulePassed = $false
            }
            
            if ($rulePassed) {
                $typeRulesPassed++
            }
            
            $perRule += @{
                ruleName = "requiredType:$nodeType"
                ruleType = "requiredType"
                passed = $rulePassed
                score = if ($rulePassed) { 100 } else { [Math]::Round(($actualCount / $minCount) * 100, 0) }
                details = @{
                    nodeType = $nodeType
                    required = $minCount
                    max = $maxCount
                    actual = $actualCount
                }
            }
        }
    }
    
    # 2. Check requiredLinks
    $linkRulesPassed = 0
    $linkRulesTotal = 0
    
    $actualLinks = @{}
    foreach ($node in $nodes) {
        if ($node.parentId -and $nodeMap.ContainsKey($node.parentId)) {
            $parentNode = $nodeMap[$node.parentId]
            $linkKey = "$($parentNode.nodeType)->$($node.nodeType)"
            $actualLinks[$linkKey] = $true
        }
    }
    
    if ($template.requiredLinks) {
        foreach ($link in $template.requiredLinks) {
            $linkRulesTotal++
            $linkKey = "$($link.from)->$($link.to)"
            
            $linkExists = $actualLinks.ContainsKey($linkKey)
            
            if (-not $linkExists) {
                $missing += @{
                    linkType = $linkKey
                    from = $link.from
                    to = $link.to
                    message = "Missing required link from $($link.from) to $($link.to)"
                }
            }
            
            if ($linkExists) {
                $linkRulesPassed++
            }
            
            $perRule += @{
                ruleName = "requiredLink:$linkKey"
                ruleType = "requiredLink"
                passed = $linkExists
                score = if ($linkExists) { 100 } else { 0 }
                details = @{
                    from = $link.from
                    to = $link.to
                }
            }
        }
    }
    
    # 3. Check namingRules
    $namingRulesPassed = 0
    $namingRulesTotal = 0
    $namingViolations = @()
    
    if ($template.namingRules) {
        foreach ($rule in $template.namingRules) {
            $nodeType = $rule.nodeType
            $pattern = $rule.pattern
            
            $typeNodes = $nodes | Where-Object { $_.nodeType -eq $nodeType }
            
            foreach ($node in $typeNodes) {
                $namingRulesTotal++
                $name = $node.name
                
                $matches = $false
                try {
                    $matches = $name -match $pattern
                } catch {
                    # Invalid regex - treat as not matching
                    $matches = $false
                }
                
                if (-not $matches) {
                    $namingViolations += @{
                        nodeId = $node.id
                        nodeName = $name
                        nodeType = $nodeType
                        pattern = $pattern
                        rule = "naming"
                        message = "Name '$name' does not match pattern '$pattern'"
                    }
                }
                
                if ($matches) {
                    $namingRulesPassed++
                }
            }
        }
        
        # Add naming violations to overall violations
        $violations += $namingViolations
        
        $namingScore = if ($namingRulesTotal -gt 0) { [Math]::Round(($namingRulesPassed / $namingRulesTotal) * 100, 0) } else { 100 }
        
        $perRule += @{
            ruleName = "naming"
            ruleType = "naming"
            passed = ($namingViolations.Count -eq 0)
            score = $namingScore
            details = @{
                checked = $namingRulesTotal
                passed = $namingRulesPassed
                violations = $namingViolations.Count
            }
        }
    }
    
    # 4. Check for extras if allowedExtras is false
    if (-not $template.allowedExtras) {
        $allowedTypes = @{}
        if ($template.requiredTypes) {
            foreach ($req in $template.requiredTypes) {
                $allowedTypes[$req.nodeType] = $true
            }
        }
        
        foreach ($node in $nodes) {
            if (-not $allowedTypes.ContainsKey($node.nodeType)) {
                $extras += @{
                    nodeId = $node.id
                    nodeType = $node.nodeType
                    message = "Node type '$($node.nodeType)' is not allowed in template"
                }
            }
        }
    }
    
    # 5. Calculate overall score
    $totalRules = $typeRulesTotal + $linkRulesTotal + (if ($namingRulesTotal -gt 0) { 1 } else { 0 })
    $passedRules = $typeRulesPassed + $linkRulesPassed + (if ($namingViolations.Count -eq 0 -and $namingRulesTotal -gt 0) { 1 } else { 0 })
    
    $score = 100
    if ($totalRules -gt 0) {
        $score = [Math]::Round(($passedRules / $totalRules) * 100, 0)
    }
    
    # Apply penalties
    $score -= $missing.Count * 5
    $score -= $violations.Count * 2
    $score -= $extras.Count * 1
    
    $score = [Math]::Max(0, [Math]::Min(100, $score))
    
    # Build result (deterministic sorting)
    $result = [ordered]@{
        score = $score
        templateName = $template.name
        checkedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        missing = ($missing | Sort-Object { $_.nodeType ?? $_.linkType })
        violations = ($violations | Sort-Object { $_.nodeId })
        extras = ($extras | Sort-Object { $_.nodeId })
        perRule = ($perRule | Sort-Object { $_.ruleName })
    }
    
    # Ensure output directory exists
    $outDir = Split-Path $OutPath -Parent
    if ($outDir -and -not (Test-Path $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }
    
    # Write results
    $result | ConvertTo-Json -Depth 10 | Set-Content -Path $OutPath -Encoding UTF8
    
    return $true
}

# Export function for module use
Export-ModuleMember -Function Test-TemplateCompliance -ErrorAction SilentlyContinue
