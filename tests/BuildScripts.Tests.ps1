<#
.SYNOPSIS
    Tests for build and release scripts.

.DESCRIPTION
    Validates that build scripts are properly configured and can execute.
#>

BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    $ScriptsPath = Join-Path $ProjectRoot "scripts"
}

Describe "Build-Release.ps1" {
    
    Context "Script Validation" {
        BeforeAll {
            $BuildScript = Join-Path $ScriptsPath "Build-Release.ps1"
        }
        
        It "Should exist" {
            Test-Path $BuildScript | Should -BeTrue
        }
        
        It "Should be valid PowerShell" {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $BuildScript,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0 -Because "Script has syntax errors"
        }
        
        It "Should have CmdletBinding" {
            $content = Get-Content $BuildScript -Raw
            $content | Should -Match '\[CmdletBinding\(\)\]'
        }
        
        It "Should have OutputPath parameter" {
            $content = Get-Content $BuildScript -Raw
            $content | Should -Match '\$OutputPath'
        }
    }
}

Describe "Verify-Release.ps1" {
    
    Context "Script Validation" {
        BeforeAll {
            $VerifyScript = Join-Path $ScriptsPath "Verify-Release.ps1"
        }
        
        It "Should exist" {
            Test-Path $VerifyScript | Should -BeTrue
        }
        
        It "Should be valid PowerShell" {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $VerifyScript,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0 -Because "Script has syntax errors"
        }
        
        It "Should have PackagePath parameter" {
            $content = Get-Content $VerifyScript -Raw
            $content | Should -Match '\$PackagePath'
        }
    }
}

Describe "New-Changelog.ps1" {
    
    Context "Script Validation" {
        BeforeAll {
            $ChangelogScript = Join-Path $ScriptsPath "New-Changelog.ps1"
        }
        
        It "Should exist" {
            Test-Path $ChangelogScript | Should -BeTrue
        }
        
        It "Should be valid PowerShell" {
            $errors = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                $ChangelogScript,
                [ref]$null,
                [ref]$errors
            )
            $errors.Count | Should -Be 0 -Because "Script has syntax errors"
        }
        
        It "Should support Version parameter" {
            $content = Get-Content $ChangelogScript -Raw
            $content | Should -Match '\$Version'
        }
    }
}

Describe "PSScriptAnalyzer Settings" {
    
    Context "Settings File" {
        BeforeAll {
            $SettingsPath = Join-Path $ProjectRoot "PSScriptAnalyzerSettings.psd1"
        }
        
        It "Should exist" {
            Test-Path $SettingsPath | Should -BeTrue
        }
        
        It "Should be valid PSD1" {
            { Import-PowerShellDataFile $SettingsPath } | Should -Not -Throw
        }
        
        It "Should have Severity setting" {
            $settings = Import-PowerShellDataFile $SettingsPath
            $settings.Severity | Should -Not -BeNullOrEmpty
        }
        
        It "Should include security rules" {
            $settings = Import-PowerShellDataFile $SettingsPath
            $hasSecurityRules = $settings.IncludeRules | Where-Object { $_ -match 'Password|Credential|SecureString' }
            $hasSecurityRules | Should -Not -BeNullOrEmpty
        }
    }
}
