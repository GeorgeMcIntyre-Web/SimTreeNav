# Get Management Reporting Data (Optimized)
# Purpose: Query database for all management reporting data across 5 work types
# Date: 2026-02-02
# Optimizations: DatabaseHelper, Parallelization, Caching, Performance Tracking

param(
    [Parameter(Mandatory=$false)]
    [string]$TNSName,

    [Parameter(Mandatory=$false)]
    [string]$Schema,

    [Parameter(Mandatory=$false)]
    [int]$ProjectId = 0,

    [DateTime]$StartDate = (Get-Date).AddDays(-7),
    [DateTime]$EndDate = (Get-Date),

    [string]$OutputFile,

    [switch]$ForceRefresh,

    [switch]$SkipTreeSnapshots,

    [int]$TreeSnapshotLimit = 25,

    [int]$TreeSnapshotErrorLimit = 5
)

# Start timer
$scriptTimer = [System.Diagnostics.Stopwatch]::StartNew()

# Load enterprise configuration for defaults
# Get project root (3 levels up from main/)
$scriptRootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$enterpriseConfigPath = Join-Path $scriptRootDir "config\enterprise-config.json"

if (Test-Path $enterpriseConfigPath) {
    $enterpriseConfig = Get-Content $enterpriseConfigPath -Raw | ConvertFrom-Json

    # Apply defaults if not specified
    if ([string]::IsNullOrWhiteSpace($TNSName)) {
        $TNSName = $enterpriseConfig.defaults.tnsName
    }

    if ([string]::IsNullOrWhiteSpace($Schema)) {
        $Schema = $enterpriseConfig.defaults.schema
    }

    if ($ProjectId -eq 0) {
        $ProjectId = $enterpriseConfig.defaults.projectId
    }
} else {
    # Fallback hardcoded defaults if config not found
    if ([string]::IsNullOrWhiteSpace($TNSName)) { $TNSName = "PSPDV3" }
    if ([string]::IsNullOrWhiteSpace($Schema)) { $Schema = "DESIGN12" }
    if ($ProjectId -eq 0) { $ProjectId = 18851221 }
    Write-Warning "Enterprise config not found: $enterpriseConfigPath - using hardcoded defaults"
}

# Set output file if not specified
if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = "management-data-${Schema}-${ProjectId}.json"
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Management Reporting Data Collection" -ForegroundColor Cyan
Write-Host "  (Optimized with DatabaseHelper)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  TNS:        $TNSName" -ForegroundColor Gray
Write-Host "  Schema:     $Schema" -ForegroundColor Gray
Write-Host "  Project ID: $ProjectId" -ForegroundColor Gray
Write-Host "  Date Range: $($StartDate.ToString('yyyy-MM-dd')) to $($EndDate.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
Write-Host "  Cache:      $(if ($ForceRefresh) { 'Bypassed (Force Refresh)' } else { 'Enabled' })" -ForegroundColor Gray
Write-Host ""

# Import DatabaseHelper
$dbHelperPath = Join-Path $PSScriptRoot "..\utilities\DatabaseHelper.ps1"
if (-not (Test-Path $dbHelperPath)) {
    Write-Error "DatabaseHelper.ps1 not found at: $dbHelperPath"
    exit 1
}
Import-Module $dbHelperPath -Force

# Import credential manager
$credManagerPath = Join-Path $PSScriptRoot "..\utilities\CredentialManager.ps1"
if (Test-Path $credManagerPath) {
    Import-Module $credManagerPath -Force
} else {
    Write-Warning "Credential manager not found. Using default password."
}

# SQL*Plus helper (optional fallback for tree scope counts)
$sqlHelperPath = Join-Path $PSScriptRoot "..\utilities\SqlPlusHelper-Simple.ps1"
if (Test-Path $sqlHelperPath) {
    . $sqlHelperPath
}

# Import evidence and snapshot libraries
$evidenceLibPath = Join-Path $PSScriptRoot "..\..\..\scripts\lib\EvidenceClassifier.ps1"
if (Test-Path $evidenceLibPath) {
    . $evidenceLibPath
} else {
    Write-Warning "Evidence classifier not found: $evidenceLibPath"
}

$treeEvidenceLibPath = Join-Path $PSScriptRoot "..\utilities\TreeEvidenceClassifier.ps1"
if (Test-Path $treeEvidenceLibPath) {
    . $treeEvidenceLibPath
} else {
    Write-Warning "Tree evidence classifier not found: $treeEvidenceLibPath"
}

$snapshotLibPath = Join-Path $PSScriptRoot "..\..\..\scripts\lib\SnapshotManager.ps1"
if (Test-Path $snapshotLibPath) {
    . $snapshotLibPath
} else {
    Write-Warning "Snapshot manager not found: $snapshotLibPath"
}

$enrichmentLibPath = Join-Path $PSScriptRoot "..\..\..\scripts\lib\WorkflowEnrichment.ps1"
if (Test-Path $enrichmentLibPath) {
    . $enrichmentLibPath
} else {
    Write-Warning "Workflow enrichment library not found: $enrichmentLibPath"
}

# Format dates for SQL
$startDateStr = $StartDate.ToString('yyyy-MM-dd')
$endDateStr = $EndDate.ToString('yyyy-MM-dd')

# Get server configuration for metadata
$serverConfig = Get-OracleServerConfig -ServerName $TNSName
$serverDescription = if ($serverConfig) { $serverConfig.description } else { "Unknown" }

# Initialize results object
$results = @{
    metadata = @{
        schemaVersion = "1.3.0"
        schema = $Schema
        projectId = $ProjectId
        startDate = $startDateStr
        endDate = $endDateStr
        generatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        tnsName = $TNSName
        serverDescription = $serverDescription
        cacheEnabled = (-not $ForceRefresh)
    }
    projectDatabase = @()
    resourceLibrary = @()
    partLibrary = @()
    ipaAssembly = @()
    studySummary = @()
    studyResources = @()
    studyPanels = @()
    studyOperations = @()
    studyMovements = @()
    studyWelds = @()
    userActivity = @()
    events = @()
    treeChanges = @()
    workTypeSummaryMeta = @{}
    studyHealth = @{
        summary = @{
            totalStudies = 0
            totalIssues = 0
            criticalIssues = 0
            highIssues = 0
            mediumIssues = 0
            lowIssues = 0
        }
        issues = @()
        suspicious = @()
        renameSuggestions = @()
    }
    resourceConflicts = @()
    staleCheckouts = @()
    bottleneckQueue = @()
    performance = @{
        totalTime = 0
        queryTimes = @{}
    }
}

# ========================================
# Cache Configuration and Functions
# ========================================

$cacheBaseDir = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))) "cache"
if (-not (Test-Path $cacheBaseDir)) {
    New-Item -ItemType Directory -Path $cacheBaseDir -Force | Out-Null
}

function Get-CacheFilePath {
    param(
        [string]$QueryName,
        [string]$Schema,
        [int]$ProjectId
    )
    $cacheFile = "$QueryName-$Schema-$ProjectId.json"
    return Join-Path $cacheBaseDir $cacheFile
}

function Test-CacheValid {
    param(
        [string]$CachePath,
        [int]$TTLHours
    )

    if (-not (Test-Path $CachePath)) {
        return $false
    }

    $fileInfo = Get-Item $CachePath
    $age = (Get-Date) - $fileInfo.LastWriteTime

    return ($age.TotalHours -lt $TTLHours)
}

function Get-CachedData {
    param(
        [string]$QueryName,
        [int]$TTLHours
    )

    if ($ForceRefresh) {
        return $null
    }

    $cachePath = Get-CacheFilePath -QueryName $QueryName -Schema $Schema -ProjectId $ProjectId

    if (Test-CacheValid -CachePath $cachePath -TTLHours $TTLHours) {
        Write-Host "    Using cached data (age: $([math]::Round(((Get-Date) - (Get-Item $cachePath).LastWriteTime).TotalHours, 1))h)" -ForegroundColor DarkGreen
        $content = Get-Content $cachePath -Raw | ConvertFrom-Json
        return @($content)
    }

    return $null
}

function Set-CachedData {
    param(
        [string]$QueryName,
        [object[]]$Data
    )

    $cachePath = Get-CacheFilePath -QueryName $QueryName -Schema $Schema -ProjectId $ProjectId
    $Data | ConvertTo-Json -Depth 5 | Out-File $cachePath -Encoding UTF8 -Force
}

# ========================================
# Helper Functions
# ========================================

function Convert-StringToDateTime {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [datetime]::MinValue
    }

    $parsed = [datetime]::MinValue
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $styles = [System.Globalization.DateTimeStyles]::AssumeLocal

    if ([datetime]::TryParseExact($Value, 'yyyy-MM-dd HH:mm:ss', $culture, $styles, [ref]$parsed)) {
        return $parsed
    }

    if ([datetime]::TryParse($Value, $culture, $styles, [ref]$parsed)) {
        return $parsed
    }

    return [datetime]::MinValue
}

function Test-DateInRange {
    param(
        [datetime]$Value,
        [datetime]$Start,
        [datetime]$End
    )

    if ($Value -eq [datetime]::MinValue) {
        return $false
    }

    return ($Value -ge $Start -and $Value -le $End)
}

function New-SnapshotEvidence {
    param(
        [hashtable]$SnapshotComparison
    )

    if (-not $SnapshotComparison) {
        return $null
    }

    return @{
        hasWrite = $SnapshotComparison.hasWrite
        hasDelta = $SnapshotComparison.hasDelta
        changes = $SnapshotComparison.changes
    }
}

function New-DefaultEvidence {
    return @{
        hasCheckout = $false
        hasWrite = $false
        hasDelta = $false
        attributionStrength = "weak"
        confidence = "unattributed"
    }
}

function Ensure-EvidenceBlock {
    param(
        [hashtable]$Evidence
    )

    if (-not $Evidence) {
        return New-DefaultEvidence
    }

    $defaultEvidence = New-DefaultEvidence
    foreach ($key in $defaultEvidence.Keys) {
        if (-not $Evidence.ContainsKey($key)) {
            $Evidence[$key] = $defaultEvidence[$key]
        }
    }

    return $Evidence
}

if (-not (Get-Command -Name New-CoordinateDeltaSummary -ErrorAction SilentlyContinue)) {
    function New-CoordinateDeltaSummary {
        param(
            [hashtable]$NewRecord,
            [hashtable]$PreviousRecord
        )

        if (-not $NewRecord -or -not $PreviousRecord) {
            return $null
        }

        if (-not $NewRecord.coordinates -or -not $PreviousRecord.coordinates) {
            return $null
        }

        $dx = [Math]::Round(($NewRecord.coordinates.x - $PreviousRecord.coordinates.x), 2)
        $dy = [Math]::Round(($NewRecord.coordinates.y - $PreviousRecord.coordinates.y), 2)
        $dz = [Math]::Round(($NewRecord.coordinates.z - $PreviousRecord.coordinates.z), 2)

        $maxDelta = [Math]::Max([Math]::Max([Math]::Abs($dx), [Math]::Abs($dy)), [Math]::Abs($dz))

        return @{
            kind = "movement"
            fields = @("x", "y", "z")
            maxAbsDelta = $maxDelta
            before = $PreviousRecord.coordinates
            after = $NewRecord.coordinates
            delta = @{ x = $dx; y = $dy; z = $dz }
        }
    }
}

if (-not (Get-Command -Name New-AllocationDeltaSummary -ErrorAction SilentlyContinue)) {
    function New-AllocationDeltaSummary {
        param(
            [hashtable]$SnapshotComparison,
            [hashtable]$NewRecord
        )

        if (-not $SnapshotComparison) {
            return $null
        }

        if (-not $SnapshotComparison.hasDelta) {
            return $null
        }

        $fields = @()
        if ($SnapshotComparison.changes -and $SnapshotComparison.changes.Count -gt 0) {
            $fields = $SnapshotComparison.changes
        }

        if ($fields.Count -eq 0) {
            $fields = @("operation")
        }

        $before = $null
        if ($SnapshotComparison.previousRecord -and $SnapshotComparison.previousRecord.PSObject.Properties['metadata']) {
            $before = $SnapshotComparison.previousRecord.metadata
        }

        $after = $null
        if ($NewRecord -and $NewRecord.metadata) {
            $after = $NewRecord.metadata
        }

        return @{
            kind = "allocation"
            fields = $fields
            before = $before
            after = $after
        }
    }
}

if (-not (Get-Command -Name New-LibraryDeltaSummary -ErrorAction SilentlyContinue)) {
    function New-LibraryDeltaSummary {
        param(
            [hashtable]$SnapshotComparison,
            [hashtable]$NewRecord
        )

        if (-not $SnapshotComparison) {
            return $null
        }

        if (-not $SnapshotComparison.hasDelta) {
            return $null
        }

        $isNew = -not $SnapshotComparison.previousRecord
        $kind = if ($isNew) { "libraryAdd" } else { "libraryChange" }

        $before = $null
        if (-not $isNew -and $SnapshotComparison.previousRecord -and $SnapshotComparison.previousRecord.PSObject.Properties['metadata']) {
            $before = $SnapshotComparison.previousRecord.metadata
        }

        $after = $null
        if ($NewRecord -and $NewRecord.metadata) {
            $after = $NewRecord.metadata
        }

        return @{
            kind = $kind
            fields = @("record")
            before = $before
            after = $after
        }
    }
}

function Normalize-WorkTypeSafe {
    param(
        [string]$WorkType,
        [string]$ObjectType = "",
        [string]$Category = ""
    )

    if (Get-Command -Name Normalize-WorkType -ErrorAction SilentlyContinue) {
        $normalized = Normalize-WorkType -WorkType $WorkType -ObjectType $ObjectType -Category $Category
        if (-not [string]::IsNullOrWhiteSpace($normalized)) {
            return $normalized
        }

        Write-Warning "Unknown workType '$WorkType' - falling back to original value"
        return $WorkType
    }

    return $WorkType
}

function Test-FileLocked {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        $stream.Close()
        return $false
    } catch {
        return $true
    }
}

# ========================================
# Database Query Execution
# ========================================

# Get credentials
# IMPORTANT: Schema parameter is for SQL queries (e.g., "SELECT * FROM DESIGN12.COLLECTION_")
# For authentication, we use sys with SYSDBA privileges in DEV mode
Write-Host "Authenticating to database..." -ForegroundColor Yellow

# Use CredentialManager to get sys credentials (DEV mode uses SYSDBA)
$credential = $null
$username = "sys"

if (Get-Command -Name Get-DbCredential -ErrorAction SilentlyContinue) {
    Write-Host "  Using CredentialManager for sys credentials..." -ForegroundColor Gray
    try {
        $credential = Get-DbCredential -TNSName $TNSName -Username $username
    } catch {
        Write-Warning "CredentialManager failed: $_"
    }
}

if ($null -eq $credential) {
    Write-Warning "Could not retrieve credentials from credential manager"
    $securePassword = Read-Host "Enter password for $username" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
} else {
    # Convert SecureString to plain text for connection
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($credential.Password)
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    $username = $credential.UserName
}

# Build connection string for both main connection and parallel jobs
$dbaPrivilege = if ($username -eq "sys") { "SYSDBA" } else { "None" }

# Create database connection using DatabaseHelper (which loads the Oracle driver)
Write-Host "Connecting to $TNSName as $username (querying schema: $Schema)..." -ForegroundColor Yellow
$connection = New-OracleConnection -ServerName $TNSName -Username $username -Password $password -DBAPrivilege $dbaPrivilege

if ($null -eq $connection) {
    Write-Error "Failed to create database connection"
    exit 1
}

# Build connection string manually for parallel jobs (connection object doesn't expose password)
$connectionString = New-OracleConnectionString -ServerName $TNSName -Username $username -Password $password -DBAPrivilege $dbaPrivilege

if ([string]::IsNullOrWhiteSpace($connectionString)) {
    Write-Error "Failed to create connection string"
    exit 1
}

try {
    $connection.Open()
    Write-Host "Connected successfully" -ForegroundColor Green
} catch {
    Write-Warning "Primary connection failed: $($_.Exception.Message)"
    Write-Host "Retrying with TNS name connection..." -ForegroundColor Yellow

    try {
        if ($null -ne $connection) {
            $connection.Dispose()
        }

        $fallbackConnectionString = New-OracleConnectionString -ServerName $TNSName -Username $username -Password $password -UseTnsNames -DBAPrivilege $dbaPrivilege
        if ([string]::IsNullOrWhiteSpace($fallbackConnectionString)) {
            throw "Failed to create fallback TNS connection string"
        }

        if ($fallbackConnectionString -notmatch "Connection Timeout") {
            $fallbackConnectionString += ";Connection Timeout=120"
        }

        $connection = New-Object Oracle.ManagedDataAccess.Client.OracleConnection($fallbackConnectionString)
        $connection.Open()
        $connectionString = $fallbackConnectionString

        Write-Host "Connected successfully (TNS fallback)" -ForegroundColor Green
    } catch {
        Write-Error "Failed to open database connection: $_"
        exit 1
    }
}

# Helper function to check table existence (avoid hard failures in optional queries)
function Test-TableExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )

    $checkQuery = "SELECT 1 FROM ALL_TABLES WHERE OWNER = '$Schema' AND TABLE_NAME = '$TableName'"
    $result = Invoke-OracleQuery -Connection $connection -Query $checkQuery -TimeoutSeconds 30
    return ($null -ne $result -and $result.Count -gt 0)
}

# Optional table checks (schema varies across deployments)
$hasTxProcessAssembly = Test-TableExists -TableName "TXPROCESSASSEMBLY_"
$hasVecRotation = Test-TableExists -TableName "VEC_ROTATION_"

# Helper function to execute query with timing and caching
function Execute-Query {
    param(
        [string]$QueryName,
        [string]$Query,
        [int]$TTLHours = 0
    )

    Write-Host "  Querying $QueryName..." -ForegroundColor Yellow

    # Check cache if TTL is set
    if ($TTLHours -gt 0) {
        $cachedData = Get-CachedData -QueryName $QueryName -TTLHours $TTLHours
        if ($null -ne $cachedData) {
            Write-Host "    Retrieved $($cachedData.Count) rows from cache" -ForegroundColor Green
            return $cachedData
        }
    }

    $queryTimer = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $data = Invoke-OracleQuery -Connection $connection -Query $Query -TimeoutSeconds 300

        $queryTimer.Stop()
        $queryTimeMs = [math]::Round($queryTimer.Elapsed.TotalMilliseconds, 0)
        $results.performance.queryTimes[$QueryName] = $queryTimeMs

        if ($null -eq $data) {
            Write-Warning "    No results returned"
            return @()
        }

        Write-Host "    Retrieved $($data.Count) rows in ${queryTimeMs}ms" -ForegroundColor Green

        # Cache data if TTL is set
        if ($TTLHours -gt 0 -and $data.Count -gt 0) {
            Set-CachedData -QueryName $QueryName -Data $data
        }

        return $data
    }
    catch {
        $queryTimer.Stop()
        Write-Warning "    Error: $_"
        return @()
    }
}

# ========================================
# Parallel Query Execution
# ========================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Executing Queries in Parallel" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Optional query templates based on schema availability
$ipaAssemblyQuery = if ($hasTxProcessAssembly) {
@"
SELECT
    'IPA_ASSEMBLY' as work_type,
    pa.OBJECT_ID as object_id,
    pa.NAME_S_ as object_name,
    'TxProcessAssembly' as object_type,
    NVL(pa.CREATEDBY_S_, '') as created_by,
    TO_CHAR(pa.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(pa.LASTMODIFIEDBY_S_, '') as modified_by,
    NVL(pr.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN pr.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(pr.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM $Schema.TXPROCESSASSEMBLY_ pa
LEFT JOIN $Schema.PROXY pr ON pa.OBJECT_ID = pr.OBJECT_ID
LEFT JOIN $Schema.USER_ u ON pr.OWNER_ID = u.OBJECT_ID
WHERE (pa.MODIFICATIONDATE_DA_ > TO_DATE('$startDateStr', 'YYYY-MM-DD')
  OR pr.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 100
ORDER BY pa.MODIFICATIONDATE_DA_ DESC
"@
} else {
    "SELECT 'IPA_ASSEMBLY' as work_type FROM DUAL WHERE 1=0"
}

$studyMovementsRotationSelect = if ($hasVecRotation) {
@"
    CASE
        WHEN EXISTS (SELECT 1 FROM $Schema.VEC_ROTATION_ vr WHERE vr.OBJECT_ID = sl.OBJECT_ID)
        THEN sl.OBJECT_ID
        ELSE NULL
    END as rotation_vector_id,
    (SELECT MAX(CASE WHEN vr.SEQ_NUMBER = 0 THEN TO_NUMBER(vr.DATA) END)
        FROM $Schema.VEC_ROTATION_ vr
        WHERE vr.OBJECT_ID = sl.OBJECT_ID) as rx_angle,
    (SELECT MAX(CASE WHEN vr.SEQ_NUMBER = 1 THEN TO_NUMBER(vr.DATA) END)
        FROM $Schema.VEC_ROTATION_ vr
        WHERE vr.OBJECT_ID = sl.OBJECT_ID) as ry_angle,
    (SELECT MAX(CASE WHEN vr.SEQ_NUMBER = 2 THEN TO_NUMBER(vr.DATA) END)
        FROM $Schema.VEC_ROTATION_ vr
        WHERE vr.OBJECT_ID = sl.OBJECT_ID) as rz_angle,
"@
} else {
@"
    NULL as rotation_vector_id,
    NULL as rx_angle,
    NULL as ry_angle,
    NULL as rz_angle,
"@
}

# Define all 14 queries
$queries = @{
    # Stable data (24 hour cache)
    ProjectDatabase = @{
        TTL = 24
        Query = @"
SELECT
    'PROJECT_DATABASE' as work_type,
    c.OBJECT_ID as object_id,
    c.CAPTION_S_ as object_name,
    c.NAME_S_ as project_name,
    'Project' as object_type,
    c.CREATEDBY_S_ as created_by,
    TO_CHAR(c.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    c.LASTMODIFIEDBY_S_ as modified_by,
    NVL(p.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(p.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM $Schema.COLLECTION_ c
LEFT JOIN $Schema.PROXY p ON c.OBJECT_ID = p.OBJECT_ID AND p.WORKING_VERSION_ID > 0
LEFT JOIN $Schema.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE c.OBJECT_ID = $ProjectId
"@
    }

    ResourceLibrary = @{
        TTL = 24
        Query = @"
SELECT
    'RESOURCE_LIBRARY' as work_type,
    r.OBJECT_ID as object_id,
    r.NAME_S_ as object_name,
    cd.NICE_NAME as object_type,
    NVL(r.CREATEDBY_S_, '') as created_by,
    TO_CHAR(r.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(r.LASTMODIFIEDBY_S_, '') as modified_by,
    NVL(p.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(p.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM $Schema.RESOURCE_ r
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON r.CLASS_ID = cd.TYPE_ID
LEFT JOIN $Schema.PROXY p ON r.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE (r.MODIFICATIONDATE_DA_ > TO_DATE('$startDateStr', 'YYYY-MM-DD')
  OR p.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 100
ORDER BY r.MODIFICATIONDATE_DA_ DESC
"@
    }

    PartLibrary = @{
        TTL = 24
        Query = @"
SELECT
    'PART_LIBRARY' as work_type,
    p.OBJECT_ID as object_id,
    p.NAME_S_ as object_name,
    cd.NICE_NAME as object_type,
    CASE
        WHEN p.NAME_S_ IN ('CC', 'RCC') THEN 'Cell Coat'
        WHEN p.NAME_S_ = 'RC' THEN 'Robot Coat'
        WHEN p.NAME_S_ = 'SC' THEN 'Spot Coat'
        WHEN p.NAME_S_ = 'CMN' THEN 'Common'
        WHEN p.NAME_S_ IN ('P702', 'P736') THEN 'Build Assembly'
        WHEN REGEXP_LIKE(p.NAME_S_, '^[0-9]+$') THEN 'Level Code'
        ELSE 'Panel/Part'
    END as category,
    NVL(p.CREATEDBY_S_, '') as created_by,
    TO_CHAR(p.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(p.LASTMODIFIEDBY_S_, '') as modified_by,
    NVL(pr.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN pr.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(pr.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM $Schema.PART_ p
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON p.CLASS_ID = cd.TYPE_ID
LEFT JOIN $Schema.PROXY pr ON p.OBJECT_ID = pr.OBJECT_ID
LEFT JOIN $Schema.USER_ u ON pr.OWNER_ID = u.OBJECT_ID
WHERE (p.MODIFICATIONDATE_DA_ > TO_DATE('$startDateStr', 'YYYY-MM-DD')
  OR pr.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 100
ORDER BY p.MODIFICATIONDATE_DA_ DESC
"@
    }

    # Semi-stable data (4 hour cache)
    IpaAssembly = @{
        TTL = 4
        Query = $ipaAssemblyQuery
    }

    StudySummary = @{
        TTL = 4
        Query = @"
SELECT
    'STUDY_SUMMARY' as work_type,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    cd.NICE_NAME as study_type,
    NVL(rs.CREATEDBY_S_, '') as created_by,
    TO_CHAR(rs.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(rs.LASTMODIFIEDBY_S_, '') as modified_by,
    NVL(p.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Active' ELSE 'Idle' END as status,
    NVL(p.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID AND p.PROJECT_ID = $ProjectId
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
LEFT JOIN $Schema.USER_ u ON p.OWNER_ID = u.OBJECT_ID
ORDER BY rs.NAME_S_
"@
    }

    StudyResources = @{
        TTL = 4
        Query = @"
SELECT
    'STUDY_RESOURCES' as work_type,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    s.NAME_S_ as shortcut_name,
    NVL(res.NAME_S_, '') as resource_name,
    NVL(cd.NICE_NAME, '') as resource_type,
    CASE
        WHEN s.NAME_S_ = 'LAYOUT' THEN 'Layout Configuration'
        WHEN s.NAME_S_ LIKE '8J-%' AND s.NAME_S_ NOT LIKE '%\_%' ESCAPE '\' THEN 'Station Reference'
        WHEN s.NAME_S_ LIKE '%\_CMN' ESCAPE '\' THEN 'Common Operations'
        WHEN s.NAME_S_ LIKE '%\_SC' ESCAPE '\' THEN 'Spot Coat Operations'
        WHEN s.NAME_S_ LIKE '%\_RC' ESCAPE '\' THEN 'Robot Coat Operations'
        WHEN s.NAME_S_ LIKE '%\_CC' ESCAPE '\' THEN 'Cell Coat Operations'
        ELSE 'Other'
    END as allocation_type
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.PROXY p_study ON rs.OBJECT_ID = p_study.OBJECT_ID AND p_study.PROJECT_ID = $ProjectId
INNER JOIN $Schema.REL_COMMON r ON r.FORWARD_OBJECT_ID = rs.OBJECT_ID AND r.REL_TYPE = 4
INNER JOIN $Schema.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
LEFT JOIN $Schema.RESOURCE_ res
    ON (s.LINKEXTERNALID_S_ IS NOT NULL AND s.LINKEXTERNALID_S_ = res.EXTERNALID_S_)
    OR (s.LINKEXTERNALID_S_ IS NULL AND s.NAME_S_ = res.NAME_S_)
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON res.CLASS_ID = cd.TYPE_ID
WHERE rs.MODIFICATIONDATE_DA_ > TO_DATE('$startDateStr', 'YYYY-MM-DD')
  AND ROWNUM <= 200
ORDER BY rs.NAME_S_, r.SEQ_NUMBER
"@
    }

    StudyPanels = @{
        TTL = 4
        Query = @"
SELECT
    'STUDY_PANELS' as work_type,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    s.NAME_S_ as shortcut_name,
    CASE
        WHEN s.NAME_S_ LIKE '%\_CC' ESCAPE '\' THEN 'CC (Cell Coat)'
        WHEN s.NAME_S_ LIKE '%\_RC' ESCAPE '\' THEN 'RC (Robot Coat)'
        WHEN s.NAME_S_ LIKE '%\_SC' ESCAPE '\' THEN 'SC (Spot Coat)'
        WHEN s.NAME_S_ LIKE '%\_CMN' ESCAPE '\' THEN 'CMN (Common)'
        ELSE 'N/A'
    END as panel_code,
    SUBSTR(s.NAME_S_, 1, INSTR(s.NAME_S_, '_') - 1) as station
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.PROXY p_study ON rs.OBJECT_ID = p_study.OBJECT_ID AND p_study.PROJECT_ID = $ProjectId
INNER JOIN $Schema.REL_COMMON r ON r.FORWARD_OBJECT_ID = rs.OBJECT_ID AND r.REL_TYPE = 4
INNER JOIN $Schema.SHORTCUT_ s ON r.OBJECT_ID = s.OBJECT_ID
WHERE s.NAME_S_ LIKE '%\_%' ESCAPE '\'
  AND rs.MODIFICATIONDATE_DA_ > TO_DATE('$startDateStr', 'YYYY-MM-DD')
  AND ROWNUM <= 200
ORDER BY rs.NAME_S_, s.NAME_S_
"@
    }

    StudyOperations = @{
        TTL = 4
        Query = @"
SELECT
    'STUDY_OPERATIONS' as work_type,
    o.OBJECT_ID as operation_id,
    o.NAME_S_ as operation_name,
    cd.NICE_NAME as operation_class,
    NVL(o.OPERATIONTYPE_S_, '') as operation_type,
    TO_CHAR(o.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(o.LASTMODIFIEDBY_S_, '') as modified_by,
    NVL(p.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE
        WHEN o.NAME_S_ LIKE 'PG%' THEN 'Weld Point Group'
        WHEN o.NAME_S_ LIKE 'MOV\_%' ESCAPE '\' THEN 'Movement Operation'
        WHEN o.NAME_S_ LIKE 'tip\_%' ESCAPE '\' THEN 'Tool Maintenance'
        WHEN o.NAME_S_ LIKE '%WELD%' THEN 'Weld Operation'
        ELSE 'Other'
    END as operation_category,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(p.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM $Schema.OPERATION_ o
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON o.CLASS_ID = cd.TYPE_ID
INNER JOIN $Schema.PROXY p ON o.OBJECT_ID = p.OBJECT_ID AND p.PROJECT_ID = $ProjectId
LEFT JOIN $Schema.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE (o.MODIFICATIONDATE_DA_ > TO_DATE('$startDateStr', 'YYYY-MM-DD')
  OR p.WORKING_VERSION_ID > 0)
  AND o.CLASS_ID = 141
  AND ROWNUM <= 100
ORDER BY o.MODIFICATIONDATE_DA_ DESC
"@
    }

    # Volatile data (1 hour cache)
    StudyMovements = @{
        TTL = 1
        Query = @"
SELECT
    'STUDY_MOVEMENTS' as work_type,
    rs.OBJECT_ID as study_id,
    rs.NAME_S_ as study_name,
    sl.OBJECT_ID as studylayout_id,
    sl.STUDYINFO_SR_ as studyinfo_id,
    TO_CHAR(sl.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(sl.LASTMODIFIEDBY_S_, '') as modified_by,
    sl.OBJECT_ID as location_vector_id,
    $studyMovementsRotationSelect
    (SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 0 THEN TO_NUMBER(vl.DATA) END)
        FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID) as x_coord,
    (SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 1 THEN TO_NUMBER(vl.DATA) END)
        FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID) as y_coord,
    (SELECT MAX(CASE WHEN vl.SEQ_NUMBER = 2 THEN TO_NUMBER(vl.DATA) END)
        FROM $Schema.VEC_LOCATION_ vl
        WHERE vl.OBJECT_ID = sl.OBJECT_ID) as z_coord,
    NVL(p.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(p.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.PROXY p_study ON rs.OBJECT_ID = p_study.OBJECT_ID AND p_study.PROJECT_ID = $ProjectId
INNER JOIN $Schema.REL_COMMON r_info ON r_info.FORWARD_OBJECT_ID = rs.OBJECT_ID AND r_info.CLASS_ID = 71
INNER JOIN $Schema.STUDYLAYOUT_ sl ON sl.STUDYINFO_SR_ = r_info.OBJECT_ID
LEFT JOIN $Schema.PROXY p ON sl.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE (sl.MODIFICATIONDATE_DA_ > TO_DATE('$startDateStr', 'YYYY-MM-DD')
    OR p.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 100
ORDER BY sl.MODIFICATIONDATE_DA_ DESC
"@
    }

    StudyWelds = @{
        TTL = 1
        Query = @"
SELECT
    'STUDY_WELDS' as work_type,
    o.OBJECT_ID as operation_id,
    o.NAME_S_ as operation_name,
    TO_CHAR(o.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(o.LASTMODIFIEDBY_S_, '') as modified_by,
    NVL(p.OWNER_ID, 0) as checked_out_by_user_id,
    NVL(u.CAPTION_S_, '') as checked_out_by_user_name,
    CASE WHEN p.WORKING_VERSION_ID > 0 THEN 'Checked Out' ELSE 'Available' END as status,
    NVL(p.WORKING_VERSION_ID, 0) as checkout_working_version_id
FROM $Schema.OPERATION_ o
INNER JOIN $Schema.PROXY p ON o.OBJECT_ID = p.OBJECT_ID AND p.PROJECT_ID = $ProjectId
LEFT JOIN $Schema.USER_ u ON p.OWNER_ID = u.OBJECT_ID
WHERE o.CLASS_ID = 141
  AND (o.MODIFICATIONDATE_DA_ > TO_DATE('$startDateStr', 'YYYY-MM-DD')
    OR p.WORKING_VERSION_ID > 0)
  AND ROWNUM <= 100
ORDER BY o.MODIFICATIONDATE_DA_ DESC
"@
    }

    UserActivity = @{
        TTL = 1
        Query = @"
SELECT
    u.OBJECT_ID as user_id,
    u.CAPTION_S_ as user_name,
    u.NAME_S_ as username,
    COUNT(DISTINCT p.OBJECT_ID) as objects_total,
    COUNT(DISTINCT CASE WHEN p.WORKING_VERSION_ID > 0 THEN p.OBJECT_ID END) as active_checkouts
FROM $Schema.USER_ u
LEFT JOIN $Schema.PROXY p ON u.OBJECT_ID = p.OWNER_ID
GROUP BY u.OBJECT_ID, u.CAPTION_S_, u.NAME_S_
HAVING COUNT(DISTINCT p.OBJECT_ID) > 0
ORDER BY active_checkouts DESC
"@
    }

    StudyHealthData = @{
        TTL = 4
        Query = @"
SELECT
    rs.OBJECT_ID as object_id,
    rs.NAME_S_ as study_name,
    cd.NICE_NAME as study_type,
    NVL(rs.CREATEDBY_S_, '') as created_by,
    TO_CHAR(rs.MODIFICATIONDATE_DA_, 'YYYY-MM-DD HH24:MI:SS') as last_modified,
    NVL(rs.LASTMODIFIEDBY_S_, '') as modified_by,
    rs.CLASS_ID as class_id
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID AND p.PROJECT_ID = $ProjectId
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON rs.CLASS_ID = cd.TYPE_ID
WHERE rs.NAME_S_ IS NOT NULL
ORDER BY rs.NAME_S_
"@
    }

    ResourceConflicts = @{
        TTL = 1
        Query = @"
SELECT
    r.NAME_S_ as resource_name,
    r.OBJECT_ID as resource_id,
    cd.NICE_NAME as resource_type,
    COUNT(DISTINCT rs.OBJECT_ID) as study_count,
    LISTAGG(rs.NAME_S_, ', ') WITHIN GROUP (ORDER BY rs.NAME_S_) as studies_using_resource
FROM $Schema.SHORTCUT_ s
INNER JOIN $Schema.RESOURCE_ r ON s.NAME_S_ = r.NAME_S_
INNER JOIN $Schema.REL_COMMON rc ON s.OBJECT_ID = rc.OBJECT_ID
INNER JOIN $Schema.ROBCADSTUDY_ rs ON rc.FORWARD_OBJECT_ID = rs.OBJECT_ID
INNER JOIN $Schema.PROXY p ON rs.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON r.CLASS_ID = cd.TYPE_ID
WHERE p.WORKING_VERSION_ID > 0
  AND p.PROJECT_ID = $ProjectId
GROUP BY r.NAME_S_, r.OBJECT_ID, cd.NICE_NAME
HAVING COUNT(DISTINCT rs.OBJECT_ID) > 1
ORDER BY study_count DESC
"@
    }

    StaleCheckouts = @{
        TTL = 1
        Query = @"
SELECT
    c.OBJECT_ID as object_id,
    c.CAPTION_S_ as object_name,
    cd.NICE_NAME as object_type,
    c.MODIFICATIONDATE_DA_ as last_modified,
    u.CAPTION_S_ as checked_out_by,
    u.OBJECT_ID as user_id,
    ROUND((SYSDATE - c.MODIFICATIONDATE_DA_) * 24, 1) as checkout_duration_hours,
    ROUND((SYSDATE - c.MODIFICATIONDATE_DA_), 1) as checkout_duration_days
FROM $Schema.COLLECTION_ c
INNER JOIN $Schema.PROXY p ON c.OBJECT_ID = p.OBJECT_ID
LEFT JOIN $Schema.USER_ u ON p.OWNER_ID = u.OBJECT_ID
LEFT JOIN $Schema.CLASS_DEFINITIONS cd ON c.CLASS_ID = cd.TYPE_ID
WHERE p.WORKING_VERSION_ID > 0
  AND c.MODIFICATIONDATE_DA_ < SYSDATE - 3
ORDER BY checkout_duration_hours DESC
"@
    }
}

# Execute queries in parallel using jobs
Write-Host "`nStarting parallel query execution..." -ForegroundColor Yellow

# Use the connection string we built earlier for parallel jobs
$connectionStringForJobs = $connectionString

$jobs = @{}
$queryOrder = @(
    'ProjectDatabase', 'ResourceLibrary', 'PartLibrary', 'IpaAssembly',
    'StudySummary', 'StudyResources', 'StudyPanels', 'StudyOperations',
    'StudyMovements', 'StudyWelds', 'UserActivity', 'StudyHealthData',
    'ResourceConflicts', 'StaleCheckouts'
)

$jobIndex = 1
foreach ($queryName in $queryOrder) {
    $queryInfo = $queries[$queryName]
    Write-Host "[$jobIndex/14] Launching $queryName (TTL: $($queryInfo.TTL)h)..." -ForegroundColor Cyan

    # Check cache first (synchronously for better UX)
    $cachedData = Get-CachedData -QueryName $queryName -TTLHours $queryInfo.TTL
    if ($null -ne $cachedData) {
        # Use cached data immediately
        $jobs[$queryName] = @{
            Job = $null
            Data = $cachedData
            Cached = $true
        }
        $jobIndex++
        continue
    }

    # Launch background job for query
    $job = Start-Job -ScriptBlock {
        param($connString, $query, $timeout)

        # Load assembly in job context
        $scriptRoot = $using:PSScriptRoot
        $rootDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scriptRoot))
        $dllPath = Join-Path $rootDir "lib\Oracle.ManagedDataAccess.dll"
        Add-Type -Path $dllPath -ErrorAction Stop

        $conn = New-Object Oracle.ManagedDataAccess.Client.OracleConnection($connString)
        $conn.Open()

        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $query
        $cmd.CommandTimeout = $timeout

        $reader = $cmd.ExecuteReader()

        $columns = @()
        for ($i = 0; $i -lt $reader.FieldCount; $i++) {
            $columns += $reader.GetName($i)
        }

        $results = @()
        while ($reader.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $value = $reader.GetValue($i)
                if ($value -is [System.DBNull]) {
                    $value = $null
                }
                $row[$columns[$i]] = $value
            }
            $results += [PSCustomObject]$row
        }

        $reader.Close()
        $cmd.Dispose()
        $conn.Close()
        $conn.Dispose()

        return $results
    } -ArgumentList $connectionStringForJobs, $queryInfo.Query, 300

    $jobs[$queryName] = @{
        Job = $job
        Data = $null
        Cached = $false
        StartTime = Get-Date
    }

    $jobIndex++
}

# Wait for jobs and collect results
Write-Host "`nWaiting for queries to complete..." -ForegroundColor Yellow

foreach ($queryName in $queryOrder) {
    $jobInfo = $jobs[$queryName]

    if ($jobInfo.Cached) {
        Write-Host "  $queryName : Retrieved $($jobInfo.Data.Count) rows from cache" -ForegroundColor Green
        continue
    }

    $job = $jobInfo.Job
    $startTime = $jobInfo.StartTime

    Write-Host "  $queryName : Waiting..." -ForegroundColor Yellow -NoNewline

    $completed = Wait-Job $job -Timeout 300

    if (-not $completed) {
        Stop-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Write-Host " TIMEOUT" -ForegroundColor Red
        $jobInfo.Data = @()
    } else {
        $data = Receive-Job $job
        Remove-Job $job -Force -ErrorAction SilentlyContinue

        $elapsed = ((Get-Date) - $startTime).TotalMilliseconds
        $results.performance.queryTimes[$queryName] = [math]::Round($elapsed, 0)

        $jobInfo.Data = @($data)
        Write-Host " $($jobInfo.Data.Count) rows in $([math]::Round($elapsed, 0))ms" -ForegroundColor Green

        # Cache the result
        if ($queries[$queryName].TTL -gt 0 -and $jobInfo.Data.Count -gt 0) {
            Set-CachedData -QueryName $queryName -Data $jobInfo.Data
        }
    }
}

# Assign results to output structure
Write-Host "`nProcessing results..." -ForegroundColor Yellow

$results.projectDatabase = $jobs['ProjectDatabase'].Data
$results.resourceLibrary = $jobs['ResourceLibrary'].Data
$results.partLibrary = $jobs['PartLibrary'].Data
$results.ipaAssembly = $jobs['IpaAssembly'].Data
$results.studySummary = $jobs['StudySummary'].Data
$results.studyResources = $jobs['StudyResources'].Data
$results.studyPanels = $jobs['StudyPanels'].Data
$results.studyOperations = $jobs['StudyOperations'].Data
$results.studyMovements = $jobs['StudyMovements'].Data
$results.studyWelds = $jobs['StudyWelds'].Data
$results.userActivity = $jobs['UserActivity'].Data

# Populate project name metadata from projectDatabase (if available)
if (-not $results.metadata.projectName) {
    $projectName = $null
    if ($results.projectDatabase -and $results.projectDatabase.Count -gt 0) {
        $firstProject = $results.projectDatabase[0]
        if ($firstProject.project_name) {
            $projectName = $firstProject.project_name
        } elseif ($firstProject.object_name) {
            $projectName = $firstProject.object_name
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($projectName)) {
        $results.metadata.projectName = $projectName
    }
}

# Deduplicate study summary by study_id
if ($results.studySummary -and $results.studySummary.Count -gt 0) {
    $studyMap = @{}
    foreach ($study in $results.studySummary) {
        $studyId = $study.study_id
        if (-not $studyMap.ContainsKey($studyId)) {
            $studyMap[$studyId] = $study
        } else {
            $existingDate = [DateTime]::ParseExact($studyMap[$studyId].last_modified, 'yyyy-MM-dd HH:mm:ss', $null)
            $newDate = [DateTime]::ParseExact($study.last_modified, 'yyyy-MM-dd HH:mm:ss', $null)
            if ($newDate -gt $existingDate) {
                $studyMap[$studyId] = $study
            }
        }
    }
    $beforeCount = $results.studySummary.Count
    $deduped = @()
    $deduped += $studyMap.Values
    $results.studySummary = $deduped
    if ($beforeCount -ne $results.studySummary.Count) {
        Write-Host "  Deduplicated $beforeCount -> $($results.studySummary.Count) studies" -ForegroundColor DarkYellow
    }
}

# Study summary count (proxy scope)
$studyTotal = if ($results.studySummary) { $results.studySummary.Count } else { 0 }

# Tree scope total (REL_COMMON descendants of projectId, REL_TYPE = 4)
$treeScopeTotal = 0
try {
    $treeScopeQuery = @"
WITH tree_collections AS (
    SELECT DISTINCT c.OBJECT_ID
    FROM $Schema.REL_COMMON r
    INNER JOIN $Schema.COLLECTION_ c ON r.OBJECT_ID = c.OBJECT_ID
    WHERE r.REL_TYPE = 4
    START WITH r.FORWARD_OBJECT_ID = $ProjectId
    CONNECT BY NOCYCLE PRIOR r.OBJECT_ID = r.FORWARD_OBJECT_ID
)
SELECT COUNT(DISTINCT rs.OBJECT_ID) AS TOTAL_COUNT
FROM $Schema.ROBCADSTUDY_ rs
INNER JOIN $Schema.REL_COMMON r ON r.OBJECT_ID = rs.OBJECT_ID AND r.REL_TYPE = 4
INNER JOIN tree_collections tc ON r.FORWARD_OBJECT_ID = tc.OBJECT_ID
"@

    $treeScopeResult = Invoke-OracleQuery -Connection $connection -Query $treeScopeQuery -TimeoutSeconds 300
    if ($treeScopeResult -and $treeScopeResult.Count -gt 0) {
        $treeScopeRow = $treeScopeResult | Select-Object -First 1
        if ($treeScopeRow.PSObject.Properties.Name -contains 'TOTAL_COUNT') {
            $treeScopeTotal = [int]$treeScopeRow.TOTAL_COUNT
        } elseif ($treeScopeRow.PSObject.Properties.Name -contains 'total_count') {
            $treeScopeTotal = [int]$treeScopeRow.total_count
        } elseif ($treeScopeRow.PSObject.Properties.Name -contains 'totalcount') {
            $treeScopeTotal = [int]$treeScopeRow.totalcount
        }
    }
} catch {
    Write-Warning "  Tree scope total query failed: $_"
    $treeScopeTotal = 0
}

# Fallback to SQL*Plus if tree scope is unexpectedly empty while proxy scope has data
if ($treeScopeTotal -eq 0 -and $studyTotal -gt 0) {
    if (Get-Command -Name sqlplus -ErrorAction SilentlyContinue) {
        if (-not (Get-Command -Name Invoke-SqlPlusQuery -ErrorAction SilentlyContinue)) {
            if (Test-Path $sqlHelperPath) {
                . $sqlHelperPath
            }
        }

        if (Get-Command -Name Invoke-SqlPlusQuery -ErrorAction SilentlyContinue) {
            try {
                Write-Warning "  Tree scope total empty via Oracle driver; retrying via SQL*Plus..."
                $treeScopeResultSql = Invoke-SqlPlusQuery -TNSName $TNSName -Username $username -Password $password -Query $treeScopeQuery -DBAPrivilege $dbaPrivilege -TimeoutSeconds 120
                if ($treeScopeResultSql -and $treeScopeResultSql.Count -gt 0) {
                    $treeScopeRowSql = $treeScopeResultSql | Select-Object -First 1
                    if ($treeScopeRowSql.PSObject.Properties.Name -contains 'TOTAL_COUNT') {
                        $treeScopeTotal = [int]$treeScopeRowSql.TOTAL_COUNT
                    } elseif ($treeScopeRowSql.PSObject.Properties.Name -contains 'total_count') {
                        $treeScopeTotal = [int]$treeScopeRowSql.total_count
                    } elseif ($treeScopeRowSql.PSObject.Properties.Name -contains 'totalcount') {
                        $treeScopeTotal = [int]$treeScopeRowSql.totalcount
                    } else {
                        $props = $treeScopeRowSql.PSObject.Properties
                        if ($props -and $props.Count -gt 0) {
                            $candidate = $props[0].Value
                            if ($candidate -match '\d+') {
                                $treeScopeTotal = [int]$Matches[0]
                            }
                        }
                    }
                }

                if ($treeScopeTotal -eq 0) {
                    $rawText = $null
                    if ($treeScopeResultSql -is [string]) {
                        $rawText = $treeScopeResultSql
                    } elseif ($treeScopeResultSql -is [System.Array] -and $treeScopeResultSql.Count -gt 0 -and $treeScopeResultSql[0] -is [string]) {
                        $rawText = ($treeScopeResultSql -join "`n")
                    }
                    if ($rawText -and $rawText -match '(\d+)') {
                        $treeScopeTotal = [int]$Matches[1]
                    }
                }

                if ($treeScopeTotal -eq 0) {
                    try {
                        $connString = "${username}/${password}@${TNSName}"
                        if ($dbaPrivilege -ne "None") {
                            $connString += " as $dbaPrivilege"
                        }

                        $tempSql = [System.IO.Path]::GetTempFileName() + ".sql"
                        $queryText = $treeScopeQuery.Trim()
                        if (-not $queryText.EndsWith(';')) {
                            $queryText += ';'
                        }

                        $sqlContent = @"
SET PAGESIZE 50000
SET FEEDBACK OFF
SET HEADING ON
SET LINESIZE 32767
SET COLSEP '|'
SET UNDERLINE OFF
$queryText
EXIT;
"@
                        $sqlContent | Out-File $tempSql -Encoding ASCII -Force

                        $output = & sqlplus -S $connString "@$tempSql" 2>&1
                        $outputText = ($output | Out-String).Trim()

                        if ($outputText -match 'ORA-\d+' -or $outputText -match 'ERROR') {
                            Write-Warning "  SQL*Plus direct fallback error: $outputText"
                        } elseif ($outputText -match '(\d+)') {
                            $treeScopeTotal = [int]$Matches[1]
                        }
                    } catch {
                        Write-Warning "  SQL*Plus direct fallback failed: $_"
                    } finally {
                        if ($tempSql -and (Test-Path $tempSql)) {
                            Remove-Item $tempSql -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
            } catch {
                Write-Warning "  SQL*Plus tree scope fallback failed: $_"
            }
        } else {
            Write-Warning "  SQL*Plus helper not available; tree scope total remains 0"
        }
    } else {
        Write-Warning "  sqlplus not found; tree scope total remains 0"
    }
}

# Work Type Summary metadata (definitions + Study Nodes breakdown)
$studyCheckedOutCount = 0
$studyModifiedInRangeCount = 0
$studyModifiedButNotCheckedOutCount = 0
$studyCheckedOutButNotModifiedCount = 0

if ($results.studySummary -and $results.studySummary.Count -gt 0) {
    foreach ($study in $results.studySummary) {
        $isCheckedOut = ($study.status -eq 'Active' -or $study.status -eq 'Checked Out')
        $lastModifiedDate = Convert-StringToDateTime -Value $study.last_modified
        $isModifiedInRange = Test-DateInRange -Value $lastModifiedDate -Start $StartDate -End $EndDate

        if ($isCheckedOut) { $studyCheckedOutCount++ }
        if ($isModifiedInRange) { $studyModifiedInRangeCount++ }
        if ($isModifiedInRange -and -not $isCheckedOut) { $studyModifiedButNotCheckedOutCount++ }
        if ($isCheckedOut -and -not $isModifiedInRange) { $studyCheckedOutButNotModifiedCount++ }
    }
}

$results.workTypeSummaryMeta = @{
    checkedOutRule = "PROXY.WORKING_VERSION_ID > 0"
    modifiedRule = "ROBCADSTUDY_.MODIFICATIONDATE_DA_ between ${startDateStr} and ${endDateStr} (inclusive)"
    modifiedTimestampColumn = "ROBCADSTUDY_.MODIFICATIONDATE_DA_"
    dateRangeStart = $startDateStr
    dateRangeEnd = $endDateStr
    studyNodes = @{
        totalStudiesTreeScope = $treeScopeTotal
        totalStudiesProxyScope = $studyTotal
        checkedOutCount = $studyCheckedOutCount
        modifiedInRangeCount = $studyModifiedInRangeCount
        modifiedButNotCheckedOutCount = $studyModifiedButNotCheckedOutCount
        checkedOutButNotModifiedInRangeCount = $studyCheckedOutButNotModifiedCount
        dateRangeStart = $startDateStr
        dateRangeEnd = $endDateStr
        modifiedTimestampColumn = "ROBCADSTUDY_.MODIFICATIONDATE_DA_"
    }
}

# ========================================
# Compute Study Health v1
# ========================================
Write-Host "`n[11b/14] Computing Study Health (v1)" -ForegroundColor Cyan

# Helper function to compute health for a single study
function Compute-StudyHealth {
    param(
        [Parameter(Mandatory=$true)]
        $Study,
        [hashtable]$TreeSnapshotIndex,
        [hashtable]$SnapshotStatusIndex,
        [hashtable]$ResourceCountsIndex,
        [hashtable]$PanelCountsIndex,
        [hashtable]$OperationCountsIndex
    )

    $studyId = [string]$Study.study_id
    $studyName = $Study.study_name

    # Initialize health signals
    $signals = @{
        nodeCount = 0
        snapshotStatus = "unknown"
        nodeCountSource = "unknown"
        rootResourceCount = 0
        structureUnreadable = $false
        hasResourcesLoaded = $false
        resourceCount = 0
        hasPanels = $false
        panelCount = 0
        hasMfg = $false
        mfgCount = 0
        projectedMfgCount = 0
        hasLocations = $false
        locationCount = 0
        assignedLocationCount = 0
        hasOperations = $false
        operationCount = 0
        robotLinkedOperationCount = 0
    }

    # Determine snapshot status
    if ($SnapshotStatusIndex.ContainsKey($studyId)) {
        $signals.snapshotStatus = $SnapshotStatusIndex[$studyId]
    }

    # Get node count from tree snapshot if available
    if ($TreeSnapshotIndex.ContainsKey($studyId)) {
        $snapshot = $TreeSnapshotIndex[$studyId]
        if ($snapshot.meta -and $snapshot.meta.nodeCount) {
            $signals.nodeCount = [int]$snapshot.meta.nodeCount
            $signals.nodeCountSource = "snapshot"
        }
    }

    # Get resource counts
    if ($ResourceCountsIndex.ContainsKey($studyId)) {
        $resInfo = $ResourceCountsIndex[$studyId]
        $signals.resourceCount = $resInfo.totalCount
        $signals.rootResourceCount = $resInfo.rootCount
        $signals.hasResourcesLoaded = ($resInfo.totalCount -gt 0)
    }

    # Get panel counts
    if ($PanelCountsIndex.ContainsKey($studyId)) {
        $panelCount = $PanelCountsIndex[$studyId]
        $signals.panelCount = $panelCount
        $signals.hasPanels = ($panelCount -gt 0)
    }

    # Get operation counts
    if ($OperationCountsIndex.ContainsKey($studyId)) {
        $opInfo = $OperationCountsIndex[$studyId]
        $signals.operationCount = $opInfo.totalCount
        $signals.robotLinkedOperationCount = $opInfo.robotLinkedCount
        $signals.hasOperations = ($opInfo.totalCount -gt 0)
    }

    # Fallback nodeCount if snapshot is missing or has error
    if ($signals.snapshotStatus -ne "ok" -and $signals.nodeCount -eq 0) {
        # Compute proxy count from existing data collections
        $fallbackCount = $signals.resourceCount + $signals.panelCount + $signals.operationCount
        if ($fallbackCount -gt 0) {
            $signals.nodeCount = $fallbackCount
            $signals.nodeCountSource = "fallback_proxy"
        }
    }

    # Determine structure readability (using study name heuristics)
    # A structure is "unreadable" if name suggests it's poorly organized
    $nameLower = $studyName.ToLowerInvariant()
    $hasJunkPattern = ($nameLower -match 'test|temp|asdf|xxx|copy|new folder')
    $hasIllegalChars = ($studyName -match '[:\*\?"<>\|]')
    $signals.structureUnreadable = ($hasJunkPattern -or $hasIllegalChars)

    # Initialize score and reasons
    $score = 100
    $reasons = @()

    # Rule 1: Hard fail ONLY if snapshot is OK but nodeCount is 0
    if ($signals.snapshotStatus -eq "ok" -and $signals.nodeCount -eq 0) {
        $score = 0
        $reasons += "no_nodes"
    } elseif ($signals.snapshotStatus -eq "missing") {
        # Snapshot missing - start at low Warning range (40-79)
        $score = 45
        $reasons += "snapshot_missing"
    } elseif ($signals.snapshotStatus -eq "error") {
        # Snapshot error - start at low Warning range
        $score = 40
        $reasons += "snapshot_error"
    }

    # Continue scoring if not hard-failed
    if ($score -gt 0) {
        # Rule 2: Root resources penalty
        if ($signals.rootResourceCount -gt 0) {
            $score -= 10
            $reasons += "root_resources"
        }

        # Rule 3: Structure unreadable penalty
        if ($signals.structureUnreadable) {
            $score -= 20
            $reasons += "structure_unreadable"
        }

        # Stage-aware penalties (only apply if appropriate)
        
        # No resources loaded (basic penalty)
        if (-not $signals.hasResourcesLoaded) {
            $score -= 5
            $reasons += "no_resources"
        } else {
            # Panels stage (only if resources exist)
            if (-not $signals.hasPanels) {
                $score -= 5
                $reasons += "no_panels"
            }

            # MFG projection (only if MFG exists)
            if ($signals.hasMfg -and $signals.projectedMfgCount -eq 0) {
                $score -= 5
                $reasons += "mfg_not_projected"
            }

            # Locations assigned (only if locations exist)
            if ($signals.hasLocations -and $signals.assignedLocationCount -eq 0) {
                $score -= 5
                $reasons += "locations_not_assigned"
            }

            # Operations robot-linked (only if operations exist)
            if ($signals.hasOperations -and $signals.robotLinkedOperationCount -eq 0) {
                $score -= 5
                $reasons += "operations_not_linked"
            }
        }
    }

    # Ensure score is in valid range
    $score = [Math]::Max(0, [Math]::Min(100, $score))

    # Determine status from score
    $status = if ($score -ge 80) { "Healthy" } elseif ($score -ge 40) { "Warning" } else { "Unhealthy" }

    return @{
        healthScore = $score
        healthStatus = $status
        healthReasons = $reasons
        healthSignals = $signals
    }
}

# Build indexes for health computation
Write-Host "  Building data indexes..." -ForegroundColor Gray

# Snapshot status index (track which studies have snapshots, missing, or errors)
# This will be populated during snapshot collection
$snapshotStatusIndex = @{}

# Tree snapshot index (nodeCount from snapshots)
$treeSnapshotIndex = @{}
$treeSnapshotDir = Join-Path (Get-Location).Path "data\tree-snapshots"
if (Test-Path $treeSnapshotDir) {
    Get-ChildItem -Path $treeSnapshotDir -Filter "*.json" | Where-Object { $_.Name -notmatch 'previous' } | ForEach-Object {
        if ($_.BaseName -match '^\d+$') {
            $studyId = $_.BaseName
            try {
                $snapshot = Get-Content $_.FullName -Raw | ConvertFrom-Json
                $treeSnapshotIndex[$studyId] = $snapshot
                $snapshotStatusIndex[$studyId] = "ok"
            } catch {
                # Mark as error if snapshot file exists but is invalid
                $snapshotStatusIndex[$studyId] = "error"
            }
        }
    }
}
Write-Host "    Loaded $($treeSnapshotIndex.Count) tree snapshots" -ForegroundColor DarkGray

# Resource counts index (per study)
$resourceCountsIndex = @{}
if ($results.studyResources) {
    $results.studyResources | Group-Object -Property study_id | ForEach-Object {
        $studyId = [string]$_.Name
        $resources = $_.Group
        $totalCount = $resources.Count
        # Root resources are those with allocation_type indicating root level or shortcut_name is empty/generic
        $rootCount = ($resources | Where-Object { 
            $_.allocation_type -eq 'Root' -or 
            $_.shortcut_name -eq 'Shortcut' -or 
            [string]::IsNullOrWhiteSpace($_.shortcut_name)
        }).Count
        $resourceCountsIndex[$studyId] = @{
            totalCount = $totalCount
            rootCount = $rootCount
        }
    }
}
Write-Host "    Indexed $($resourceCountsIndex.Count) studies with resources" -ForegroundColor DarkGray

# Panel counts index
$panelCountsIndex = @{}
if ($results.studyPanels) {
    $results.studyPanels | Group-Object -Property study_id | ForEach-Object {
        $studyId = [string]$_.Name
        $panelCountsIndex[$studyId] = $_.Count
    }
}
Write-Host "    Indexed $($panelCountsIndex.Count) studies with panels" -ForegroundColor DarkGray

# Operation counts index (total and robot-linked)
$operationCountsIndex = @{}
if ($results.studyOperations) {
    $results.studyOperations | Group-Object -Property study_id | ForEach-Object {
        $studyId = [string]$_.Name
        $operations = $_.Group
        $totalCount = $operations.Count
        # Robot-linked operations have a robot_name populated
        $robotLinkedCount = ($operations | Where-Object { -not [string]::IsNullOrWhiteSpace($_.robot_name) }).Count
        $operationCountsIndex[$studyId] = @{
            totalCount = $totalCount
            robotLinkedCount = $robotLinkedCount
        }
    }
}
Write-Host "    Indexed $($operationCountsIndex.Count) studies with operations" -ForegroundColor DarkGray

# Compute health for each study in studySummary
Write-Host "  Computing health for $($results.studySummary.Count) studies..." -ForegroundColor Gray
$healthyCount = 0
$warningCount = 0
$unhealthyCount = 0

foreach ($study in $results.studySummary) {
    $studyId = [string]$study.study_id
    # Mark as missing if no snapshot status was set (meaning no snapshot exists)
    if (-not $snapshotStatusIndex.ContainsKey($studyId)) {
        $snapshotStatusIndex[$studyId] = "missing"
    }
    
    $health = Compute-StudyHealth `
        -Study $study `
        -TreeSnapshotIndex $treeSnapshotIndex `
        -SnapshotStatusIndex $snapshotStatusIndex `
        -ResourceCountsIndex $resourceCountsIndex `
        -PanelCountsIndex $panelCountsIndex `
        -OperationCountsIndex $operationCountsIndex

    # Attach health fields to study object
    $study | Add-Member -NotePropertyName healthScore -NotePropertyValue $health.healthScore -Force
    $study | Add-Member -NotePropertyName healthStatus -NotePropertyValue $health.healthStatus -Force
    $study | Add-Member -NotePropertyName healthReasons -NotePropertyValue $health.healthReasons -Force
    $study | Add-Member -NotePropertyName healthSignals -NotePropertyValue $health.healthSignals -Force

    # Count by status
    switch ($health.healthStatus) {
        "Healthy" { $healthyCount++ }
        "Warning" { $warningCount++ }
        "Unhealthy" { $unhealthyCount++ }
    }
}

Write-Host "  Health computed: $healthyCount Healthy, $warningCount Warning, $unhealthyCount Unhealthy" -ForegroundColor Green

# Process Study Health Analysis
Write-Host "`n[12/14] Processing Study Health Analysis" -ForegroundColor Cyan
$allStudies = $jobs['StudyHealthData'].Data

# Load rules from config file
$rulesPath = Join-Path $PSScriptRoot "..\..\..\config\robcad-study-health-rules.json"
$rules = @{
    maxNameLength = 60
    maxWordCount = 8
    illegalChars = @(":", "*", "?", '"', "<", ">", "|")
    junkTokens = @("test", "temp", "asdf", "qwerty", "xxx", "copy")
    junkPhrases = @("new folder", "do not delete", "final_final")
    legacyTokens = @("old", "legacy", "backup", "deprecated", "unused", "archive")
    yearPattern = "(19|20)\d{2}"
}

if (Test-Path $rulesPath) {
    try {
        $rulesJson = Get-Content $rulesPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $rules.maxNameLength = $rulesJson.maxNameLength
        $rules.maxWordCount = $rulesJson.maxWordCount
        $rules.illegalChars = $rulesJson.illegalChars
        $rules.junkTokens = $rulesJson.junkTokens
        $rules.junkPhrases = $rulesJson.junkPhrases
        $rules.legacyTokens = $rulesJson.legacyTokens
        $rules.yearPattern = $rulesJson.yearPattern
    } catch {
        Write-Warning "    Could not load rules from $rulesPath, using defaults"
    }
}

$issues = @()
$suspicious = @()
$renameSuggestions = @()

# Helper function to check for illegal characters
function Test-IllegalChars {
    param([string]$Name, [string[]]$IllegalChars)
    foreach ($char in $IllegalChars) {
        if ($Name.Contains($char)) {
            return $true
        }
    }
    return $false
}

# Helper function to extract tokens
function Get-NameTokens {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) {
        return @()
    }
    $matches = [regex]::Matches($Name, "[A-Za-z0-9]+")
    return $matches | ForEach-Object { $_.Value.ToLowerInvariant() }
}

# Analyze each study
foreach ($study in $allStudies) {
    $name = $study.study_name

    if ([string]::IsNullOrWhiteSpace($name)) {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = ""
            severity = "Critical"
            issue = "empty_name"
            details = "Name is empty or whitespace"
        }
        continue
    }

    if ($name -ne $name.Trim()) {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = $name
            severity = "High"
            issue = "whitespace_padding"
            details = "Name has leading or trailing whitespace"
        }
    }

    if ($name.Length -gt $rules.maxNameLength) {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = $name
            severity = "Medium"
            issue = "name_too_long"
            details = "Name exceeds $($rules.maxNameLength) characters (current: $($name.Length))"
        }
    }

    if (Test-IllegalChars -Name $name -IllegalChars $rules.illegalChars) {
        $issues += [PSCustomObject]@{
            node_id = $study.object_id
            study_name = $name
            severity = "Critical"
            issue = "illegal_characters"
            details = "Name contains illegal filesystem characters"
        }
    }

    $tokens = Get-NameTokens -Name $name

    foreach ($junk in $rules.junkTokens) {
        if ($tokens -contains $junk) {
            $suspicious += [PSCustomObject]@{
                node_id = $study.object_id
                study_name = $name
                flag = "junk_token"
                token = $junk
                suggestion = "Review and rename if test/temporary study"
            }
        }
    }

    foreach ($legacy in $rules.legacyTokens) {
        if ($tokens -contains $legacy) {
            $suspicious += [PSCustomObject]@{
                node_id = $study.object_id
                study_name = $name
                flag = "legacy_token"
                token = $legacy
                suggestion = "Consider archiving or removing if no longer needed"
            }
        }
    }

    if ($name -match $rules.yearPattern) {
        $year = [regex]::Match($name, $rules.yearPattern).Value
        $currentYear = (Get-Date).Year
        if ([int]$year -lt ($currentYear - 2)) {
            $suspicious += [PSCustomObject]@{
                node_id = $study.object_id
                study_name = $name
                flag = "old_year"
                token = $year
                suggestion = "Study name contains old year $year - review if still current"
            }
        }
    }
}

$results.studyHealth.issues = $issues
$results.studyHealth.suspicious = $suspicious
$results.studyHealth.renameSuggestions = $renameSuggestions
$results.studyHealth.summary.totalStudies = $allStudies.Count
$results.studyHealth.summary.totalIssues = $issues.Count
$results.studyHealth.summary.criticalIssues = ($issues | Where-Object { $_.severity -eq "Critical" }).Count
$results.studyHealth.summary.highIssues = ($issues | Where-Object { $_.severity -eq "High" }).Count
$results.studyHealth.summary.mediumIssues = ($issues | Where-Object { $_.severity -eq "Medium" }).Count
$results.studyHealth.summary.lowIssues = ($issues | Where-Object { $_.severity -eq "Low" }).Count

Write-Host "  Found $($issues.Count) issues across $($allStudies.Count) studies" -ForegroundColor Green

# Process Resource Conflicts
Write-Host "`n[13/14] Processing Resource Conflicts" -ForegroundColor Cyan
$conflicts = $jobs['ResourceConflicts'].Data

$results.resourceConflicts = $conflicts | ForEach-Object {
    $studyCount = [int]$_.study_count
    $riskLevel = if ($studyCount -ge 3) { "Critical" } elseif ($studyCount -eq 2) { "High" } else { "Medium" }

    [PSCustomObject]@{
        resource_name = $_.resource_name
        resource_id = $_.resource_id
        resource_type = $_.resource_type
        study_count = $studyCount
        studies = $_.studies_using_resource
        risk_level = $riskLevel
    }
}

Write-Host "  Found $($results.resourceConflicts.Count) resource conflicts" -ForegroundColor Green

# Process Stale Checkouts
Write-Host "`n[14/14] Processing Stale Checkouts" -ForegroundColor Cyan
$staleCheckouts = $jobs['StaleCheckouts'].Data

$results.staleCheckouts = $staleCheckouts | ForEach-Object {
    $hours = [double]$_.checkout_duration_hours
    $days = [double]$_.checkout_duration_days
    $severity = if ($hours -ge 168) { "Critical" } elseif ($hours -ge 120) { "High" } elseif ($hours -ge 72) { "Medium" } else { "Low" }

    [PSCustomObject]@{
        object_id = $_.object_id
        object_name = $_.object_name
        object_type = $_.object_type
        last_modified = $_.last_modified
        checked_out_by = $_.checked_out_by
        user_id = $_.user_id
        checkout_duration_hours = $hours
        checkout_duration_days = $days
        severity = $severity
        flagged = ($hours -ge 72)
    }
}

$results.bottleneckQueue = $results.staleCheckouts |
    Where-Object { $_.flagged } |
    Group-Object -Property checked_out_by |
    ForEach-Object {
        [PSCustomObject]@{
            user_name = $_.Name
            checkout_count = $_.Count
            total_hours = ($_.Group | Measure-Object -Property checkout_duration_hours -Sum).Sum
            items = $_.Group | ForEach-Object {
                [PSCustomObject]@{
                    object_name = $_.object_name
                    object_type = $_.object_type
                    duration_hours = $_.checkout_duration_hours
                }
            }
        }
    } |
    Sort-Object -Property total_hours -Descending

Write-Host "  Found $($results.staleCheckouts.Count) stale checkouts" -ForegroundColor Green
Write-Host "  Identified $($results.bottleneckQueue.Count) users with stale checkouts" -ForegroundColor Green

# Close database connection
$connection.Close()
$connection.Dispose()

# ========================================
# Tree Snapshot Collection
# ========================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Tree Snapshot Collection" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$treeEvidence = @()
$treeEvidenceEnabled = $false
if (Get-Command -Name New-TreeEvidenceBlock -ErrorAction SilentlyContinue) {
    $treeEvidenceEnabled = $true
} else {
    Write-Warning "Tree evidence classifier not available; tree changes will be raw."
}

$treeSnapshotDir = Join-Path (Get-Location).Path "data\tree-snapshots"
if (-not (Test-Path $treeSnapshotDir)) {
    New-Item -ItemType Directory -Path $treeSnapshotDir -Force | Out-Null
}

$treeExportScript = Join-Path $PSScriptRoot "..\..\..\scripts\debug\export-study-tree-snapshot.ps1"
$treeDiffScript = Join-Path $PSScriptRoot "..\..\..\scripts\debug\compare-study-tree-snapshots.ps1"

if ($SkipTreeSnapshots) {
    Write-Warning "Tree snapshot collection skipped (SkipTreeSnapshots enabled)."
} elseif (-not (Test-Path $treeExportScript) -or -not (Test-Path $treeDiffScript)) {
    Write-Warning "Tree snapshot scripts not found; skipping tree change collection."
} else {
    $treeCheckoutMap = @{}
    $treeWriteMap = @{}
    foreach ($study in $results.studySummary) {
        $studyId = [string]$study.study_id
        if ([int]$study.checkout_working_version_id -gt 0) {
            $treeCheckoutMap[$studyId] = $true
        }

        $lastModifiedDate = Convert-StringToDateTime -Value $study.last_modified
        if (Test-DateInRange -Value $lastModifiedDate -Start $StartDate -End $EndDate) {
            $treeWriteMap[$studyId] = $true
        }
    }

    $snapshotAttempts = 0
    $snapshotErrors = 0
    $snapshotSkipped = 0

    foreach ($study in $results.studySummary) {
        $studyId = [string]$study.study_id
        $studyName = $study.study_name

        $hasCheckout = $treeCheckoutMap.ContainsKey($studyId)
        $hasWrite = $treeWriteMap.ContainsKey($studyId)

        if (-not $hasCheckout -and -not $hasWrite) {
            $snapshotSkipped++
            continue
        }

        if ($TreeSnapshotLimit -gt 0 -and $snapshotAttempts -ge $TreeSnapshotLimit) {
            Write-Warning "Tree snapshot limit reached ($TreeSnapshotLimit). Skipping remaining studies."
            break
        }

        $snapshotAttempts++
        Write-Host "  Processing: $studyName (ID: $studyId)" -ForegroundColor Gray

        $snapshotPath = Join-Path $treeSnapshotDir "$studyId.json"
        $previousSnapshotPath = Join-Path $treeSnapshotDir "$studyId.previous.json"

        $currentSnapshot = $null
        if (Test-Path $snapshotPath) {
            if (Test-Path $previousSnapshotPath) {
                Remove-Item $previousSnapshotPath -Force -ErrorAction SilentlyContinue
            }
            Copy-Item -Path $snapshotPath -Destination $previousSnapshotPath -Force -ErrorAction SilentlyContinue
        }

        try {
            # Export to temp dir then move to target location for consistent naming
            $tempDir = Join-Path $env:TEMP "study-snapshots-$(Get-Random)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            
            & $treeExportScript -TNSName $TNSName -Schema $Schema -ProjectId $ProjectId -StudyId $studyId -OutputDir $tempDir -ErrorAction Stop
            
            # Find the generated snapshot file and move it to the target location
            $generatedFiles = Get-ChildItem -Path $tempDir -Filter "study-tree-snapshot-*.json" -ErrorAction SilentlyContinue
            if ($generatedFiles -and $generatedFiles.Count -gt 0) {
                $latestFile = $generatedFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                Move-Item -Path $latestFile.FullName -Destination $snapshotPath -Force
                $currentSnapshot = Get-Content $snapshotPath -Raw | ConvertFrom-Json
                $snapshotStatusIndex[$studyId] = "ok"
            } else {
                Write-Warning "    No snapshot file generated"
                $snapshotErrors++
                $snapshotStatusIndex[$studyId] = "error"
            }
            
            # Clean up temp directory
            Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "    Failed to export tree snapshot: $_"
            $snapshotErrors++
            $snapshotStatusIndex[$studyId] = "error"
            if ($TreeSnapshotErrorLimit -gt 0 -and $snapshotErrors -ge $TreeSnapshotErrorLimit) {
                Write-Warning "Tree snapshot error limit reached ($TreeSnapshotErrorLimit). Stopping snapshot collection."
                break
            }
        }

        if ($treeEvidenceEnabled -and $currentSnapshot) {
            $treeEvidenceBlock = New-TreeEvidenceBlock `
                -StudyId $studyId `
                -StudyName $studyName `
                -HasCheckout $hasCheckout `
                -HasWrite $hasWrite `
                -CurrentSnapshot $currentSnapshot `
                -PreviousSnapshotPath $previousSnapshotPath

            if ($treeEvidenceBlock) {
                $treeEvidence += $treeEvidenceBlock
            }
        }
    }

    Write-Host "  Tree snapshots attempted: $snapshotAttempts (skipped: $snapshotSkipped, errors: $snapshotErrors)" -ForegroundColor Gray
}

$results.treeChanges = $treeEvidence

# ========================================
# Property Normalization
# ========================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Normalizing Output" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

function ConvertTo-LowercaseProperties {
    param($InputObject)

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [Array]) {
        return $InputObject | ForEach-Object { ConvertTo-LowercaseProperties $_ }
    }

    if ($InputObject -is [hashtable]) {
        $newObj = @{}
        foreach ($key in $InputObject.Keys) {
            $lowercaseKey = $key.ToString().ToLower()
            $newObj[$lowercaseKey] = ConvertTo-LowercaseProperties $InputObject[$key]
        }
        return $newObj
    }

    if ($InputObject -is [PSCustomObject]) {
        $newObj = @{}
        $InputObject.PSObject.Properties | ForEach-Object {
            $lowercaseKey = $_.Name.ToLower()
            $newObj[$lowercaseKey] = ConvertTo-LowercaseProperties $_.Value
        }
        return [PSCustomObject]$newObj
    }

    return $InputObject
}

Write-Host "  Converting property names to lowercase..." -ForegroundColor Yellow
$results = ConvertTo-LowercaseProperties $results
Write-Host "  Normalization complete" -ForegroundColor Green

# ========================================
# Save Results
# ========================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Saving Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$outputPath = [System.IO.Path]::GetFullPath($OutputFile)
$outputDir = [System.IO.Path]::GetDirectoryName($outputPath)
if ([string]::IsNullOrWhiteSpace($outputDir)) {
    $outputDir = (Get-Location).Path
}
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Determine file naming pattern (support both legacy and new patterns)
$outputName = [System.IO.Path]::GetFileNameWithoutExtension($outputPath)
$outputExt = [System.IO.Path]::GetExtension($outputPath)

# If output file doesn't end with -latest, construct versioned names
$latestFile = if ($outputName -match '-latest$') {
    $outputPath
} else {
    Join-Path $outputDir "management-data-${Schema}-${ProjectId}-latest${outputExt}"
}

$prevFile = $latestFile -replace '-latest', '-prev'
$runStateFile = Join-Path $outputDir "run-state-${Schema}-${ProjectId}.json"

# Load previous run state (if exists)
$runState = if (Test-Path $runStateFile) {
    Get-Content $runStateFile -Raw | ConvertFrom-Json
} else {
    @{
        runHistory = @()
    }
}

# If latest file exists, rotate it to prev
$prevRunAt = $null
if (Test-Path $latestFile) {
    Write-Host "  Rotating latest -> prev..." -ForegroundColor Gray
    
    # Read metadata from current latest to get its timestamp
    try {
        $latestContent = Get-Content $latestFile -Raw | ConvertFrom-Json
        $prevRunAt = $latestContent.metadata.generatedAt
    } catch {
        Write-Warning "  Could not read timestamp from existing latest file"
    }
    
    # Copy latest to prev (overwrite if prev exists)
    if (Test-Path $prevFile) {
        Remove-Item $prevFile -Force
    }
    Copy-Item $latestFile $prevFile -Force
    Write-Host "  Previous run backed up" -ForegroundColor Green
}

# Add performance summary
$scriptTimer.Stop()
$results.performance.totalTime = [math]::Round($scriptTimer.Elapsed.TotalSeconds, 2)

# Prepare run metadata for the new run
$currentRunAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
$runId = (Get-Date).ToString('yyyyMMdd-HHmmss')

# Update run state
$runState.latestRunAt = $currentRunAt
$runState.latestRunId = $runId
$runState.latestFile = $latestFile
if ($prevRunAt) {
    $runState.prevRunAt = $prevRunAt
    $runState.prevFile = $prevFile
}

# Add to history (keep last 10)
$runState.runHistory = @($runState.runHistory | Select-Object -Last 9) + @{
    runAt = $currentRunAt
    runId = $runId
    file = $latestFile
    schema = $Schema
    projectId = $ProjectId
}

# Convert to JSON with optimized depth
$jsonText = $results | ConvertTo-Json -Depth 5

# Fix single-element array serialization
$jsonText = $jsonText -replace '"studysummary":\s*\{', '"studysummary": [{'
$jsonText = $jsonText -replace '("studysummary":\s*\[\{[^\}]+\})\s*,\s*"', '$1],  "'

# Write to temp file first
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$tempFile = Join-Path $outputDir ("management-data-${Schema}-${ProjectId}.tmp-$timestamp${outputExt}")
$jsonText | Out-File $tempFile -Encoding UTF8 -Force

# Move temp to latest
try {
    if (Test-Path $latestFile) {
        Remove-Item -Path $latestFile -Force -ErrorAction Stop
    }
    Move-Item -Path $tempFile -Destination $latestFile -ErrorAction Stop
    Write-Host "  Results saved to: $latestFile" -ForegroundColor Green
} catch {
    Write-Warning "  Could not write to latest file; keeping temp file: $tempFile"
}

# Save run state
$runStateJson = $runState | ConvertTo-Json -Depth 3
$runStateJson | Out-File $runStateFile -Encoding UTF8 -Force
Write-Host "  Run state updated: $runStateFile" -ForegroundColor Green

# ========================================
# Compute Previous Run Diff
# ========================================
if (Test-Path $prevFile) {
    Write-Host "`n  Computing changes since previous run..." -ForegroundColor Cyan
    
    $diffScriptPath = Join-Path $scriptRootDir "scripts\compute-prev-diff.ps1"
    if (Test-Path $diffScriptPath) {
        try {
            # Run diff computation
            $diffResult = & $diffScriptPath -PrevFile $prevFile -LatestFile $latestFile
            
            if ($diffResult -and $diffResult.compareMeta) {
                # Add compareMeta to results metadata
                $results.metadata | Add-Member -NotePropertyName "compareMeta" -NotePropertyValue $diffResult.compareMeta -Force
                
                # Add changedSincePrev and changeReasons to each study
                foreach ($study in $results.studySummary) {
                    $studyId = $study.OBJECT_ID
                    if ($diffResult.studyChanges.ContainsKey($studyId)) {
                        $changeInfo = $diffResult.studyChanges[$studyId]
                        $study | Add-Member -NotePropertyName "changedSincePrev" -NotePropertyValue $changeInfo.changed -Force
                        $study | Add-Member -NotePropertyName "changeReasons" -NotePropertyValue $changeInfo.reasons -Force
                    } else {
                        # Study not in diff (shouldn't happen, but handle gracefully)
                        $study | Add-Member -NotePropertyName "changedSincePrev" -NotePropertyValue $false -Force
                        $study | Add-Member -NotePropertyName "changeReasons" -NotePropertyValue @() -Force
                    }
                }
                
                # Re-save latest file with diff data
                $jsonTextWithDiff = $results | ConvertTo-Json -Depth 5
                $jsonTextWithDiff = $jsonTextWithDiff -replace '"studysummary":\s*\{', '"studysummary": [{'
                $jsonTextWithDiff = $jsonTextWithDiff -replace '("studysummary":\s*\[\{[^\}]+\})\s*,\s*"', '$1],  "'
                $jsonTextWithDiff | Out-File $latestFile -Encoding UTF8 -Force
                
                Write-Host "  Changed studies: $($diffResult.compareMeta.changedStudyCount) / $($diffResult.compareMeta.totalStudyCount)" -ForegroundColor Green
            }
        } catch {
            Write-Warning "  Failed to compute diff: $_"
            # Add empty compareMeta to indicate diff was attempted but failed
            $results.metadata | Add-Member -NotePropertyName "compareMeta" -NotePropertyValue @{
                mode = "diff_failed"
                error = $_.ToString()
            } -Force
        }
    } else {
        Write-Warning "  Diff script not found: $diffScriptPath"
    }
} else {
    Write-Host "`n  No previous run found - this is the first run" -ForegroundColor Gray
    # Add compareMeta indicating no previous run
    $results.metadata | Add-Member -NotePropertyName "compareMeta" -NotePropertyValue @{
        mode = "no_previous_run"
        noPreviousRun = $true
    } -Force
    
    # Set all studies to not changed
    foreach ($study in $results.studySummary) {
        $study | Add-Member -NotePropertyName "changedSincePrev" -NotePropertyValue $false -Force
        $study | Add-Member -NotePropertyName "changeReasons" -NotePropertyValue @() -Force
    }
    
    # Re-save with these fields
    $jsonTextWithDiff = $results | ConvertTo-Json -Depth 5
    $jsonTextWithDiff = $jsonTextWithDiff -replace '"studysummary":\s*\{', '"studysummary": [{'
    $jsonTextWithDiff = $jsonTextWithDiff -replace '("studysummary":\s*\[\{[^\}]+\})\s*,\s*"', '$1],  "'
    $jsonTextWithDiff | Out-File $latestFile -Encoding UTF8 -Force
}

# Also write to legacy location for backward compatibility
$legacyFile = Join-Path $outputDir "management-data-${Schema}-${ProjectId}${outputExt}"
if ($legacyFile -ne $latestFile) {
    Copy-Item $latestFile $legacyFile -Force
    Write-Host "  Legacy file updated: $legacyFile" -ForegroundColor Gray
}

$finalOutput = $latestFile

# ========================================
# Performance Summary
# ========================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Performance Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "  Total execution time: $($results.performance.totalTime)s" -ForegroundColor Green

$cacheHits = ($jobs.Values | Where-Object { $_.Cached }).Count
$totalQueries = $jobs.Count
Write-Host "  Cache hits: $cacheHits / $totalQueries" -ForegroundColor $(if ($cacheHits -gt 0) { "Green" } else { "Gray" })

$slowestQuery = $results.performance.queryTimes.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 1
if ($slowestQuery) {
    Write-Host "  Slowest query: $($slowestQuery.Key) ($($slowestQuery.Value)ms)" -ForegroundColor Yellow
}

Write-Host ""

# Explicitly exit with success code
exit 0
