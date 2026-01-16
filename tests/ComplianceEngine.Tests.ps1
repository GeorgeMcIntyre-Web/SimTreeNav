# ComplianceEngine Pester Tests
# Tests for Save-Template.ps1 and Test-TemplateCompliance.ps1

BeforeAll {
    $enginePath = Join-Path $PSScriptRoot "..\src\powershell\ws2c-engines"
    . "$enginePath\Save-Template.ps1"
    . "$enginePath\Test-TemplateCompliance.ps1"
    
    # Create test data directory
    $script:testDataDir = Join-Path $PSScriptRoot "test-data"
    if (-not (Test-Path $testDataDir)) {
        New-Item -ItemType Directory -Path $testDataDir | Out-Null
    }
    
    # Sample nodes data for testing
    $script:sampleNodes = @(
        @{
            id = "1"
            name = "Project_Root"
            nodeType = "Project"
            parentId = $null
            attributes = @{ version = "1.0" }
        },
        @{
            id = "2"
            name = "Plant_001"
            nodeType = "Plant"
            parentId = "1"
            attributes = @{ location = "Detroit" }
        },
        @{
            id = "3"
            name = "Line_001"
            nodeType = "Line"
            parentId = "2"
            attributes = @{}
        },
        @{
            id = "4"
            name = "Station_001"
            nodeType = "Station"
            parentId = "3"
            attributes = @{ cycleTime = 60 }
        },
        @{
            id = "5"
            name = "Station_002"
            nodeType = "Station"
            parentId = "3"
            attributes = @{ cycleTime = 45 }
        },
        @{
            id = "6"
            name = "Robot_001"
            nodeType = "Robot"
            parentId = "4"
            attributes = @{ model = "KUKA KR-16" }
        },
        @{
            id = "7"
            name = "invalid-name!"
            nodeType = "Device"
            parentId = "4"
            attributes = @{}
        }
    )
    
    $script:nodesPath = Join-Path $testDataDir "test-nodes.json"
    $sampleNodes | ConvertTo-Json -Depth 10 | Set-Content -Path $nodesPath
}

AfterAll {
    # Cleanup test data
    if (Test-Path $script:testDataDir) {
        Remove-Item -Path $testDataDir -Recurse -Force
    }
}

Describe "Save-Template" {
    Context "Template Creation" {
        It "Should create a valid template from nodes" {
            $templatePath = Join-Path $script:testDataDir "test-template.json"
            
            $result = Save-Template -NodesPath $script:nodesPath -NodeId "1" -TemplateName "TestTemplate" -OutPath $templatePath
            
            $result | Should -Be $true
            Test-Path $templatePath | Should -Be $true
        }
        
        It "Should include requiredTypes in template" {
            $templatePath = Join-Path $script:testDataDir "test-template.json"
            Save-Template -NodesPath $script:nodesPath -NodeId "1" -TemplateName "TestTemplate" -OutPath $templatePath
            
            $template = Get-Content $templatePath | ConvertFrom-Json
            
            $template.requiredTypes | Should -Not -BeNullOrEmpty
        }
        
        It "Should include requiredLinks in template" {
            $templatePath = Join-Path $script:testDataDir "test-template.json"
            Save-Template -NodesPath $script:nodesPath -NodeId "1" -TemplateName "TestTemplate" -OutPath $templatePath
            
            $template = Get-Content $templatePath | ConvertFrom-Json
            
            $template.requiredLinks | Should -Not -BeNullOrEmpty
        }
        
        It "Should include namingRules with regex patterns" {
            $templatePath = Join-Path $script:testDataDir "test-template.json"
            Save-Template -NodesPath $script:nodesPath -NodeId "1" -TemplateName "TestTemplate" -OutPath $templatePath
            
            $template = Get-Content $templatePath | ConvertFrom-Json
            
            $template.namingRules | Should -Not -BeNullOrEmpty
        }
        
        It "Should include allowedExtras setting" {
            $templatePath = Join-Path $script:testDataDir "test-template.json"
            Save-Template -NodesPath $script:nodesPath -NodeId "1" -TemplateName "TestTemplate" -OutPath $templatePath
            
            $template = Get-Content $templatePath | ConvertFrom-Json
            
            $template.PSObject.Properties.Name | Should -Contain "allowedExtras"
        }
        
        It "Should fail gracefully for non-existent node" {
            $templatePath = Join-Path $script:testDataDir "fail-template.json"
            
            $result = Save-Template -NodesPath $script:nodesPath -NodeId "999" -TemplateName "FailTemplate" -OutPath $templatePath
            
            $result | Should -Be $false
        }
    }
    
    Context "Deterministic Output" {
        It "Should produce identical output for same input" {
            $template1Path = Join-Path $script:testDataDir "template1.json"
            $template2Path = Join-Path $script:testDataDir "template2.json"
            
            Save-Template -NodesPath $script:nodesPath -NodeId "1" -TemplateName "DeterminismTest" -OutPath $template1Path
            Save-Template -NodesPath $script:nodesPath -NodeId "1" -TemplateName "DeterminismTest" -OutPath $template2Path
            
            $content1 = Get-Content $template1Path -Raw
            $content2 = Get-Content $template2Path -Raw
            
            $content1 | Should -Be $content2
        }
    }
}

Describe "Test-TemplateCompliance" {
    BeforeAll {
        # Create a template for compliance testing
        $script:complianceTemplatePath = Join-Path $script:testDataDir "compliance-template.json"
        
        $complianceTemplate = @{
            name = "StationTemplate"
            version = "1.0"
            rootType = "Line"
            requiredTypes = @(
                @{ nodeType = "Station"; min = 1; max = 10 }
                @{ nodeType = "Robot"; min = 1; max = 5 }
            )
            requiredLinks = @(
                @{ from = "Line"; to = "Station" }
                @{ from = "Station"; to = "Robot" }
            )
            namingRules = @(
                @{ nodeType = "Station"; pattern = "^Station_\d{3}$" }
                @{ nodeType = "Robot"; pattern = "^Robot_\d{3}$" }
            )
            allowedExtras = $true
            driftRules = @(
                @{ nodeType = "Station"; tolerance = 2 }
            )
        }
        
        $complianceTemplate | ConvertTo-Json -Depth 10 | Set-Content -Path $complianceTemplatePath
    }
    
    Context "Compliance Scoring" {
        It "Should return a score between 0 and 100" {
            $complianceOutPath = Join-Path $script:testDataDir "compliance-result.json"
            
            Test-TemplateCompliance -NodesPath $script:nodesPath -TemplatePath $script:complianceTemplatePath -OutPath $complianceOutPath
            
            $result = Get-Content $complianceOutPath | ConvertFrom-Json
            
            $result.score | Should -BeGreaterOrEqual 0
            $result.score | Should -BeLessOrEqual 100
        }
        
        It "Should identify missing required types" {
            # Create nodes without required Robot
            $incompleteNodes = @(
                @{ id = "1"; name = "Line_001"; nodeType = "Line"; parentId = $null }
                @{ id = "2"; name = "Station_001"; nodeType = "Station"; parentId = "1" }
            )
            
            $incompleteNodesPath = Join-Path $script:testDataDir "incomplete-nodes.json"
            $incompleteNodes | ConvertTo-Json -Depth 10 | Set-Content -Path $incompleteNodesPath
            
            $complianceOutPath = Join-Path $script:testDataDir "compliance-incomplete.json"
            
            Test-TemplateCompliance -NodesPath $incompleteNodesPath -TemplatePath $script:complianceTemplatePath -OutPath $complianceOutPath
            
            $result = Get-Content $complianceOutPath | ConvertFrom-Json
            
            $result.missing | Should -Not -BeNullOrEmpty
            $result.missing | Where-Object { $_.nodeType -eq "Robot" } | Should -Not -BeNullOrEmpty
        }
        
        It "Should detect naming violations" {
            $complianceOutPath = Join-Path $script:testDataDir "compliance-naming.json"
            
            Test-TemplateCompliance -NodesPath $script:nodesPath -TemplatePath $script:complianceTemplatePath -OutPath $complianceOutPath
            
            $result = Get-Content $complianceOutPath | ConvertFrom-Json
            
            # Our test data has "invalid-name!" which violates naming rules
            $result.violations | Should -Not -BeNullOrEmpty
        }
        
        It "Should identify extra nodes when allowedExtras is false" {
            # Create strict template
            $strictTemplate = @{
                name = "StrictTemplate"
                version = "1.0"
                rootType = "Line"
                requiredTypes = @(
                    @{ nodeType = "Station"; min = 1; max = 1 }
                )
                requiredLinks = @()
                namingRules = @()
                allowedExtras = $false
            }
            
            $strictTemplatePath = Join-Path $script:testDataDir "strict-template.json"
            $strictTemplate | ConvertTo-Json -Depth 10 | Set-Content -Path $strictTemplatePath
            
            $complianceOutPath = Join-Path $script:testDataDir "compliance-strict.json"
            
            # Nodes have more than 1 station
            Test-TemplateCompliance -NodesPath $script:nodesPath -TemplatePath $strictTemplatePath -OutPath $complianceOutPath
            
            $result = Get-Content $complianceOutPath | ConvertFrom-Json
            
            $result.extras | Should -Not -BeNullOrEmpty
        }
        
        It "Should include perRule breakdown" {
            $complianceOutPath = Join-Path $script:testDataDir "compliance-breakdown.json"
            
            Test-TemplateCompliance -NodesPath $script:nodesPath -TemplatePath $script:complianceTemplatePath -OutPath $complianceOutPath
            
            $result = Get-Content $complianceOutPath | ConvertFrom-Json
            
            $result.perRule | Should -Not -BeNullOrEmpty
        }
        
        It "Should include evidence with nodeIds" {
            $complianceOutPath = Join-Path $script:testDataDir "compliance-evidence.json"
            
            Test-TemplateCompliance -NodesPath $script:nodesPath -TemplatePath $script:complianceTemplatePath -OutPath $complianceOutPath
            
            $result = Get-Content $complianceOutPath | ConvertFrom-Json
            
            # Check that violations include nodeIds as evidence
            if ($result.violations.Count -gt 0) {
                $result.violations[0].PSObject.Properties.Name | Should -Contain "nodeId"
            }
        }
    }
    
    Context "Deterministic Output" {
        It "Should produce stable sorted output" {
            $result1Path = Join-Path $script:testDataDir "compliance-det1.json"
            $result2Path = Join-Path $script:testDataDir "compliance-det2.json"
            
            Test-TemplateCompliance -NodesPath $script:nodesPath -TemplatePath $script:complianceTemplatePath -OutPath $result1Path
            Test-TemplateCompliance -NodesPath $script:nodesPath -TemplatePath $script:complianceTemplatePath -OutPath $result2Path
            
            $content1 = Get-Content $result1Path -Raw
            $content2 = Get-Content $result2Path -Raw
            
            $content1 | Should -Be $content2
        }
    }
}
