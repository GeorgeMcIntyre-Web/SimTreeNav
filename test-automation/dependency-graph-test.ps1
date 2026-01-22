# Dependency graph validation script
# Verifies expected chains, detects cycles, and reports orphans.

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$EdgesPath,

    [string]$ExpectedChainsPath = "",
    [string[]]$RootIds = @(),
    [int]$MaxCycleSamples = 10,
    [string]$OutputReport = "test-automation/results/dependency-graph-test.json"
)

function Add-Issue {
    param([string]$Message)
    $script:results.issues += $Message
    $script:results.status = "fail"
}

function Load-Edges {
    param([string]$Path)
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -eq ".json") {
        $json = Get-Content $Path -Raw | ConvertFrom-Json
        return $json
    }
    return Import-Csv $Path
}

function Load-Chains {
    param([string]$Path)
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -eq ".json") {
        return (Get-Content $Path -Raw | ConvertFrom-Json)
    }
    return Import-Csv $Path
}

if (-not (Test-Path $EdgesPath)) { throw "Edges file not found: $EdgesPath" }

$results = [ordered]@{
    test = "dependency-graph-test"
    startedAt = (Get-Date).ToString("s")
    status = "pass"
    issues = @()
    metrics = [ordered]@{}
    samples = [ordered]@{}
}

$edges = Load-Edges -Path $EdgesPath
$adj = @{}
$allNodes = New-Object System.Collections.Generic.HashSet[string]
$childNodes = New-Object System.Collections.Generic.HashSet[string]

foreach ($edge in $edges) {
    $parent = $edge.parentId
    $child = $edge.childId
    if (-not $parent -or -not $child) { continue }

    if (-not $adj.ContainsKey($parent)) { $adj[$parent] = @() }
    $adj[$parent] += $child

    [void]$allNodes.Add([string]$parent)
    [void]$allNodes.Add([string]$child)
    [void]$childNodes.Add([string]$child)
}

# Orphan detection
$orphans = @()
foreach ($node in $allNodes) {
    if (-not $childNodes.Contains($node) -and -not ($RootIds -contains $node)) {
        $orphans += $node
    }
}
$results.metrics.orphanCount = $orphans.Count
$results.samples.orphans = $orphans | Select-Object -First 20

# Cycle detection
$state = @{} # 0 unvisited, 1 visiting, 2 visited
$cycles = New-Object System.Collections.Generic.List[string]

function Visit {
    param([string]$node, [System.Collections.Generic.List[string]]$path)

    if ($state[$node] -eq 1) {
        $cyclePath = ($path + $node) -join " -> "
        $cycles.Add($cyclePath) | Out-Null
        return
    }
    if ($state[$node] -eq 2) { return }

    $state[$node] = 1
    $newPath = New-Object System.Collections.Generic.List[string]
    $path.ForEach({ $newPath.Add($_) })
    $newPath.Add($node)

    if ($adj.ContainsKey($node)) {
        foreach ($child in $adj[$node]) {
            Visit -node $child -path $newPath
            if ($cycles.Count -ge $MaxCycleSamples) { return }
        }
    }

    $state[$node] = 2
}

foreach ($node in $allNodes) {
    if (-not $state.ContainsKey($node)) {
        Visit -node $node -path (New-Object System.Collections.Generic.List[string])
        if ($cycles.Count -ge $MaxCycleSamples) { break }
    }
}

$results.metrics.cycleCount = $cycles.Count
$results.samples.cycles = $cycles

if ($cycles.Count -gt 0) {
    Add-Issue "Cycles detected in dependency graph"
}

# Expected chains validation
if ($ExpectedChainsPath) {
    if (-not (Test-Path $ExpectedChainsPath)) {
        Add-Issue "Expected chains file not found: $ExpectedChainsPath"
    } else {
        $chains = Load-Chains -Path $ExpectedChainsPath
        $missingEdges = New-Object System.Collections.Generic.List[string]

        foreach ($chain in $chains) {
            $nodes = $null
            if ($chain -is [System.Array]) {
                $nodes = $chain
            } elseif ($chain.chain) {
                $nodes = $chain.chain
            } else {
                $nodes = @($chain.parentId, $chain.childId)
            }

            for ($i = 0; $i -lt ($nodes.Count - 1); $i++) {
                $p = [string]$nodes[$i]
                $c = [string]$nodes[$i + 1]
                if (-not ($adj.ContainsKey($p) -and $adj[$p] -contains $c)) {
                    $missingEdges.Add("$p -> $c") | Out-Null
                }
            }
        }

        $results.metrics.missingChainEdges = $missingEdges.Count
        $results.samples.missingChainEdges = $missingEdges | Select-Object -First 20
        if ($missingEdges.Count -gt 0) {
            Add-Issue "Missing edges found in expected chains"
        }
    }
}

$results.endedAt = (Get-Date).ToString("s")

$reportDir = Split-Path $OutputReport
if ($reportDir -and -not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
}

$results | ConvertTo-Json -Depth 6 | Set-Content -Encoding ASCII $OutputReport

Write-Host "Dependency graph test complete. Status: $($results.status)"
Write-Host "Report: $OutputReport"
if ($results.status -eq "fail") {
    exit 1
}
