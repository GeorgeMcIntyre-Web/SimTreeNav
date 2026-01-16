# StreamingJsonWriter.ps1 - Write large JSON files incrementally without holding entire array in memory
# Supports: nodes.json, diff.json, actions.json, impact.json, drift.json

<#
.SYNOPSIS
    Streaming JSON writer for large tree data without memory bloat.
    
.DESCRIPTION
    Provides a streaming approach to writing JSON arrays that can be
    very large (50k+ nodes). Writes incrementally to disk instead of
    building the entire structure in memory.
#>

class StreamingJsonWriter {
    [string]$FilePath
    [System.IO.StreamWriter]$Writer
    [int]$ItemCount
    [bool]$IsFirstItem
    [string]$ArrayName
    [bool]$IsOpen
    
    StreamingJsonWriter([string]$path, [string]$arrayName = "nodes") {
        $this.FilePath = $path
        $this.ArrayName = $arrayName
        $this.ItemCount = 0
        $this.IsFirstItem = $true
        $this.IsOpen = $false
    }
    
    [void] Open() {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $this.Writer = [System.IO.StreamWriter]::new($this.FilePath, $false, $utf8NoBom, 65536)
        $this.Writer.AutoFlush = $false
        $this.IsOpen = $true
        
        # Write opening
        $this.Writer.WriteLine("{")
        $this.Writer.WriteLine("  `"$($this.ArrayName)`": [")
    }
    
    [void] WriteNode([hashtable]$node) {
        if (-not $this.IsOpen) {
            throw "StreamingJsonWriter is not open. Call Open() first."
        }
        
        # Convert hashtable to JSON (single object)
        $json = $node | ConvertTo-Json -Depth 5 -Compress
        
        # Write comma separator if not first item
        if (-not $this.IsFirstItem) {
            $this.Writer.WriteLine(",")
        }
        
        # Write the node (indented)
        $this.Writer.Write("    $json")
        
        $this.IsFirstItem = $false
        $this.ItemCount++
        
        # Flush periodically to prevent memory buildup
        if ($this.ItemCount % 1000 -eq 0) {
            $this.Writer.Flush()
        }
    }
    
    [void] WriteNodeJson([string]$jsonString) {
        if (-not $this.IsOpen) {
            throw "StreamingJsonWriter is not open. Call Open() first."
        }
        
        # Write comma separator if not first item
        if (-not $this.IsFirstItem) {
            $this.Writer.WriteLine(",")
        }
        
        # Write the pre-formatted JSON (indented)
        $this.Writer.Write("    $jsonString")
        
        $this.IsFirstItem = $false
        $this.ItemCount++
        
        # Flush periodically
        if ($this.ItemCount % 1000 -eq 0) {
            $this.Writer.Flush()
        }
    }
    
    [int] Close([hashtable]$metadata = @{}) {
        if (-not $this.IsOpen) {
            return $this.ItemCount
        }
        
        # Close the array
        $this.Writer.WriteLine()
        $this.Writer.WriteLine("  ],")
        
        # Write metadata
        $this.Writer.WriteLine("  `"_meta`": {")
        $this.Writer.WriteLine("    `"count`": $($this.ItemCount),")
        $this.Writer.WriteLine("    `"generatedAt`": `"$((Get-Date).ToString('o'))`"")
        
        # Add custom metadata
        foreach ($key in $metadata.Keys) {
            $value = $metadata[$key]
            if ($value -is [string]) {
                $this.Writer.WriteLine("    ,`"$key`": `"$value`"")
            } elseif ($value -is [int] -or $value -is [long] -or $value -is [double]) {
                $this.Writer.WriteLine("    ,`"$key`": $value")
            } elseif ($value -is [bool]) {
                $boolStr = if ($value) { "true" } else { "false" }
                $this.Writer.WriteLine("    ,`"$key`": $boolStr")
            }
        }
        
        $this.Writer.WriteLine("  }")
        $this.Writer.WriteLine("}")
        
        $this.Writer.Flush()
        $this.Writer.Close()
        $this.Writer.Dispose()
        $this.IsOpen = $false
        
        return $this.ItemCount
    }
    
    [void] Dispose() {
        if ($this.IsOpen) {
            $this.Close()
        }
    }
}

function New-StreamingJsonWriter {
    <#
    .SYNOPSIS
        Create a new streaming JSON writer.
    
    .PARAMETER Path
        Output file path.
        
    .PARAMETER ArrayName
        Name of the root array property (default: "nodes").
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [string]$ArrayName = "nodes"
    )
    
    return [StreamingJsonWriter]::new($Path, $ArrayName)
}

function Write-NodesJsonStreaming {
    <#
    .SYNOPSIS
        Write nodes to JSON file using streaming approach.
    
    .DESCRIPTION
        Processes nodes one at a time, writing directly to disk
        to minimize memory usage for large trees.
    
    .PARAMETER Nodes
        Array or enumerable of node objects.
        
    .PARAMETER OutputPath
        Path to output JSON file.
        
    .PARAMETER GenerateIndex
        If true, also generates node_index.json.
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Nodes,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath,
        
        [switch]$GenerateIndex,
        
        [string]$IndexPath = ""
    )
    
    $writer = New-StreamingJsonWriter -Path $OutputPath -ArrayName "nodes"
    $writer.Open()
    
    $indexData = @{}
    $byteOffset = 0
    
    foreach ($node in $Nodes) {
        $nodeHash = @{
            id = $node.id
            name = $node.name
            parentId = $node.parentId
            level = $node.level
            typeId = $node.typeId
            className = $node.className
            niceName = $node.niceName
            children = @($node.children | ForEach-Object { $_.id })
        }
        
        if ($GenerateIndex) {
            $indexData[$node.id] = @{
                offset = $byteOffset
                name = $node.name
                level = $node.level
            }
        }
        
        $writer.WriteNode($nodeHash)
        $byteOffset += 100  # Approximate line length
    }
    
    $count = $writer.Close(@{ streaming = $true })
    
    # Write index file if requested
    if ($GenerateIndex) {
        $actualIndexPath = if ($IndexPath) { $IndexPath } else { 
            $OutputPath -replace '\.json$', '_index.json' 
        }
        Write-NodeIndexJson -IndexData $indexData -OutputPath $actualIndexPath
    }
    
    return $count
}

function Write-NodeIndexJson {
    <#
    .SYNOPSIS
        Write node index file for fast lookups.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$IndexData,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    $indexJson = @{
        version = "1.0"
        count = $IndexData.Count
        generatedAt = (Get-Date).ToString("o")
        index = $IndexData
    } | ConvertTo-Json -Depth 4 -Compress
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($OutputPath, $indexJson, $utf8NoBom)
    
    Write-Host "[JSON] Wrote index to: $OutputPath ($($IndexData.Count) entries)" -ForegroundColor Cyan
}

function Write-PathIndexJson {
    <#
    .SYNOPSIS
        Write path index file for path-based lookups.
    #>
    param(
        [Parameter(Mandatory=$true)]
        $Nodes,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    $pathIndex = @{}
    $nodeMap = @{}
    
    # First pass: build node map
    foreach ($node in $Nodes) {
        $nodeMap[$node.id] = $node
    }
    
    # Second pass: build paths
    foreach ($node in $Nodes) {
        $path = @()
        $current = $node
        
        while ($current) {
            $path = @($current.name) + $path
            $current = if ($current.parentId -and $nodeMap[$current.parentId]) {
                $nodeMap[$current.parentId]
            } else {
                $null
            }
        }
        
        $fullPath = $path -join "/"
        $pathIndex[$fullPath] = $node.id
    }
    
    $indexJson = @{
        version = "1.0"
        count = $pathIndex.Count
        generatedAt = (Get-Date).ToString("o")
        paths = $pathIndex
    } | ConvertTo-Json -Depth 3 -Compress
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($OutputPath, $indexJson, $utf8NoBom)
    
    Write-Host "[JSON] Wrote path index to: $OutputPath ($($pathIndex.Count) paths)" -ForegroundColor Cyan
}

# Export functions
Export-ModuleMember -Function @(
    'New-StreamingJsonWriter',
    'Write-NodesJsonStreaming',
    'Write-NodeIndexJson',
    'Write-PathIndexJson'
)
