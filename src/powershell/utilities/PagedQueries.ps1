# PagedQueries.ps1 - Paging support for large database queries
# Enables extraction of very large trees without memory exhaustion

<#
.SYNOPSIS
    Paged query utilities for extracting large trees from Oracle databases.
    
.DESCRIPTION
    Provides paging support to extract large datasets in chunks,
    reducing memory usage and preventing timeouts.
#>

# Default page size for queries
$script:DefaultPageSize = 10000

function Get-PagedQueryTemplate {
    <#
    .SYNOPSIS
        Get a paged version of a query with ROWNUM bounds.
    
    .PARAMETER BaseQuery
        The base SQL query (without ORDER BY or paging).
        
    .PARAMETER OrderBy
        ORDER BY clause.
        
    .PARAMETER PageNumber
        Page number (0-based).
        
    .PARAMETER PageSize
        Number of rows per page.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$BaseQuery,
        
        [string]$OrderBy = "",
        
        [int]$PageNumber = 0,
        
        [int]$PageSize = 10000
    )
    
    $startRow = ($PageNumber * $PageSize) + 1
    $endRow = ($PageNumber + 1) * $PageSize
    
    $orderClause = if ($OrderBy) { "ORDER BY $OrderBy" } else { "" }
    
    $pagedQuery = @"
SELECT * FROM (
    SELECT a.*, ROWNUM rnum FROM (
        $BaseQuery
        $orderClause
    ) a
    WHERE ROWNUM <= $endRow
)
WHERE rnum >= $startRow
"@
    
    return $pagedQuery
}

function Invoke-PagedTreeQuery {
    <#
    .SYNOPSIS
        Execute a tree query with paging, returning results incrementally.
    
    .PARAMETER TNSName
        Oracle TNS name.
        
    .PARAMETER Schema
        Schema name.
        
    .PARAMETER ProjectId
        Project ID for tree root.
        
    .PARAMETER PageSize
        Rows per page (default: 10000).
        
    .PARAMETER MaxPages
        Maximum pages to fetch (0 = unlimited).
        
    .PARAMETER OutputFile
        Optional file to stream results to.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,
        
        [Parameter(Mandatory=$true)]
        [string]$Schema,
        
        [Parameter(Mandatory=$true)]
        [string]$ProjectId,
        
        [int]$PageSize = 10000,
        
        [int]$MaxPages = 0,
        
        [string]$OutputFile = ""
    )
    
    # Import credential manager if available
    $credManagerPath = Join-Path $PSScriptRoot "CredentialManager.ps1"
    if (Test-Path $credManagerPath) {
        Import-Module $credManagerPath -Force
    }
    
    $allResults = @()
    $pageNumber = 0
    $totalRows = 0
    $hasMore = $true
    
    # Open output file if specified
    $writer = $null
    if ($OutputFile) {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $writer = [System.IO.StreamWriter]::new($OutputFile, $false, $utf8NoBom, 65536)
    }
    
    try {
        while ($hasMore) {
            if ($MaxPages -gt 0 -and $pageNumber -ge $MaxPages) {
                Write-Host "[PAGED] Reached max pages limit: $MaxPages" -ForegroundColor Yellow
                break
            }
            
            $startRow = ($pageNumber * $PageSize) + 1
            $endRow = ($pageNumber + 1) * $PageSize
            
            Write-Host "[PAGED] Fetching page $($pageNumber + 1) (rows $startRow - $endRow)..." -ForegroundColor Cyan
            
            $pageQuery = Get-TreePageQuery -Schema $Schema -ProjectId $ProjectId -StartRow $startRow -EndRow $endRow
            
            $startTime = Get-Date
            $pageResults = Invoke-SqlPlusQuery -TNSName $TNSName -Query $pageQuery
            $duration = (Get-Date) - $startTime
            
            $rowCount = ($pageResults | Measure-Object).Count
            
            Write-Host "[PAGED] Page $($pageNumber + 1): $rowCount rows in $([math]::Round($duration.TotalMilliseconds, 0))ms" -ForegroundColor DarkCyan
            
            if ($rowCount -eq 0) {
                $hasMore = $false
            }
            else {
                $totalRows += $rowCount
                
                if ($writer) {
                    # Stream to file
                    foreach ($line in $pageResults) {
                        $writer.WriteLine($line)
                    }
                    $writer.Flush()
                }
                else {
                    # Collect in memory
                    $allResults += $pageResults
                }
                
                if ($rowCount -lt $PageSize) {
                    $hasMore = $false
                }
            }
            
            $pageNumber++
        }
    }
    finally {
        if ($writer) {
            $writer.Close()
            $writer.Dispose()
        }
    }
    
    Write-Host "[PAGED] Complete: $totalRows total rows in $pageNumber pages" -ForegroundColor Green
    
    return @{
        TotalRows = $totalRows
        PageCount = $pageNumber
        Results = if ($OutputFile) { @() } else { $allResults }
        OutputFile = $OutputFile
    }
}

function Get-TreePageQuery {
    <#
    .SYNOPSIS
        Generate a paged tree query for a specific row range.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$Schema,
        
        [Parameter(Mandatory=$true)]
        [string]$ProjectId,
        
        [int]$StartRow = 1,
        [int]$EndRow = 10000
    )
    
    # This query uses Oracle's hierarchical query with paging
    $query = @"
SET PAGESIZE 0
SET LINESIZE 500
SET FEEDBACK OFF
SET HEADING OFF

SELECT * FROM (
    SELECT a.*, ROWNUM rnum FROM (
        SELECT
            LEVEL || '|' ||
            PRIOR c.OBJECT_ID || '|' ||
            c.OBJECT_ID || '|' ||
            NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
            NVL(c.CAPTION_S_, 'Unnamed') || '|' ||
            NVL(c.EXTERNALID_S_, '') || '|' ||
            TO_CHAR(r.SEQ_NUMBER) || '|' ||
            NVL(cd.NAME, 'class PmNode') || '|' ||
            NVL(cd.NICE_NAME, 'Unknown') || '|' ||
            TO_CHAR(cd.TYPE_ID) AS DATA_LINE
        FROM $Schema.REL_COMMON r
        INNER JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
        LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
        START WITH r.FORWARD_OBJECT_ID = $ProjectId
        CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
        ORDER SIBLINGS BY NVL(c.MODIFICATIONDATE_DA_, TO_DATE('1900-01-01', 'YYYY-MM-DD')), c.OBJECT_ID
    ) a
    WHERE ROWNUM <= $EndRow
)
WHERE rnum >= $StartRow;

EXIT;
"@
    
    return $query
}

function Invoke-SqlPlusQuery {
    <#
    .SYNOPSIS
        Execute a SQL query using SQL*Plus and return results.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,
        
        [Parameter(Mandatory=$true)]
        [string]$Query
    )
    
    $tempSqlFile = Join-Path $env:TEMP "paged_query_$(Get-Random).sql"
    
    try {
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($tempSqlFile, $Query, $utf8NoBom)
        
        $env:NLS_LANG = "AMERICAN_AMERICA.UTF8"
        
        # Get connection string
        try {
            $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
        }
        catch {
            $connectionString = "sys/change_on_install@$TNSName AS SYSDBA"
        }
        
        $result = sqlplus -S $connectionString "@$tempSqlFile" 2>&1
        
        # Filter to data lines only
        $dataLines = $result -split "`r?`n" | Where-Object { 
            $_ -match '^\d+\|' -and 
            $_ -notmatch 'ERROR' -and 
            $_ -notmatch 'SP2'
        }
        
        return $dataLines
    }
    finally {
        if (Test-Path $tempSqlFile) {
            Remove-Item $tempSqlFile -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-EstimatedRowCount {
    <#
    .SYNOPSIS
        Get estimated row count for a tree without fetching all data.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,
        
        [Parameter(Mandatory=$true)]
        [string]$Schema,
        
        [Parameter(Mandatory=$true)]
        [string]$ProjectId
    )
    
    $countQuery = @"
SET PAGESIZE 0
SET LINESIZE 100
SET FEEDBACK OFF
SET HEADING OFF

SELECT COUNT(*) FROM (
    SELECT c.OBJECT_ID
    FROM $Schema.REL_COMMON r
    INNER JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
    START WITH r.FORWARD_OBJECT_ID = $ProjectId
    CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
);

EXIT;
"@
    
    $result = Invoke-SqlPlusQuery -TNSName $TNSName -Query $countQuery
    $count = ($result | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1)
    
    return [int]$count
}

# Export functions
Export-ModuleMember -Function @(
    'Get-PagedQueryTemplate',
    'Invoke-PagedTreeQuery',
    'Get-TreePageQuery',
    'Invoke-SqlPlusQuery',
    'Get-EstimatedRowCount'
)
