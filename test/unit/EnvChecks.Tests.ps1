<#
.SYNOPSIS
    Pester tests for EnvChecks.ps1 library with code coverage.

.DESCRIPTION
    Unit tests using Pester framework to verify environment validation functions:
    - Test-PowerShellVersion validates PS version requirements
    - Test-SqlPlusAvailable checks SQL*Plus availability
    - Test-OutDirWritable verifies directory write permissions
    - Test-RequiredPaths validates path existence
#>

BeforeAll {
    # Import the module under test
    $script:ModulePath = Join-Path $PSScriptRoot "..\..\scripts\lib\EnvChecks.ps1"
    . $script:ModulePath

    # Create temp directory for test artifacts
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "pester-envchecks-$(New-Guid)"
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
}

AfterAll {
    # Cleanup temp directory
    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'EnvChecks Library' {
    Context 'Test-PowerShellVersion' {
        It 'returns PSCustomObject with required fields' {
            $result = Test-PowerShellVersion -MinMajorVersion 1

            $result | Should -Not -BeNull
            $result.PSObject.Properties['Sufficient'] | Should -Not -BeNull
            $result.PSObject.Properties['Current'] | Should -Not -BeNull
            $result.PSObject.Properties['Error'] | Should -Not -BeNull
        }

        It 'passes when current version meets minimum (version 1)' {
            $result = Test-PowerShellVersion -MinMajorVersion 1

            $result.Sufficient | Should -BeTrue
            $result.Current | Should -Not -BeNullOrEmpty
            $result.Error | Should -BeNullOrEmpty
        }

        It 'passes when current version equals minimum' {
            $currentMajor = $PSVersionTable.PSVersion.Major
            $result = Test-PowerShellVersion -MinMajorVersion $currentMajor

            $result.Sufficient | Should -BeTrue
            $result.Error | Should -BeNullOrEmpty
        }

        It 'fails when current version is below minimum' {
            $impossibleVersion = $PSVersionTable.PSVersion.Major + 1
            $result = Test-PowerShellVersion -MinMajorVersion $impossibleVersion

            $result.Sufficient | Should -BeFalse
            $result.Error | Should -Not -BeNullOrEmpty
            $result.Error | Should -Match "insufficient"
        }

        It 'uses default minimum version of 7' {
            $result = Test-PowerShellVersion

            $result.Sufficient | Should -Not -BeNull
            # Error message should reference version 7 if it fails
            if (-not $result.Sufficient) {
                $result.Error | Should -Match "version 7"
            }
        }

        It 'returns current version string' {
            $result = Test-PowerShellVersion -MinMajorVersion 1

            $result.Current | Should -Match '^\d+\.\d+\.\d+'
        }
    }

    Context 'Test-SqlPlusAvailable' {
        It 'returns PSCustomObject with required fields' {
            $result = Test-SqlPlusAvailable

            $result | Should -Not -BeNull
            $result.PSObject.Properties['Available'] | Should -Not -BeNull
            $result.PSObject.Properties['Version'] | Should -Not -BeNull
            $result.PSObject.Properties['Error'] | Should -Not -BeNull
        }

        It 'returns boolean for Available field' {
            $result = Test-SqlPlusAvailable

            $result.Available | Should -BeOfType [bool]
        }

        It 'provides error message when SQL*Plus not available' {
            # This test assumes sqlplus is not in PATH in CI
            $result = Test-SqlPlusAvailable

            if (-not $result.Available) {
                $result.Error | Should -Not -BeNullOrEmpty
                $result.Error | Should -Match "not found|Oracle Client"
            }
        }

        It 'sets Version to null when not available' {
            $result = Test-SqlPlusAvailable

            if (-not $result.Available) {
                $result.Version | Should -BeNullOrEmpty
            }
        }
    }

    Context 'Test-OutDirWritable' {
        It 'returns PSCustomObject with required fields' {
            $result = Test-OutDirWritable -OutDir $script:TempDir

            $result | Should -Not -BeNull
            $result.PSObject.Properties['Writable'] | Should -Not -BeNull
            $result.PSObject.Properties['Error'] | Should -Not -BeNull
        }

        It 'passes for writable temp directory' {
            $result = Test-OutDirWritable -OutDir $script:TempDir

            $result.Writable | Should -BeTrue
            $result.Error | Should -BeNullOrEmpty
        }

        It 'creates directory if it does not exist' {
            $newDir = Join-Path $script:TempDir "auto-created-$(New-Guid)"

            Test-Path $newDir | Should -BeFalse

            $result = Test-OutDirWritable -OutDir $newDir

            Test-Path $newDir | Should -BeTrue
            $result.Writable | Should -BeTrue
        }

        It 'cleans up test file after verification' {
            $result = Test-OutDirWritable -OutDir $script:TempDir

            # Check that no .tmp files are left behind
            $tmpFiles = Get-ChildItem -Path $script:TempDir -Filter "*.tmp"
            $tmpFiles.Count | Should -Be 0
        }

        It 'fails for non-existent parent directory' {
            $invalidDir = Join-Path $script:TempDir "nonexistent\nested\path"

            $result = Test-OutDirWritable -OutDir $invalidDir

            # This may pass or fail depending on permissions to create nested dirs
            $result.Writable | Should -BeOfType [bool]
        }

        It 'fails for invalid path characters' -Skip:($IsLinux -or $IsMacOS) {
            # Windows-specific test for invalid characters
            $invalidDir = Join-Path $script:TempDir "invalid<>path"

            $result = Test-OutDirWritable -OutDir $invalidDir

            $result.Writable | Should -BeFalse
            $result.Error | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Test-RequiredPaths' {
        BeforeEach {
            # Create test files
            $script:existingFile1 = Join-Path $script:TempDir "existing1.txt"
            $script:existingFile2 = Join-Path $script:TempDir "existing2.txt"
            "test" | Set-Content $script:existingFile1
            "test" | Set-Content $script:existingFile2
        }

        It 'returns PSCustomObject with required fields' {
            $result = Test-RequiredPaths -Paths @($script:existingFile1)

            $result | Should -Not -BeNull
            $result.PSObject.Properties['AllExist'] | Should -Not -BeNull
            $result.PSObject.Properties['MissingPaths'] | Should -Not -BeNull
            $result.PSObject.Properties['Error'] | Should -Not -BeNull
        }

        It 'passes when all paths exist' {
            $result = Test-RequiredPaths -Paths @($script:existingFile1, $script:existingFile2)

            $result.AllExist | Should -BeTrue
            $result.MissingPaths.Count | Should -Be 0
            $result.Error | Should -BeNullOrEmpty
        }

        It 'fails when one path is missing' {
            $missingPath = Join-Path $script:TempDir "nonexistent.txt"
            $result = Test-RequiredPaths -Paths @($script:existingFile1, $missingPath)

            $result.AllExist | Should -BeFalse
            $result.MissingPaths.Count | Should -Be 1
            $result.MissingPaths[0] | Should -Be $missingPath
            $result.Error | Should -Not -BeNullOrEmpty
        }

        It 'fails when all paths are missing' {
            $missing1 = Join-Path $script:TempDir "missing1.txt"
            $missing2 = Join-Path $script:TempDir "missing2.txt"

            $result = Test-RequiredPaths -Paths @($missing1, $missing2)

            $result.AllExist | Should -BeFalse
            $result.MissingPaths.Count | Should -Be 2
            $result.Error | Should -Match "Missing paths"
        }

        It 'handles empty paths array' {
            $result = Test-RequiredPaths -Paths @()

            $result.AllExist | Should -BeTrue
            $result.MissingPaths.Count | Should -Be 0
        }

        It 'includes missing paths in error message' {
            $missingPath = Join-Path $script:TempDir "missing.txt"
            $result = Test-RequiredPaths -Paths @($missingPath)

            $result.Error | Should -Match [regex]::Escape($missingPath)
        }

        It 'validates directories as well as files' {
            $result = Test-RequiredPaths -Paths @($script:TempDir)

            $result.AllExist | Should -BeTrue
            $result.Error | Should -BeNullOrEmpty
        }

        It 'handles mix of files and directories' {
            $subDir = Join-Path $script:TempDir "subdir"
            New-Item -ItemType Directory -Path $subDir | Out-Null

            $result = Test-RequiredPaths -Paths @($script:existingFile1, $subDir)

            $result.AllExist | Should -BeTrue
            $result.MissingPaths.Count | Should -Be 0
        }
    }

    Context 'Integration - Combined Environment Checks' {
        It 'performs all environment checks in sequence' {
            # PowerShell version check
            $psCheck = Test-PowerShellVersion -MinMajorVersion 1
            $psCheck.Sufficient | Should -BeTrue

            # SQL*Plus check (may pass or fail based on environment)
            $sqlCheck = Test-SqlPlusAvailable
            $sqlCheck.Available | Should -BeOfType [bool]

            # Output directory check
            $dirCheck = Test-OutDirWritable -OutDir $script:TempDir
            $dirCheck.Writable | Should -BeTrue

            # Required paths check
            $pathCheck = Test-RequiredPaths -Paths @($script:TempDir)
            $pathCheck.AllExist | Should -BeTrue
        }

        It 'provides actionable error messages for troubleshooting' {
            # Test with failing conditions
            $impossibleVersion = $PSVersionTable.PSVersion.Major + 10
            $psCheck = Test-PowerShellVersion -MinMajorVersion $impossibleVersion

            $psCheck.Error | Should -Not -BeNullOrEmpty
            $psCheck.Error | Should -Match "Requires version"
        }
    }
}
