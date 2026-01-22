# Robcad Study Health Report
# Lints RobcadStudy names and flags cross-study anomalies.

param(
    [Parameter(Mandatory = $true)]
    [string[]]$Input,

    [string]$OutDir = "out",

    [string]$RulesPath = "config/robcad-study-health-rules.json"
)

$ErrorActionPreference = "Stop"

$inputPaths = @()
if ($PSBoundParameters.ContainsKey('Input')) {
    $inputPaths = @($PSBoundParameters['Input'])
}

if (-not $inputPaths -and $Input) {
    $inputPaths = @($Input)
}

if (-not $inputPaths -or $inputPaths.Count -eq 0) {
    throw "Input is required. Provide one or more files with -Input."
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$resolvedRulesPath = $RulesPath
if (-not [System.IO.Path]::IsPathRooted($resolvedRulesPath)) {
    $resolvedRulesPath = Join-Path $repoRoot $resolvedRulesPath
}

function Read-Rules {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Rules file not found: $Path"
    }

    $json = Get-Content $Path -Raw -Encoding UTF8
    return $json | ConvertFrom-Json
}

function Get-GitBranch {
    $branch = ""
    try {
        $branch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
    } catch {
        $branch = ""
    }

    if ([string]::IsNullOrWhiteSpace($branch)) {
        return "unknown"
    }

    return $branch
}

function Get-TreeDataLinesFromHtml {
    param([string]$Path)

    $content = Get-Content $Path -Raw -Encoding UTF8
    $pattern = '(?s)const\s+rawData\s*=\s*`(.*?)`;'
    $match = [regex]::Match($content, $pattern)

    if (-not $match.Success) {
        throw "Unable to find rawData block in HTML: $Path"
    }

    $rawData = $match.Groups[1].Value
    if ($rawData -match 'TREE_DATA_PLACEHOLDER') {
        throw "HTML contains TREE_DATA_PLACEHOLDER. Use a generated tree HTML file."
    }

    return $rawData -split "`r?`n" | Where-Object { $_ -and $_.Contains('|') }
}

function Get-TreeDataLinesFromText {
    param([string]$Path)

    return Get-Content $Path -Encoding UTF8 | Where-Object { $_ -and $_.Contains('|') }
}

function Get-TreeDataLines {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        throw "Input file not found: $Path"
    }

    $extension = [System.IO.Path]::GetExtension($Path)
    if ($extension -eq ".html") {
        return Get-TreeDataLinesFromHtml -Path $Path
    }

    return Get-TreeDataLinesFromText -Path $Path
}

function Convert-LineToNode {
    param(
        [string]$Line,
        [string]$Source
    )

    if (-not $Line) {
        return $null
    }

    if (-not ($Line -match '\|')) {
        return $null
    }

    $parts = $Line -split '\|'
    if ($parts.Length -lt 10) {
        return $null
    }

    $objectId = $parts[2]
    if ([string]::IsNullOrWhiteSpace($objectId)) {
        return $null
    }

    $name = $parts[3]
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $parts[4]
    }

    return [PSCustomObject]@{
        Level = $parts[0]
        ParentId = $parts[1]
        ObjectId = $objectId
        Name = $name
        Caption = $name
        ExternalId = $parts[5]
        SeqNumber = $parts[6]
        ClassName = $parts[7]
        NiceName = $parts[8]
        TypeId = $parts[9]
        Sources = @($Source)
        Path = ""
        NormalizedName = ""
        TokensLower = @()
    }
}

function Add-Source {
    param(
        [hashtable]$NodeMap,
        [PSCustomObject]$Node
    )

    if (-not $NodeMap.ContainsKey($Node.ObjectId)) {
        $NodeMap[$Node.ObjectId] = $Node
        return
    }

    $existing = $NodeMap[$Node.ObjectId]
    if ($existing.Sources -notcontains $Node.Sources[0]) {
        $existing.Sources += $Node.Sources[0]
    }

    if ([string]::IsNullOrWhiteSpace($existing.Name) -and -not [string]::IsNullOrWhiteSpace($Node.Name)) {
        $existing.Name = $Node.Name
        $existing.Caption = $Node.Caption
    }

    if ([string]::IsNullOrWhiteSpace($existing.ClassName) -and -not [string]::IsNullOrWhiteSpace($Node.ClassName)) {
        $existing.ClassName = $Node.ClassName
    }

    if ([string]::IsNullOrWhiteSpace($existing.NiceName) -and -not [string]::IsNullOrWhiteSpace($Node.NiceName)) {
        $existing.NiceName = $Node.NiceName
    }

    if ([string]::IsNullOrWhiteSpace($existing.TypeId) -and -not [string]::IsNullOrWhiteSpace($Node.TypeId)) {
        $existing.TypeId = $Node.TypeId
    }
}

function Get-NameTokens {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return @()
    }

    $matches = [regex]::Matches($Name, "[A-Za-z0-9]+")
    if (-not $matches) {
        return @()
    }

    return $matches | ForEach-Object { $_.Value }
}

function Get-WordTokens {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return @()
    }

    return ($Name.Trim() -split '\s+') | Where-Object { $_ }
}

function Get-NormalizedStudyName {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return ""
    }

    $value = $Name.Trim()
    $value = $value -replace '\s+', ' '
    $value = $value -replace '[- ]', '_'
    $value = $value -replace '_+', '_'
    return $value.ToLowerInvariant()
}

function Get-NodePath {
    param(
        [string]$NodeId,
        [hashtable]$Nodes
    )

    if (-not $Nodes.ContainsKey($NodeId)) {
        return ""
    }

    $pathParts = New-Object System.Collections.Generic.List[string]
    $currentId = $NodeId
    $visited = @{}

    while ($currentId -and $Nodes.ContainsKey($currentId)) {
        if ($visited.ContainsKey($currentId)) {
            break
        }

        $visited[$currentId] = $true
        $node = $Nodes[$currentId]
        if (-not [string]::IsNullOrWhiteSpace($node.Name)) {
            $pathParts.Add($node.Name)
        }

        $currentId = $node.ParentId
    }

    if ($pathParts.Count -eq 0) {
        return ""
    }

    [array]::Reverse($pathParts)
    return ($pathParts -join " / ")
}

function Test-IsStudyNode {
    param(
        [PSCustomObject]$Node,
        [string]$StudyType
    )

    if (-not $Node) {
        return $false
    }

    if ($Node.NiceName -eq $StudyType) {
        return $true
    }

    if ($Node.ClassName -match $StudyType) {
        return $true
    }

    if ($Node.TypeId -eq "177") {
        return $true
    }

    return $false
}

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$Issues,
        [PSCustomObject]$Study,
        [string]$Severity,
        [string]$Issue,
        [string]$Details
    )

    $Issues.Add([PSCustomObject]@{
        NodeId = $Study.ObjectId
        StudyName = $Study.Name
        Severity = $Severity
        Issue = $Issue
        Details = $Details
        ParentId = $Study.ParentId
        Path = $Study.Path
        Sources = ($Study.Sources -join ";")
    })
}

function Get-EditDistance {
    param(
        [string]$A,
        [string]$B
    )

    if ($A -is [System.Array]) {
        $A = ($A | Select-Object -First 1)
    }

    if ($B -is [System.Array]) {
        $B = ($B | Select-Object -First 1)
    }

    if ($A -eq $B) {
        return 0
    }

    if (-not $A) {
        return $B.Length
    }

    if (-not $B) {
        return $A.Length
    }

    $lenA = [int]$A.Length
    $lenB = [int]$B.Length
    $minLen = [math]::Min($lenA, $lenB)
    $distance = [math]::Abs($lenA - $lenB)

    for ($index = 0; $index -lt $minLen; $index++) {
        if ($A[$index] -ne $B[$index]) {
            $distance++
        }
    }

    return $distance
}

function Get-Percentile {
    param(
        [int[]]$Values,
        [double]$Percent
    )

    if (-not $Values -or $Values.Count -eq 0) {
        return 0
    }

    $cleanValues = @()
    foreach ($value in $Values) {
        if ($null -eq $value) {
            continue
        }

        $cleanValues += [double]$value
    }

    if ($cleanValues.Count -eq 0) {
        return 0
    }

    $sorted = $cleanValues | Sort-Object
    $index = [math]::Floor(($sorted.Count - 1) * $Percent)
    return $sorted[$index]
}

$rules = Read-Rules -Path $resolvedRulesPath
$studyType = $rules.studyType
if (-not $studyType) {
    $studyType = "RobcadStudy"
}

$nodes = @{}
$inputSources = @()

foreach ($path in $inputPaths) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        throw "Input path is empty."
    }

    $resolvedPath = $null
    if (Test-Path -LiteralPath $path) {
        $resolvedPath = (Resolve-Path -LiteralPath $path).Path
    }

    if (-not $resolvedPath -and -not [System.IO.Path]::IsPathRooted($path)) {
        $candidate = Join-Path $repoRoot $path
        if (Test-Path -LiteralPath $candidate) {
            $resolvedPath = (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    if (-not $resolvedPath) {
        throw "Input file not found: $path"
    }

    $inputSources += $resolvedPath
    $lines = Get-TreeDataLines -Path $resolvedPath
    foreach ($line in $lines) {
        $node = Convert-LineToNode -Line $line -Source $resolvedPath
        if (-not $node) {
            continue
        }

        Add-Source -NodeMap $nodes -Node $node
    }
}

if ($nodes.Count -eq 0) {
    throw "No nodes parsed from input files."
}

foreach ($node in $nodes.Values) {
    $node.Path = Get-NodePath -NodeId $node.ObjectId -Nodes $nodes
    $node.NormalizedName = Get-NormalizedStudyName -Name $node.Name
    if ([string]::IsNullOrWhiteSpace($node.Name)) {
        $node.TokensLower = @()
        continue
    }

    $node.TokensLower = Get-NameTokens -Name ($node.Name.ToLowerInvariant())
}

$studies = $nodes.Values | Where-Object { Test-IsStudyNode -Node $_ -StudyType $studyType }
$studyList = @($studies)

if ($studyList.Count -eq 0) {
    throw "No RobcadStudy nodes found in inputs."
}

$studiesByParent = @{}
foreach ($study in $studyList) {
    $parentId = $study.ParentId
    if (-not $studiesByParent.ContainsKey($parentId)) {
        $studiesByParent[$parentId] = @()
    }

    $studiesByParent[$parentId] += $study
}

$issues = New-Object System.Collections.Generic.List[object]
$nbsp = [char]0x00A0
$illegalChars = @()
if ($rules.illegalChars) {
    $illegalChars = $rules.illegalChars
}

$illegalPattern = ""
if ($illegalChars.Count -gt 0) {
    $illegalPattern = ($illegalChars | ForEach-Object { [regex]::Escape($_) }) -join ""
}

foreach ($study in $studyList) {
    $name = $study.Name

    if ([string]::IsNullOrWhiteSpace($name)) {
        Add-Issue -Issues $issues -Study $study -Severity "Critical" -Issue "empty_name" -Details "Name is empty or whitespace."
        continue
    }

    if ($name -ne $name.Trim()) {
        Add-Issue -Issues $issues -Study $study -Severity "Critical" -Issue "leading_trailing_whitespace" -Details "Leading or trailing whitespace."
    }

    if ($name -like "*`t*" -or $name -like "*$nbsp*") {
        Add-Issue -Issues $issues -Study $study -Severity "Critical" -Issue "invisible_whitespace" -Details "Contains tabs or NBSP."
    }

    if ($illegalPattern -and ($name -match "[$illegalPattern]")) {
        Add-Issue -Issues $issues -Study $study -Severity "Critical" -Issue "illegal_chars" -Details "Contains illegal characters."
    }

    $nameLower = $name.ToLowerInvariant()
    $tokensLower = $study.TokensLower

    $junkTokensFound = @()
    if ($rules.junkTokens) {
        $junkTokensFound = $rules.junkTokens | Where-Object { $tokensLower -contains $_ }
    }

    $junkPhrasesFound = @()
    if ($rules.junkPhrases) {
        $junkPhrasesFound = $rules.junkPhrases | Where-Object { $nameLower -like "*$_*" }
    }

    if ($junkTokensFound.Count -gt 0 -or $junkPhrasesFound.Count -gt 0) {
        $detail = (@($junkTokensFound + $junkPhrasesFound) | Sort-Object -Unique) -join ", "
        Add-Issue -Issues $issues -Study $study -Severity "High" -Issue "junk_tokens" -Details "Contains placeholder tokens: $detail"
    }

    if ($nameLower -match '(?i)[0-9a-f]{16,}') {
        Add-Issue -Issues $issues -Study $study -Severity "High" -Issue "hash_like_name" -Details "Looks like a GUID or hash."
    }

    if ($nameLower -match '(?i)([a-z]:\\|\\\\|/home/)') {
        Add-Issue -Issues $issues -Study $study -Severity "High" -Issue "file_path_name" -Details "Contains a file path."
    }

    $legacyTokensFound = @()
    if ($rules.legacyTokens) {
        $legacyTokensFound = $rules.legacyTokens | Where-Object { $tokensLower -contains $_ }
    }

    $yearPattern = $rules.yearPattern
    $hasYearStamp = $false
    if ($yearPattern -and ($nameLower -match $yearPattern)) {
        $hasYearStamp = $true
    }

    if ($legacyTokensFound.Count -gt 0 -or $hasYearStamp) {
        $legacyDetails = $legacyTokensFound -join ", "
        if ($hasYearStamp) {
            if ($legacyDetails) {
                $legacyDetails = "$legacyDetails, year_stamp"
            } else {
                $legacyDetails = "year_stamp"
            }
        }
        Add-Issue -Issues $issues -Study $study -Severity "High" -Issue "legacy_markers" -Details "Contains legacy markers: $legacyDetails"
    }

    if ($rules.maxNameLength -and $name.Length -gt [int]$rules.maxNameLength) {
        Add-Issue -Issues $issues -Study $study -Severity "Low" -Issue "overlong_name" -Details "Length $($name.Length) exceeds $($rules.maxNameLength)."
    }

    $wordTokens = Get-WordTokens -Name $name
    if ($rules.maxWordCount -and $wordTokens.Count -gt [int]$rules.maxWordCount) {
        Add-Issue -Issues $issues -Study $study -Severity "Low" -Issue "too_many_tokens" -Details "Word count $($wordTokens.Count) exceeds $($rules.maxWordCount)."
    }

    if ($rules.abbreviation) {
        $tokenMatches = Get-NameTokens -Name $name
        $abbrevTokens = @()
        if ($tokenMatches.Count -gt 0) {
            $abbrevTokens = $tokenMatches | Where-Object {
                $_.Length -le [int]$rules.abbreviation.maxTokenLength -and $_ -match '^[A-Z0-9]+$'
            }
        }

        $minTokenCount = [int]$rules.abbreviation.minTokenCount
        $minRatio = [double]$rules.abbreviation.minRatio
        if ($tokenMatches.Count -ge $minTokenCount) {
            $ratio = 0
            if ($tokenMatches.Count -gt 0) {
                $ratio = $abbrevTokens.Count / $tokenMatches.Count
            }

            if ($ratio -ge $minRatio) {
                Add-Issue -Issues $issues -Study $study -Severity "Low" -Issue "abbreviation_soup" -Details "Abbrev ratio $([math]::Round($ratio, 2))."
            }
        }
    }
}

foreach ($parentId in $studiesByParent.Keys) {
    $siblings = $studiesByParent[$parentId]
    if ($siblings.Count -lt 2) {
        continue
    }

    $normalizedMap = @{}
    foreach ($study in $siblings) {
        $norm = $study.NormalizedName
        if (-not $normalizedMap.ContainsKey($norm)) {
            $normalizedMap[$norm] = @()
        }
        $normalizedMap[$norm] += $study
    }

    foreach ($norm in $normalizedMap.Keys) {
        $group = $normalizedMap[$norm]
        if ($group.Count -lt 2) {
            continue
        }

        foreach ($study in $group) {
            Add-Issue -Issues $issues -Study $study -Severity "Critical" -Issue "duplicate_sibling" -Details "Duplicate sibling normalized name: $norm"
        }
    }

    $separatorMap = @{}
    foreach ($study in $siblings) {
        $name = $study.Name
        $signature = @()
        if ($name -match '_') { $signature += '_' }
        if ($name -match '-') { $signature += '-' }
        if ($name -match '\s') { $signature += 'space' }

        if ($signature.Count -eq 0) { $signature = @('none') }
        if ($signature.Count -gt 1) { $signature = @('mixed') }

        $separatorMap[$study.ObjectId] = $signature[0]
    }

    $usedSeparators = $separatorMap.Values | Where-Object { $_ -ne 'none' } | Sort-Object -Unique
    if ($usedSeparators.Count -gt 1) {
        foreach ($study in $siblings) {
            if ($separatorMap[$study.ObjectId] -eq 'none') {
                continue
            }

            Add-Issue -Issues $issues -Study $study -Severity "Medium" -Issue "separator_inconsistency" -Details "Mixed separators among siblings."
        }
    }

    $caseMap = @{}
    foreach ($study in $siblings) {
        $key = $study.Name.Trim().ToLowerInvariant()
        if (-not $caseMap.ContainsKey($key)) {
            $caseMap[$key] = @()
        }
        $caseMap[$key] += $study
    }

    foreach ($key in $caseMap.Keys) {
        $group = $caseMap[$key]
        if ($group.Count -lt 2) {
            continue
        }

        $distinctNames = $group | Select-Object -ExpandProperty Name -Unique
        if ($distinctNames.Count -lt 2) {
            continue
        }

        foreach ($study in $group) {
            Add-Issue -Issues $issues -Study $study -Severity "Medium" -Issue "case_drift" -Details "Case drift among sibling names."
        }
    }

    $numberMap = @{}
    foreach ($study in $siblings) {
        $numbers = [regex]::Matches($study.Name, '\d+')
        foreach ($match in $numbers) {
            $value = [int]$match.Value
            if (-not $numberMap.ContainsKey($value)) {
                $numberMap[$value] = @{}
            }

            $numberMap[$value][$match.Value.Length] = $true
        }
    }

    $driftValues = $numberMap.Keys | Where-Object { $numberMap[$_].Keys.Count -gt 1 }
    if ($driftValues.Count -gt 0) {
        foreach ($study in $siblings) {
            $studyNumbers = [regex]::Matches($study.Name, '\d+') | ForEach-Object { [int]$_.Value }
            if ($studyNumbers | Where-Object { $driftValues -contains $_ }) {
                Add-Issue -Issues $issues -Study $study -Severity "Medium" -Issue "numbering_drift" -Details "Inconsistent zero padding among siblings."
            }
        }
    }
}

$normalizedGroups = $studyList | Group-Object -Property NormalizedName
foreach ($group in $normalizedGroups) {
    if ($group.Count -lt 2) {
        continue
    }

    $uniqueNames = $group.Group | Select-Object -ExpandProperty Name -Unique
    if ($uniqueNames.Count -lt 2) {
        continue
    }

    foreach ($study in $group.Group) {
        Add-Issue -Issues $issues -Study $study -Severity "Medium" -Issue "near_duplicate" -Details "Normalized name collision: $($group.Name)"
    }
}

$lengths = $studyList | ForEach-Object {
    if ([string]::IsNullOrWhiteSpace($_.Name)) { 0 } else { $_.Name.Trim().Length }
}
$q1 = [double]((Get-Percentile -Values $lengths -Percent 0.25) | Select-Object -First 1)
$q3 = [double]((Get-Percentile -Values $lengths -Percent 0.75) | Select-Object -First 1)
if ($q1 -is [System.Array]) {
    $q1 = [double]($q1 | Select-Object -First 1)
}
if ($q3 -is [System.Array]) {
    $q3 = [double]($q3 | Select-Object -First 1)
}
$iqr = $q3 - $q1
$lengthLow = $q1 - (1.5 * $iqr)
$lengthHigh = $q3 + (1.5 * $iqr)

$tokenCounts = @{}
foreach ($study in $studyList) {
    $uniqueTokens = $study.TokensLower | Sort-Object -Unique
    foreach ($token in $uniqueTokens) {
        if (-not $tokenCounts.ContainsKey($token)) {
            $tokenCounts[$token] = 0
        }
        $tokenCounts[$token]++
    }
}

$nearest = @{}
foreach ($study in $studyList) {
    $nearest[$study.ObjectId] = [PSCustomObject]@{
        Distance = [double]::PositiveInfinity
        NeighborId = ""
        NeighborName = ""
    }
}

for ($i = 0; $i -lt $studyList.Count; $i++) {
    $studyA = $studyList[$i]
    for ($j = $i + 1; $j -lt $studyList.Count; $j++) {
        $studyB = $studyList[$j]
        $distance = Get-EditDistance -A $studyA.NormalizedName -B $studyB.NormalizedName
        $maxLen = [math]::Max($studyA.NormalizedName.Length, $studyB.NormalizedName.Length)
        $norm = 0
        if ($maxLen -gt 0) {
            $norm = $distance / $maxLen
        }

        if ($norm -lt $nearest[$studyA.ObjectId].Distance) {
            $nearest[$studyA.ObjectId].Distance = $norm
            $nearest[$studyA.ObjectId].NeighborId = $studyB.ObjectId
            $nearest[$studyA.ObjectId].NeighborName = $studyB.Name
        }

        if ($norm -lt $nearest[$studyB.ObjectId].Distance) {
            $nearest[$studyB.ObjectId].Distance = $norm
            $nearest[$studyB.ObjectId].NeighborId = $studyA.ObjectId
            $nearest[$studyB.ObjectId].NeighborName = $studyA.Name
        }
    }
}

$suspicious = @()
$rareThreshold = [double]$rules.rareTokenPercent
if (-not $rareThreshold) {
    $rareThreshold = 2
}

$distanceThreshold = [double]$rules.editDistance.maxNormalizedDistance
if (-not $distanceThreshold) {
    $distanceThreshold = 0.6
}

foreach ($study in $studyList) {
    $reasons = New-Object System.Collections.Generic.List[string]
    $uniqueTokens = $study.TokensLower | Sort-Object -Unique
    $rareTokens = @()
    foreach ($token in $uniqueTokens) {
        if (-not $tokenCounts.ContainsKey($token)) {
            continue
        }

        $percent = ($tokenCounts[$token] / $studyList.Count) * 100
        if ($percent -lt $rareThreshold) {
            $rareTokens += $token
        }
    }

    if ($rareTokens.Count -gt 0) {
        $reasons.Add("rare_tokens: $($rareTokens -join ', ')")
    }

    $uniqueJunk = @()
    if ($rules.junkTokens) {
        foreach ($junk in $rules.junkTokens) {
            if ($uniqueTokens -contains $junk -and $tokenCounts[$junk] -eq 1) {
                $uniqueJunk += $junk
            }
        }
    }

    if ($uniqueJunk.Count -gt 0) {
        $reasons.Add("unique_junk_tokens: $($uniqueJunk -join ', ')")
    }

    $nameLength = 0
    if (-not [string]::IsNullOrWhiteSpace($study.Name)) {
        $nameLength = $study.Name.Trim().Length
    }
    if ($iqr -gt 0 -and ($nameLength -lt $lengthLow -or $nameLength -gt $lengthHigh)) {
        $reasons.Add("length_outlier: $nameLength")
    }

    $neighbor = $nearest[$study.ObjectId]
    $nearestDistance = $neighbor.Distance
    if (-not [double]::IsInfinity($nearestDistance) -and $nearestDistance -gt $distanceThreshold) {
        $reasons.Add("edit_distance: $([math]::Round($nearestDistance, 2))")
    }

    if ($reasons.Count -eq 0) {
        continue
    }

    if ([double]::IsInfinity($nearestDistance)) {
        $nearestDistance = 0
    }

    $suspicious += [PSCustomObject]@{
        NodeId = $study.ObjectId
        StudyName = $study.Name
        Reasons = ($reasons -join "; ")
        NearestMatch = $neighbor.NeighborName
        "Score/Distance" = [math]::Round($nearestDistance, 2)
        Score = [math]::Round(($reasons.Count + $nearestDistance), 2)
        Path = $study.Path
        Sources = ($study.Sources -join ";")
    }
}

if (-not (Test-Path $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir | Out-Null
}

$reportPath = Join-Path $OutDir "robcad-study-health-report.md"
$issuesPath = Join-Path $OutDir "robcad-study-health-issues.csv"
$suspiciousPath = Join-Path $OutDir "robcad-study-health-suspicious.csv"
$renamePath = Join-Path $OutDir "robcad-study-health-rename-suggestions.csv"

$issues | Sort-Object Severity, Issue, StudyName | Export-Csv -Path $issuesPath -NoTypeInformation -Encoding UTF8

$suspiciousOutput = $suspicious | Sort-Object Score -Descending
$suspiciousOutput | Select-Object NodeId, StudyName, Reasons, NearestMatch, "Score/Distance" | Export-Csv -Path $suspiciousPath -NoTypeInformation -Encoding UTF8

$renameSuggestions = @()
foreach ($study in $studyList) {
    if ([string]::IsNullOrWhiteSpace($study.Name)) {
        continue
    }

    $suggested = $study.Name
    $suggested = $suggested.Trim()
    $escapedNbsp = [regex]::Escape($nbsp)
    $suggested = $suggested -replace "(`t|$escapedNbsp)+", ' '
    if ($illegalPattern) {
        $suggested = $suggested -replace "[$illegalPattern]", "_"
    }
    $suggested = $suggested -replace '\s+', ' '
    $suggested = $suggested.Trim()

    if ($suggested -ne $study.Name) {
        $renameSuggestions += [PSCustomObject]@{
            NodeId = $study.ObjectId
            StudyName = $study.Name
            SuggestedName = $suggested
            Reason = "Trimmed whitespace or removed illegal characters."
        }
    }
}

if ($renameSuggestions.Count -gt 0) {
    $renameSuggestions | Export-Csv -Path $renamePath -NoTypeInformation -Encoding UTF8
}

$severityCounts = @{
    Critical = 0
    High = 0
    Medium = 0
    Low = 0
}

foreach ($issue in $issues) {
    if ($severityCounts.ContainsKey($issue.Severity)) {
        $severityCounts[$issue.Severity]++
    }
}

$issuesByStudy = $issues | Group-Object NodeId | Sort-Object Count -Descending
$issuesByParent = $issues | Group-Object ParentId | Sort-Object Count -Descending

$topStudyLines = @()
foreach ($entry in ($issuesByStudy | Select-Object -First 5)) {
    $study = $studyList | Where-Object { $_.ObjectId -eq $entry.Name } | Select-Object -First 1
    $label = $entry.Name
    if ($study) {
        $label = "$($study.Name) ($($study.ObjectId))"
    }
    $topStudyLines += "- ${label}: $($entry.Count) issues"
}

$topParentLines = @()
foreach ($entry in ($issuesByParent | Select-Object -First 5)) {
    $parent = $nodes[$entry.Name]
    $label = $entry.Name
    if ($parent) {
        $label = "$($parent.Name) ($($parent.ObjectId))"
    }
    $topParentLines += "- ${label}: $($entry.Count) issues"
}

$suspiciousLines = @()
foreach ($item in ($suspiciousOutput | Select-Object -First 10)) {
    $suspiciousLines += "- $($item.StudyName) ($($item.NodeId)): $($item.Reasons) | Nearest: $($item.NearestMatch)"
}

$timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$branch = Get-GitBranch
$inputList = ($inputSources | Sort-Object -Unique) -join ", "

$reportLines = @()
$reportLines += "# Robcad Study Health Report"
$reportLines += ""
$reportLines += "## Run Context"
$reportLines += "- Timestamp: $timestamp"
$reportLines += "- Branch: $branch"
$reportLines += "- Input: $inputList"
$reportLines += ""
$reportLines += "## Totals"
$reportLines += "- Total nodes scanned: $($nodes.Count)"
$reportLines += "- Total studies scanned: $($studyList.Count)"
$reportLines += ""
$reportLines += "## Severity Counts"
$reportLines += "- Critical: $($severityCounts.Critical)"
$reportLines += "- High: $($severityCounts.High)"
$reportLines += "- Medium: $($severityCounts.Medium)"
$reportLines += "- Low: $($severityCounts.Low)"
$reportLines += ""
$reportLines += "## Top Offenders (Studies)"
if ($topStudyLines.Count -eq 0) {
    $reportLines += "- None"
} else {
    $reportLines += $topStudyLines
}
$reportLines += ""
$reportLines += "## Top Offenders (Parents)"
if ($topParentLines.Count -eq 0) {
    $reportLines += "- None"
} else {
    $reportLines += $topParentLines
}
$reportLines += ""
$reportLines += "## Suspicious Studies"
if ($suspiciousLines.Count -eq 0) {
    $reportLines += "- None"
} else {
    $reportLines += $suspiciousLines
}
$reportLines += ""
$reportLines += "## Outputs"
$reportLines += "- $issuesPath"
$reportLines += "- $suspiciousPath"
if ($renameSuggestions.Count -gt 0) {
    $reportLines += "- $renamePath"
}

$reportLines | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host "Wrote report: $reportPath" -ForegroundColor Green
Write-Host "Wrote issues CSV: $issuesPath" -ForegroundColor Green
Write-Host "Wrote suspicious CSV: $suspiciousPath" -ForegroundColor Green
if ($renameSuggestions.Count -gt 0) {
    Write-Host "Wrote rename suggestions CSV: $renamePath" -ForegroundColor Green
}
