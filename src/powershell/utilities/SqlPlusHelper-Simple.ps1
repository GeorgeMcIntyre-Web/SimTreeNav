<#
.SYNOPSIS
    Simple SQL*Plus Helper using PowerShell native execution
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

        # Create temp SQL file
        $tempSql = [System.IO.Path]::GetTempFileName() + ".sql"

        # Ensure query ends with semicolon
        $queryText = $Query.Trim()
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

        Write-Verbose "Temp SQL file: $tempSql"
        Write-Verbose "Connection string: $($connString -replace '/[^@]+@', '/***@')"

        # Execute using PowerShell's native call operator with timeout
        $job = Start-Job -ScriptBlock {
            param($ConnStr, $SqlFile)
            & sqlplus -S $ConnStr "@$SqlFile" 2>&1
        } -ArgumentList $connString, $tempSql

        # Wait with timeout
        $completed = Wait-Job $job -Timeout $TimeoutSeconds

        if (-not $completed) {
            Stop-Job $job
            Remove-Job $job -Force
            Remove-Item $tempSql -Force -ErrorAction SilentlyContinue
            throw "Query timed out after ${TimeoutSeconds} seconds"
        }

        $output = Receive-Job $job
        Remove-Job $job -Force

        # Clean up
        Remove-Item $tempSql -Force -ErrorAction SilentlyContinue

        # Convert output to string
        $outputText = ($output | Out-String).Trim()

        Write-Verbose "Raw output length: $($outputText.Length) chars"
        if ($outputText.Length -lt 500) {
            Write-Verbose "Raw output:`n$outputText"
        }

        if ([string]::IsNullOrWhiteSpace($outputText)) {
            Write-Verbose "No output returned"
            return @()
        }

        # Check for errors
        if ($outputText -match 'ORA-\d+' -or $outputText -match 'ERROR') {
            throw "SQL*Plus error: $outputText"
        }

        # Parse pipe-delimited output
        $lines = $outputText -split "`r?`n" | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            $_ -match '\|' -and
            $_ -notmatch '^[\s\-\|]+$'
        }

        Write-Verbose "Found $($lines.Count) pipe-delimited lines"

        if ($lines.Count -lt 1) {
            Write-Verbose "No pipe-delimited data, trying simple parse"
            # Simple fallback: just return lines as single-column data
            $lines = $outputText -split "`r?`n" | Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                $_ -notmatch '^[\s\-]+$'
            }

            if ($lines.Count -ge 2) {
                $header = $lines[0].Trim()
                $results = @()
                foreach ($line in $lines[1..($lines.Count - 1)]) {
                    $value = $line.Trim()
                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        $results += [PSCustomObject]@{ $header = $value }
                    }
                }
                return $results
            }

            return @()
        }

        # Parse pipe-delimited format
        $headers = $lines[0] -split '\|' | ForEach-Object { $_.Trim() }
        Write-Verbose "Headers: $($headers -join ', ')"

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

        Write-Verbose "Parsed $($results.Count) result rows"
        return $results

    } catch {
        Write-Error "SQL*Plus query failed: $_"
        return $null
    } finally {
        if (Test-Path $tempSql -ErrorAction SilentlyContinue) {
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

    $query = "SELECT 'OK' as status FROM DUAL;"
    $result = Invoke-SqlPlusQuery -TNSName $TNSName -Username $Username -Password $Password -Query $query -DBAPrivilege $DBAPrivilege -TimeoutSeconds 10 -Verbose:$VerbosePreference

    return ($null -ne $result -and $result.Count -gt 0)
}
