<#
.SYNOPSIS
    Tests for manifest.json validity and consistency.

.DESCRIPTION
    Validates that manifest.json contains required fields
    and follows the expected schema.
#>

BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    $ManifestPath = Join-Path $ProjectRoot "manifest.json"
}

Describe "Manifest.json" {
    
    Context "File Existence" {
        It "Should exist in project root" {
            Test-Path $ManifestPath | Should -BeTrue
        }
    }
    
    Context "JSON Validity" {
        BeforeAll {
            $ManifestContent = Get-Content $ManifestPath -Raw -ErrorAction SilentlyContinue
        }
        
        It "Should be valid JSON" {
            { $ManifestContent | ConvertFrom-Json } | Should -Not -Throw
        }
    }
    
    Context "Required Fields" {
        BeforeAll {
            $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        }
        
        It "Should have schemaVersion" {
            $Manifest.schemaVersion | Should -Not -BeNullOrEmpty
        }
        
        It "Should have appVersion" {
            $Manifest.appVersion | Should -Not -BeNullOrEmpty
        }
        
        It "Should have appName" {
            $Manifest.appName | Should -Not -BeNullOrEmpty
        }
        
        It "Should have description" {
            $Manifest.description | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Version Format" {
        BeforeAll {
            $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        }
        
        It "schemaVersion should follow semver format" {
            $Manifest.schemaVersion | Should -Match '^\d+\.\d+\.\d+$'
        }
        
        It "appVersion should follow semver format" {
            $Manifest.appVersion | Should -Match '^\d+\.\d+\.\d+$'
        }
    }
    
    Context "Component Definitions" {
        BeforeAll {
            $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        }
        
        It "Should have components section" {
            $Manifest.components | Should -Not -BeNullOrEmpty
        }
        
        It "Should have core component" {
            $Manifest.components.core | Should -Not -BeNullOrEmpty
        }
        
        It "Core component should have entryPoint" {
            $Manifest.components.core.entryPoint | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Dependencies" {
        BeforeAll {
            $Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        }
        
        It "Should have dependencies section" {
            $Manifest.dependencies | Should -Not -BeNullOrEmpty
        }
        
        It "Should have runtime dependencies" {
            $Manifest.dependencies.runtime | Should -Not -BeNullOrEmpty
        }
    }
}
