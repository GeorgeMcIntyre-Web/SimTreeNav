# CompressionUtils.ps1 - Optional gzip compression for large output files
# Supports: nodes.json, diff.json, actions.json, impact.json, drift.json

<#
.SYNOPSIS
    Compression utilities for large tree output files.
    
.DESCRIPTION
    Provides optional gzip compression for output files to reduce
    storage and transfer costs for large trees (50k+ nodes).
#>

function Compress-OutputFile {
    <#
    .SYNOPSIS
        Compress a file using gzip.
    
    .PARAMETER InputPath
        Path to the file to compress.
        
    .PARAMETER OutputPath
        Optional output path. Defaults to InputPath + ".gz"
        
    .PARAMETER DeleteOriginal
        If true, deletes the original file after compression.
        
    .PARAMETER CompressionLevel
        Compression level: Optimal, Fastest, NoCompression
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPath,
        
        [string]$OutputPath = "",
        
        [switch]$DeleteOriginal,
        
        [ValidateSet("Optimal", "Fastest", "NoCompression")]
        [string]$CompressionLevel = "Optimal"
    )
    
    if (-not (Test-Path $InputPath)) {
        throw "Input file not found: $InputPath"
    }
    
    $actualOutputPath = if ($OutputPath) { $OutputPath } else { "$InputPath.gz" }
    
    $inputFile = Get-Item $InputPath
    $originalSize = $inputFile.Length
    
    Write-Host "[GZIP] Compressing: $InputPath" -ForegroundColor Cyan
    
    try {
        $inputStream = [System.IO.File]::OpenRead($InputPath)
        $outputStream = [System.IO.File]::Create($actualOutputPath)
        
        $level = switch ($CompressionLevel) {
            "Optimal" { [System.IO.Compression.CompressionLevel]::Optimal }
            "Fastest" { [System.IO.Compression.CompressionLevel]::Fastest }
            "NoCompression" { [System.IO.Compression.CompressionLevel]::NoCompression }
        }
        
        $gzipStream = [System.IO.Compression.GZipStream]::new(
            $outputStream, 
            $level,
            $false
        )
        
        $inputStream.CopyTo($gzipStream)
        
        $gzipStream.Close()
        $outputStream.Close()
        $inputStream.Close()
        
        $compressedFile = Get-Item $actualOutputPath
        $compressedSize = $compressedFile.Length
        $ratio = [math]::Round(($compressedSize / $originalSize) * 100, 1)
        $savedMB = [math]::Round(($originalSize - $compressedSize) / 1MB, 2)
        
        Write-Host "[GZIP] Compressed: $([math]::Round($originalSize / 1MB, 2))MB -> $([math]::Round($compressedSize / 1MB, 2))MB ($ratio%, saved ${savedMB}MB)" -ForegroundColor Green
        
        if ($DeleteOriginal) {
            Remove-Item $InputPath -Force
            Write-Host "[GZIP] Deleted original: $InputPath" -ForegroundColor Gray
        }
        
        return @{
            InputPath = $InputPath
            OutputPath = $actualOutputPath
            OriginalSizeBytes = $originalSize
            CompressedSizeBytes = $compressedSize
            CompressionRatio = $ratio
            SavedBytes = $originalSize - $compressedSize
        }
    }
    catch {
        Write-Error "Compression failed: $_"
        throw
    }
}

function Expand-OutputFile {
    <#
    .SYNOPSIS
        Decompress a gzip file.
    
    .PARAMETER InputPath
        Path to the .gz file to decompress.
        
    .PARAMETER OutputPath
        Optional output path. Defaults to InputPath without .gz extension.
        
    .PARAMETER DeleteCompressed
        If true, deletes the compressed file after expansion.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$InputPath,
        
        [string]$OutputPath = "",
        
        [switch]$DeleteCompressed
    )
    
    if (-not (Test-Path $InputPath)) {
        throw "Input file not found: $InputPath"
    }
    
    $actualOutputPath = if ($OutputPath) { $OutputPath } else { 
        $InputPath -replace '\.gz$', '' 
    }
    
    Write-Host "[GZIP] Decompressing: $InputPath" -ForegroundColor Cyan
    
    try {
        $inputStream = [System.IO.File]::OpenRead($InputPath)
        $gzipStream = [System.IO.Compression.GZipStream]::new(
            $inputStream,
            [System.IO.Compression.CompressionMode]::Decompress
        )
        $outputStream = [System.IO.File]::Create($actualOutputPath)
        
        $gzipStream.CopyTo($outputStream)
        
        $outputStream.Close()
        $gzipStream.Close()
        $inputStream.Close()
        
        $expandedFile = Get-Item $actualOutputPath
        Write-Host "[GZIP] Expanded to: $actualOutputPath ($([math]::Round($expandedFile.Length / 1MB, 2))MB)" -ForegroundColor Green
        
        if ($DeleteCompressed) {
            Remove-Item $InputPath -Force
            Write-Host "[GZIP] Deleted compressed: $InputPath" -ForegroundColor Gray
        }
        
        return $actualOutputPath
    }
    catch {
        Write-Error "Decompression failed: $_"
        throw
    }
}

function Compress-TreeOutputs {
    <#
    .SYNOPSIS
        Compress all tree output files in a directory.
    
    .PARAMETER OutputDir
        Directory containing output files.
        
    .PARAMETER FilePatterns
        Patterns of files to compress (default: nodes.json, diff.json, etc.)
        
    .PARAMETER DeleteOriginals
        If true, deletes original files after compression.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$OutputDir,
        
        [string[]]$FilePatterns = @(
            "nodes.json",
            "diff.json",
            "actions.json",
            "impact.json",
            "drift.json"
        ),
        
        [switch]$DeleteOriginals
    )
    
    if (-not (Test-Path $OutputDir)) {
        throw "Output directory not found: $OutputDir"
    }
    
    $results = @()
    
    foreach ($pattern in $FilePatterns) {
        $files = Get-ChildItem -Path $OutputDir -Filter $pattern -File
        
        foreach ($file in $files) {
            $result = Compress-OutputFile -InputPath $file.FullName -DeleteOriginal:$DeleteOriginals
            $results += $result
        }
    }
    
    $totalSaved = ($results | Measure-Object -Property SavedBytes -Sum).Sum
    $totalSavedMB = [math]::Round($totalSaved / 1MB, 2)
    
    Write-Host "`n[GZIP] Total space saved: ${totalSavedMB}MB across $($results.Count) files" -ForegroundColor Green
    
    return $results
}

function Test-GzipSupport {
    <#
    .SYNOPSIS
        Test if gzip compression is available.
    #>
    try {
        $testData = [System.Text.Encoding]::UTF8.GetBytes("test")
        $ms = [System.IO.MemoryStream]::new()
        $gz = [System.IO.Compression.GZipStream]::new($ms, [System.IO.Compression.CompressionMode]::Compress)
        $gz.Write($testData, 0, $testData.Length)
        $gz.Close()
        $ms.Close()
        return $true
    }
    catch {
        return $false
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Compress-OutputFile',
    'Expand-OutputFile',
    'Compress-TreeOutputs',
    'Test-GzipSupport'
)
