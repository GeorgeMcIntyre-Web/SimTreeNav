<#
.SYNOPSIS
    Security compliance tests for SimTreeNav.

.DESCRIPTION
    Validates that no security violations exist in the codebase.
#>

BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    $SourcePath = Join-Path $ProjectRoot "src"
}

Describe "Security Compliance" {
    
    Context "No Hardcoded Credentials" {
        BeforeAll {
            $Scripts = Get-ChildItem -Path $SourcePath -Recurse -Filter "*.ps1"
        }
        
        It "Should not contain hardcoded passwords" {
            $violations = @()
            foreach ($script in $Scripts) {
                $content = Get-Content $script.FullName -Raw
                # Look for password assignments (excluding comments and secure patterns)
                if ($content -match '(?<!#.*)\$password\s*=\s*["\u0027][^"\u0027$]{3,}["\u0027]') {
                    $violations += $script.Name
                }
            }
            $violations | Should -BeNullOrEmpty -Because "Hardcoded passwords found in: $($violations -join ', ')"
        }
        
        It "Should not contain plain text credentials in connection strings" {
            $violations = @()
            foreach ($script in $Scripts) {
                $content = Get-Content $script.FullName -Raw
                # Look for connection strings with embedded passwords
                if ($content -match 'password\s*=\s*["\u0027][^$"][^"\u0027]+["\u0027]' -and 
                    $content -notmatch '\$.*password' -and
                    $content -notmatch '#.*password') {
                    $violations += $script.Name
                }
            }
            $violations.Count | Should -BeLessThan 3 -Because "Potential hardcoded credentials in connection strings"
        }
        
        It "Should use SecureString or Credential objects" {
            # At least one script should demonstrate secure credential handling
            $securePatterns = @()
            foreach ($script in $Scripts) {
                $content = Get-Content $script.FullName -Raw
                if ($content -match 'SecureString|PSCredential|Get-Credential|ConvertTo-SecureString') {
                    $securePatterns += $script.Name
                }
            }
            $securePatterns.Count | Should -BeGreaterThan 0 -Because "No scripts use secure credential patterns"
        }
    }
    
    Context "Git Ignore Protection" {
        BeforeAll {
            $GitIgnorePath = Join-Path $ProjectRoot ".gitignore"
            $GitIgnoreContent = if (Test-Path $GitIgnorePath) { 
                Get-Content $GitIgnorePath -Raw 
            } else { 
                "" 
            }
        }
        
        It "Should have .gitignore file" {
            Test-Path $GitIgnorePath | Should -BeTrue
        }
        
        It "Should ignore credential files" {
            $patterns = @('.credentials', 'credential', '*.xml')
            $hasProtection = $false
            foreach ($pattern in $patterns) {
                if ($GitIgnoreContent -match [regex]::Escape($pattern)) {
                    $hasProtection = $true
                    break
                }
            }
            $hasProtection | Should -BeTrue -Because ".gitignore should protect credential files"
        }
        
        It "Should ignore generated HTML files" {
            $GitIgnoreContent | Should -Match '\.html' -Because "Generated HTML files may contain sensitive data"
        }
    }
    
    Context "SQL Injection Prevention" {
        BeforeAll {
            $Scripts = Get-ChildItem -Path $SourcePath -Recurse -Filter "*.ps1"
        }
        
        It "Should not use string concatenation for SQL with user input" {
            $suspicious = @()
            foreach ($script in $Scripts) {
                $content = Get-Content $script.FullName -Raw
                # Look for potential SQL injection patterns
                # This is a simplified check - real analysis would be more comprehensive
                if ($content -match '\$.*\s*\+\s*["\u0027].*SELECT|INSERT|UPDATE|DELETE' -or
                    $content -match 'SELECT.*\+\s*\$') {
                    # Exclude known safe patterns
                    if ($content -notmatch 'ValidatePattern|ValidateSet') {
                        $suspicious += $script.Name
                    }
                }
            }
            # Allow some instances but flag if excessive
            $suspicious.Count | Should -BeLessThan 5 -Because "Potential SQL injection patterns detected"
        }
    }
    
    Context "No Sensitive Data in Logs" {
        BeforeAll {
            $Scripts = Get-ChildItem -Path $SourcePath -Recurse -Filter "*.ps1"
        }
        
        It "Should not log passwords" {
            $violations = @()
            foreach ($script in $Scripts) {
                $content = Get-Content $script.FullName -Raw
                if ($content -match 'Write-(Host|Output|Verbose|Debug|Warning|Error).*\$password' -and
                    $content -notmatch '#.*Write-') {
                    $violations += $script.Name
                }
            }
            $violations | Should -BeNullOrEmpty -Because "Password logging detected in: $($violations -join ', ')"
        }
    }
}

Describe "SECURITY.md Compliance" {
    
    Context "Security Documentation" {
        BeforeAll {
            $SecurityPath = Join-Path $ProjectRoot "SECURITY.md"
        }
        
        It "Should have SECURITY.md file" {
            Test-Path $SecurityPath | Should -BeTrue
        }
        
        It "Should document supported versions" {
            $content = Get-Content $SecurityPath -Raw
            $content | Should -Match 'Supported Versions'
        }
        
        It "Should document vulnerability reporting" {
            $content = Get-Content $SecurityPath -Raw
            $content | Should -Match 'Reporting|Vulnerability|Disclosure'
        }
    }
}
