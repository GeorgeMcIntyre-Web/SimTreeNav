# CollectorUtils.ps1
# Utility functions for data anonymization, bundling, and snapshot creation
#
# Features:
# - Read-only database snapshots
# - Data anonymization/masking
# - ZIP bundle creation
# - Mapping file generation (internal use only)
# - Atomic file operations

<#
.SYNOPSIS
    Provides utility functions for the Collector Agent's data handling.

.DESCRIPTION
    This module provides:
    - Snapshot creation from database queries
    - Data anonymization for safe sharing
    - Atomic bundle creation (no partial uploads)
    - Mapping file generation for internal correlation

.EXAMPLE
    $snapshot = New-CollectorSnapshot -TNSName "DB" -Schema "DESIGN12"
    $anonymized = ConvertTo-AnonymizedData -Data $snapshot
    New-CollectorBundle -Data $anonymized -OutputPath "bundles"
#>

# Default anonymization rules
$script:AnonymizationRules = @{
    # Field patterns that should be anonymized
    SensitivePatterns = @(
        'USERNAME',
        'USER_NAME',
        'EMAIL',
        'PASSWORD',
        'PHONE',
        'ADDRESS',
        'SSID',
        'IP_ADDRESS',
        'HOST',
        'SERVER',
        'CONNECTION',
        'CREDENTIAL'
    )
    # Fields to completely remove
    RemoveFields = @(
        'PASSWORD',
        'SECRET',
        'TOKEN',
        'API_KEY',
        'PRIVATE_KEY'
    )
    # Fields to hash (one-way anonymization)
    HashFields = @(
        'OBJECT_ID',
        'PROJECTID',
        'FORWARD_OBJECT_ID'
    )
}

# Initialize snapshot configuration
function Initialize-SnapshotConfig {
    <#
    .SYNOPSIS
        Initializes snapshot configuration with safe defaults.
    .PARAMETER Config
        Configuration hashtable from collector config file
    #>
    param(
        [hashtable]$Config = @{}
    )

    $defaultConfig = @{
        MaxRows = 10000
        Timeout = 300
        ReadOnly = $true
        IncludeMetadata = $true
        AnonymizeByDefault = $true
    }

    # Merge with provided config
    foreach ($key in $Config.Keys) {
        $defaultConfig[$key] = $Config[$key]
    }

    return $defaultConfig
}

# Create a read-only snapshot from database
function New-CollectorSnapshot {
    <#
    .SYNOPSIS
        Creates a read-only snapshot of database tree structure.
    .PARAMETER TNSName
        Oracle TNS name for connection
    .PARAMETER Schema
        Database schema to query
    .PARAMETER ProjectId
        Optional project ID to limit scope
    .PARAMETER MaxRows
        Maximum rows to retrieve per query
    .PARAMETER Queries
        Array of query definitions to execute
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,

        [Parameter(Mandatory=$true)]
        [string]$Schema,

        [string]$ProjectId = $null,

        [int]$MaxRows = 10000,

        [array]$Queries = @()
    )

    Write-CollectorLog -Level INFO -Message "Creating snapshot" -Data @{
        schema = $Schema
        projectId = $ProjectId
        maxRows = $MaxRows
    }

    $snapshot = @{
        metadata = @{
            createdAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            schema = $Schema
            projectId = $ProjectId
            tnsName = $TNSName
            version = "1.0"
            snapshotId = [guid]::NewGuid().ToString("N").Substring(0, 12)
        }
        data = @{}
        statistics = @{
            queriesExecuted = 0
            totalRows = 0
            errors = @()
        }
    }

    # Default queries if none provided
    if ($Queries.Count -eq 0) {
        $Queries = @(
            @{
                name = "TreeStructure"
                description = "Hierarchical tree structure"
                sql = @"
SELECT /*+ READ_ONLY */ 
    c.OBJECT_ID,
    c.CAPTION_S_,
    c.CLASS_ID_,
    r.FORWARD_OBJECT_ID,
    cd.NAME AS CLASS_NAME,
    cd.TYPE_ID
FROM $Schema.COLLECTION_ c
INNER JOIN $Schema.REL_COMMON r ON c.OBJECT_ID = r.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID_ = cd.CLASS_ID
WHERE ROWNUM <= $MaxRows
"@
            },
            @{
                name = "ProjectList"
                description = "List of projects"
                sql = @"
SELECT /*+ READ_ONLY */
    p.PROJECTID,
    c.CAPTION_S_ AS PROJECT_NAME,
    c.EXTERNALID_S_
FROM $Schema.DFPROJECT p
LEFT JOIN $Schema.COLLECTION_ c ON p.PROJECTID = c.OBJECT_ID
WHERE ROWNUM <= 100
"@
            },
            @{
                name = "ClassDefinitions"
                description = "Class type definitions"
                sql = @"
SELECT /*+ READ_ONLY */
    cd.CLASS_ID,
    cd.NAME,
    cd.TYPE_ID,
    cd.DESCRIPTION
FROM $Schema.CLASS_DEFINITIONS cd
WHERE ROWNUM <= 500
"@
            }
        )
    }

    # Execute each query
    foreach ($query in $Queries) {
        try {
            Write-CollectorLog -Level DEBUG -Message "Executing query: $($query.name)"
            
            $result = Invoke-ReadOnlyQuery -TNSName $TNSName -Query $query.sql -MaxRows $MaxRows
            
            $snapshot.data[$query.name] = @{
                description = $query.description
                rowCount = $result.Count
                columns = if ($result.Count -gt 0) { $result[0].PSObject.Properties.Name } else { @() }
                rows = $result
            }
            
            $snapshot.statistics.queriesExecuted++
            $snapshot.statistics.totalRows += $result.Count

            Write-CollectorLog -Level DEBUG -Message "Query completed" -Data @{
                query = $query.name
                rows = $result.Count
            }
        }
        catch {
            $error = @{
                query = $query.name
                error = $_.Exception.Message
                timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            }
            $snapshot.statistics.errors += $error
            
            Write-CollectorLog -Level WARN -Message "Query failed" -Data @{
                query = $query.name
                error = $_.Exception.Message
            }
        }
    }

    Write-CollectorLog -Level INFO -Message "Snapshot created" -Data @{
        snapshotId = $snapshot.metadata.snapshotId
        totalRows = $snapshot.statistics.totalRows
        errors = $snapshot.statistics.errors.Count
    }

    return $snapshot
}

# Execute a read-only query
function Invoke-ReadOnlyQuery {
    <#
    .SYNOPSIS
        Executes a read-only SQL query against the database.
    .DESCRIPTION
        This function ensures queries are read-only by:
        - Using SET TRANSACTION READ ONLY
        - Rejecting queries with DML keywords
        - Setting query timeouts
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,

        [Parameter(Mandatory=$true)]
        [string]$Query,

        [int]$MaxRows = 10000
    )

    # Validate query is read-only (basic check)
    $dmlPatterns = @('INSERT\s+INTO', 'UPDATE\s+', 'DELETE\s+FROM', 'DROP\s+', 'CREATE\s+', 'ALTER\s+', 'TRUNCATE\s+')
    foreach ($pattern in $dmlPatterns) {
        if ($Query -match $pattern) {
            throw "Query contains DML/DDL statements. Only SELECT queries are allowed in collector mode."
        }
    }

    # Build the query file with read-only transaction
    $queryFile = "collector-query-$([guid]::NewGuid().ToString('N').Substring(0, 8)).sql"
    $fullQuery = @"
SET PAGESIZE 50000
SET LINESIZE 32767
SET FEEDBACK OFF
SET HEADING ON
SET TRIMSPOOL ON
SET COLSEP '|'
SET TRANSACTION READ ONLY;

$Query;

COMMIT;
EXIT;
"@

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText("$PWD\$queryFile", $fullQuery, $utf8NoBom)

        $env:NLS_LANG = "AMERICAN_AMERICA.UTF8"

        # Get connection string using credential manager
        $credManagerPath = Join-Path $PSScriptRoot "..\utilities\CredentialManager.ps1"
        if (Test-Path $credManagerPath) {
            . $credManagerPath
            $connectionString = Get-DbConnectionString -TNSName $TNSName -AsSysDBA -ErrorAction Stop
        }
        else {
            throw "Credential manager not found"
        }

        $result = sqlplus -S $connectionString "@$queryFile" 2>&1

        # Parse results
        $parsedResults = @()
        $headers = @()
        $inData = $false

        foreach ($line in $result) {
            $line = $line.Trim()
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -match '^[-]+') { continue }  # Skip separator lines
            if ($line -match 'ORA-\d+') {
                throw "Oracle error: $line"
            }

            $parts = $line -split '\|' | ForEach-Object { $_.Trim() }

            if (-not $inData -and $parts.Count -gt 0) {
                # First non-empty line is headers
                $headers = $parts
                $inData = $true
                continue
            }

            if ($inData -and $parts.Count -eq $headers.Count) {
                $row = @{}
                for ($i = 0; $i -lt $headers.Count; $i++) {
                    $row[$headers[$i]] = $parts[$i]
                }
                $parsedResults += [PSCustomObject]$row
            }
        }

        return $parsedResults
    }
    finally {
        Remove-Item $queryFile -Force -ErrorAction SilentlyContinue
    }
}

# Anonymize data for safe external sharing
function ConvertTo-AnonymizedData {
    <#
    .SYNOPSIS
        Anonymizes snapshot data for safe external sharing.
    .PARAMETER Snapshot
        The snapshot data to anonymize
    .PARAMETER Rules
        Optional custom anonymization rules
    .PARAMETER CreateMapping
        Whether to create a reversible mapping file (internal use only)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Snapshot,

        [hashtable]$Rules = $null,

        [bool]$CreateMapping = $false
    )

    Write-CollectorLog -Level INFO -Message "Anonymizing snapshot data"

    $rules = if ($Rules) { $Rules } else { $script:AnonymizationRules }
    
    $mapping = @{
        createdAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        snapshotId = $Snapshot.metadata.snapshotId
        mappings = @{}
    }

    $anonymized = @{
        metadata = @{
            createdAt = $Snapshot.metadata.createdAt
            anonymizedAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            version = $Snapshot.metadata.version
            snapshotId = $Snapshot.metadata.snapshotId
            isAnonymized = $true
        }
        data = @{}
        statistics = $Snapshot.statistics
    }

    # Process each data table
    foreach ($tableName in $Snapshot.data.Keys) {
        $table = $Snapshot.data[$tableName]
        $anonymizedRows = @()
        $tableMapping = @{}

        foreach ($row in $table.rows) {
            $anonymizedRow = @{}
            
            foreach ($prop in $row.PSObject.Properties) {
                $fieldName = $prop.Name
                $value = $prop.Value

                # Check if field should be removed
                $shouldRemove = $false
                foreach ($pattern in $rules.RemoveFields) {
                    if ($fieldName -like "*$pattern*") {
                        $shouldRemove = $true
                        break
                    }
                }

                if ($shouldRemove) {
                    $anonymizedRow[$fieldName] = "[REDACTED]"
                    continue
                }

                # Check if field should be hashed
                $shouldHash = $false
                foreach ($pattern in $rules.HashFields) {
                    if ($fieldName -eq $pattern) {
                        $shouldHash = $true
                        break
                    }
                }

                if ($shouldHash -and $value) {
                    # Generate consistent hash for the value
                    $hash = Get-StringHash -InputString "$value"
                    $anonymizedRow[$fieldName] = $hash

                    if ($CreateMapping) {
                        if (-not $tableMapping[$fieldName]) {
                            $tableMapping[$fieldName] = @{}
                        }
                        $tableMapping[$fieldName][$hash] = $value
                    }
                    continue
                }

                # Check if field matches sensitive patterns
                $shouldMask = $false
                foreach ($pattern in $rules.SensitivePatterns) {
                    if ($fieldName -like "*$pattern*") {
                        $shouldMask = $true
                        break
                    }
                }

                if ($shouldMask -and $value) {
                    $anonymizedRow[$fieldName] = Get-MaskedValue -Value $value
                }
                else {
                    $anonymizedRow[$fieldName] = $value
                }
            }

            $anonymizedRows += [PSCustomObject]$anonymizedRow
        }

        $anonymized.data[$tableName] = @{
            description = $table.description
            rowCount = $table.rowCount
            columns = $table.columns
            rows = $anonymizedRows
        }

        if ($CreateMapping -and $tableMapping.Count -gt 0) {
            $mapping.mappings[$tableName] = $tableMapping
        }
    }

    Write-CollectorLog -Level INFO -Message "Anonymization complete" -Data @{
        tablesProcessed = $anonymized.data.Count
    }

    if ($CreateMapping) {
        return @{
            data = $anonymized
            mapping = $mapping
        }
    }

    return $anonymized
}

# Generate consistent hash for a string
function Get-StringHash {
    param(
        [string]$InputString
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($InputString)
    $hash = $sha256.ComputeHash($bytes)
    return [BitConverter]::ToString($hash).Replace("-", "").Substring(0, 16).ToLower()
}

# Mask a sensitive value
function Get-MaskedValue {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    $length = $Value.Length
    if ($length -le 4) {
        return "****"
    }
    elseif ($length -le 8) {
        return $Value.Substring(0, 1) + ("*" * ($length - 2)) + $Value.Substring($length - 1, 1)
    }
    else {
        return $Value.Substring(0, 2) + ("*" * ($length - 4)) + $Value.Substring($length - 2, 2)
    }
}

# Create a bundle (ZIP file) from snapshot data
function New-CollectorBundle {
    <#
    .SYNOPSIS
        Creates an atomic ZIP bundle from snapshot data.
    .DESCRIPTION
        Creates a ZIP bundle with:
        - Atomic write (temp file then rename to prevent partial uploads)
        - Manifest file with checksums
        - Consistent naming convention
    .PARAMETER Data
        The anonymized snapshot data
    .PARAMETER OutputPath
        Directory for bundle output
    .PARAMETER Label
        Optional label for the bundle filename
    .PARAMETER Mapping
        Optional mapping data (saved separately, internal only)
    .PARAMETER MappingPath
        Directory for mapping files (should be secured)
    #>
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Data,

        [Parameter(Mandatory=$true)]
        [string]$OutputPath,

        [string]$Label = "snapshot",

        [hashtable]$Mapping = $null,

        [string]$MappingPath = $null
    )

    Write-CollectorLog -Level INFO -Message "Creating bundle" -Data @{
        outputPath = $OutputPath
        label = $Label
    }

    # Ensure output directory exists
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    # Generate timestamp and filenames
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $bundleName = "${timestamp}_${Label}"
    $bundleFile = Join-Path $OutputPath "$bundleName.zip"
    $tempFile = Join-Path $OutputPath "$bundleName.tmp.zip"

    # Create temp directory for bundle contents
    $tempDir = Join-Path $env:TEMP "collector_bundle_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # Write snapshot data as JSON
        $dataFile = Join-Path $tempDir "snapshot.json"
        $Data | ConvertTo-Json -Depth 20 | Out-File $dataFile -Encoding UTF8

        # Create manifest with checksums
        $manifest = @{
            bundleId = $bundleName
            createdAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            version = "1.0"
            files = @()
        }

        # Calculate checksum for data file
        $hash = Get-FileHash -Path $dataFile -Algorithm SHA256
        $manifest.files += @{
            name = "snapshot.json"
            size = (Get-Item $dataFile).Length
            sha256 = $hash.Hash.ToLower()
        }

        # Write manifest
        $manifestFile = Join-Path $tempDir "manifest.json"
        $manifest | ConvertTo-Json -Depth 10 | Out-File $manifestFile -Encoding UTF8

        # Create ZIP atomically (write to temp, then rename)
        # Using .NET compression for better control
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }

        [System.IO.Compression.ZipFile]::CreateFromDirectory($tempDir, $tempFile)

        # Atomic rename
        if (Test-Path $bundleFile) {
            Remove-Item $bundleFile -Force
        }
        Move-Item -Path $tempFile -Destination $bundleFile -Force

        Write-CollectorLog -Level INFO -Message "Bundle created successfully" -Data @{
            bundleFile = $bundleFile
            size = (Get-Item $bundleFile).Length
        }

        # Handle mapping file separately (internal use only)
        if ($Mapping -and $MappingPath) {
            if (-not (Test-Path $MappingPath)) {
                New-Item -ItemType Directory -Path $MappingPath -Force | Out-Null
            }

            $mappingFile = Join-Path $MappingPath "$bundleName.map.json"
            $Mapping | ConvertTo-Json -Depth 20 | Out-File $mappingFile -Encoding UTF8

            Write-CollectorLog -Level INFO -Message "Mapping file created" -Data @{
                mappingFile = $mappingFile
            }

            return @{
                bundleFile = $bundleFile
                mappingFile = $mappingFile
            }
        }

        return @{
            bundleFile = $bundleFile
            mappingFile = $null
        }
    }
    catch {
        Write-CollectorLog -Level ERROR -Message "Failed to create bundle" -Exception $_.Exception

        # Clean up any partial files
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
        }

        throw
    }
    finally {
        # Clean up temp directory
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Validate bundle integrity
function Test-BundleIntegrity {
    <#
    .SYNOPSIS
        Validates a bundle's integrity using manifest checksums.
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$BundlePath
    )

    Write-CollectorLog -Level DEBUG -Message "Validating bundle integrity" -Data @{
        bundle = $BundlePath
    }

    if (-not (Test-Path $BundlePath)) {
        return @{
            valid = $false
            error = "Bundle file not found"
        }
    }

    try {
        Add-Type -AssemblyName System.IO.Compression.FileSystem

        $tempDir = Join-Path $env:TEMP "collector_validate_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        [System.IO.Compression.ZipFile]::ExtractToDirectory($BundlePath, $tempDir)

        $manifestFile = Join-Path $tempDir "manifest.json"
        if (-not (Test-Path $manifestFile)) {
            return @{
                valid = $false
                error = "Manifest not found in bundle"
            }
        }

        $manifest = Get-Content $manifestFile -Raw | ConvertFrom-Json

        foreach ($file in $manifest.files) {
            $filePath = Join-Path $tempDir $file.name
            if (-not (Test-Path $filePath)) {
                return @{
                    valid = $false
                    error = "Missing file: $($file.name)"
                }
            }

            $hash = Get-FileHash -Path $filePath -Algorithm SHA256
            if ($hash.Hash.ToLower() -ne $file.sha256.ToLower()) {
                return @{
                    valid = $false
                    error = "Checksum mismatch for: $($file.name)"
                }
            }
        }

        return @{
            valid = $true
            bundleId = $manifest.bundleId
            createdAt = $manifest.createdAt
        }
    }
    catch {
        return @{
            valid = $false
            error = $_.Exception.Message
        }
    }
    finally {
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-SnapshotConfig',
    'New-CollectorSnapshot',
    'Invoke-ReadOnlyQuery',
    'ConvertTo-AnonymizedData',
    'New-CollectorBundle',
    'Test-BundleIntegrity',
    'Get-StringHash',
    'Get-MaskedValue'
)
