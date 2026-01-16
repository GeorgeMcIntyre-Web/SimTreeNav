<#
.SYNOPSIS
    Tests for project structure validity.

.DESCRIPTION
    Validates that all required files and directories exist
    and are properly organized.
#>

BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

Describe "Project Structure" {
    
    Context "Root Files" {
        $RequiredFiles = @(
            "README.md",
            "CHANGELOG.md",
            "CONTRIBUTING.md",
            "SECURITY.md",
            "manifest.json",
            "PSScriptAnalyzerSettings.psd1"
        )
        
        foreach ($file in $RequiredFiles) {
            It "Should have $file" {
                $path = Join-Path $ProjectRoot $file
                Test-Path $path | Should -BeTrue
            }
        }
    }
    
    Context "Source Directory Structure" {
        $RequiredDirs = @(
            "src/powershell/main",
            "src/powershell/database",
            "src/powershell/utilities"
        )
        
        foreach ($dir in $RequiredDirs) {
            It "Should have $dir directory" {
                $path = Join-Path $ProjectRoot $dir
                Test-Path $path | Should -BeTrue
            }
        }
    }
    
    Context "Documentation" {
        $RequiredDocs = @(
            "docs/ARCHITECTURE.md",
            "docs/FEATURES.md",
            "docs/DEPLOYMENT.md",
            "docs/ROADMAP.md"
        )
        
        foreach ($doc in $RequiredDocs) {
            It "Should have $doc" {
                $path = Join-Path $ProjectRoot $doc
                Test-Path $path | Should -BeTrue
            }
        }
    }
    
    Context "GitHub Configuration" {
        It "Should have .github/workflows directory" {
            $path = Join-Path $ProjectRoot ".github/workflows"
            Test-Path $path | Should -BeTrue
        }
        
        It "Should have CI workflow" {
            $path = Join-Path $ProjectRoot ".github/workflows/ci.yml"
            Test-Path $path | Should -BeTrue
        }
        
        It "Should have issue templates" {
            $path = Join-Path $ProjectRoot ".github/ISSUE_TEMPLATE"
            Test-Path $path | Should -BeTrue
        }
    }
    
    Context "Scripts Directory" {
        $RequiredScripts = @(
            "scripts/Build-Release.ps1",
            "scripts/Verify-Release.ps1",
            "scripts/New-Changelog.ps1"
        )
        
        foreach ($script in $RequiredScripts) {
            It "Should have $script" {
                $path = Join-Path $ProjectRoot $script
                Test-Path $path | Should -BeTrue
            }
        }
    }
}

Describe "PowerShell Scripts" {
    
    Context "Main Scripts" {
        BeforeAll {
            $MainScripts = Get-ChildItem -Path (Join-Path $ProjectRoot "src/powershell/main") -Filter "*.ps1"
        }
        
        It "Should have at least one main script" {
            $MainScripts.Count | Should -BeGreaterThan 0
        }
        
        It "Should have tree-viewer-launcher.ps1" {
            $launcher = $MainScripts | Where-Object { $_.Name -eq "tree-viewer-launcher.ps1" -or $_.Name -eq "tree-viewer-launcher-v2.ps1" }
            $launcher | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Utility Scripts" {
        BeforeAll {
            $UtilityPath = Join-Path $ProjectRoot "src/powershell/utilities"
        }
        
        It "Should have CredentialManager.ps1" {
            $path = Join-Path $UtilityPath "CredentialManager.ps1"
            Test-Path $path | Should -BeTrue
        }
        
        It "Should have PCProfileManager.ps1" {
            $path = Join-Path $UtilityPath "PCProfileManager.ps1"
            Test-Path $path | Should -BeTrue
        }
    }
    
    Context "Database Scripts" {
        BeforeAll {
            $DbPath = Join-Path $ProjectRoot "src/powershell/database"
        }
        
        It "Should have connect-db.ps1" {
            $path = Join-Path $DbPath "connect-db.ps1"
            Test-Path $path | Should -BeTrue
        }
        
        It "Should have test-connection.ps1" {
            $path = Join-Path $DbPath "test-connection.ps1"
            Test-Path $path | Should -BeTrue
        }
    }
}
