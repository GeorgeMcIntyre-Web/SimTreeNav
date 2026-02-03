<#
.SYNOPSIS
    SQL*Plus Helper - Direct Oracle queries using SQL*Plus
.DESCRIPTION
    Alternative to Oracle.ManagedDataAccess.dll that uses SQL*Plus directly.
    More reliable when managed driver has issues.
#>

function Invoke-SqlPlusQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,

        [Parameter(Mandatory=$true)]
        [string]$Username,

        [Parameter(Mandatory=$true)]
        [string]$Password,

        [Parameter(Mandatory=$true)]
        [string]$Query,

        [Parameter(Mandatory=$false)]
        [ValidateSet("SYSDBA", "SYSOPER", "None")]
        [string]$DBAPrivilege = "None",

        [Parameter(Mandatory=$false)]
        [int]$TimeoutSeconds = 30
    )

    try {
        # Build connection string
        $connString = "${Username}/${Password}@${TNSName}"
        if ($DBAPrivilege -ne "None") {
            $connString += " as $DBAPrivilege"
        }

        # Create temp SQL file with query only (no CONNECT - passed as argument)
        $tempSql = [System.IO.Path]::GetTempFileName() + ".sql"
        $sqlContent = @"
SET PAGESIZE 0
SET FEEDBACK OFF
SET HEADING ON
SET LINESIZE 32767
SET TRIMOUT ON
SET TRIMSPOOL ON
SET COLSEP '|'
SET UNDERLINE OFF

$Query

EXIT;
"@
        $sqlContent | Out-File $tempSql -Encoding ASCII

        # Execute with timeout
        Write-Verbose "Executing SQL*Plus query (timeout: ${TimeoutSeconds}s)..."

        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "sqlplus"
        # Pass connection string as argument, then script file
        $processInfo.Arguments = "-S $connString @`"$tempSql`""
        $processInfo.UseShellExecute = $false
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo

        $process.Start() | Out-Null

        # Read output synchronously (simpler and more reliable)
        $outputText = $process.StandardOutput.ReadToEnd()
        $errorText = $process.StandardError.ReadToEnd()

        $completed = $process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $completed) {
            $process.Kill()
            throw "Query timed out after ${TimeoutSeconds} seconds"
        }

        # Clean up temp file
        Remove-Item $tempSql -Force -ErrorAction SilentlyContinue

        if ($process.ExitCode -ne 0) {
            throw "SQL*Plus error (exit code $($process.ExitCode)): $errorText"
        }

        # Debug: Show raw output
        Write-Verbose "Raw output length: $($outputText.Length) chars"
        if ($outputText.Length -lt 500) {
            Write-Verbose "Raw output:`n$outputText"
        }

        # Parse pipe-delimited output
        $lines = $outputText -split "`r?`n" | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            $_ -match '\|' -and
            $_ -notmatch '^[\s\-\|]+$'
        }

        Write-Verbose "Found $($lines.Count) parseable lines"

        if ($lines.Count -lt 1) {
            Write-Verbose "No pipe-delimited data found"
            # Try parsing non-delimited output (fallback)
            $lines = $outputText -split "`r?`n" | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -notmatch '^[\s\-]+$'
            }

            if ($lines.Count -ge 2) {
                Write-Verbose "Using non-delimited format (headers + data)"
                # Assume first line is header, rest are data rows
                $header = $lines[0].Trim()
                $results = @()
                foreach ($line in $lines[1..($lines.Count - 1)]) {
                    $value = $line.Trim()
                    $results += [PSCustomObject]@{ $header = $value }
                }
                return $results
            }

            return @()
        }

        # First line is headers
        $headers = $lines[0] -split '\|' | ForEach-Object { $_.Trim() }

        # Subsequent lines are data
        $results = @()
        foreach ($line in $lines[1..($lines.Count - 1)]) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }

            $values = $line -split '\|', $headers.Count
            $row = @{}

            for ($i = 0; $i -lt $headers.Count; $i++) {
                $value = if ($i -lt $values.Count) { $values[$i].Trim() } else { "" }
                $row[$headers[$i]] = $value
            }

            $results += [PSCustomObject]$row
        }

        Write-Verbose "Query returned $($results.Count) rows"
        return $results

    } catch {
        Write-Error "SQL*Plus query failed: $_"
        return $null
    } finally {
        # Cleanup
        if (Test-Path $tempSql) {
            Remove-Item $tempSql -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-SqlPlusConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$TNSName,

        [Parameter(Mandatory=$true)]
        [string]$Username,

        [Parameter(Mandatory=$true)]
        [string]$Password,

        [Parameter(Mandatory=$false)]
        [ValidateSet("SYSDBA", "SYSOPER", "None")]
        [string]$DBAPrivilege = "None"
    )

    $query = "SELECT 'OK' as status FROM DUAL"
    $result = Invoke-SqlPlusQuery -TNSName $TNSName -Username $Username -Password $Password -Query $query -DBAPrivilege $DBAPrivilege -TimeoutSeconds 10

    return ($null -ne $result -and $result.Count -gt 0)
}
