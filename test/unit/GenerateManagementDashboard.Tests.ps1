<#
.SYNOPSIS
    Pester tests for generate-management-dashboard.ps1 UI bindings.
#>

BeforeAll {
    $script:DashboardPath = Join-Path $PSScriptRoot "..\..\scripts\generate-management-dashboard.ps1"
    $script:DashboardContent = Get-Content -Path $script:DashboardPath -Raw -Encoding UTF8
}

Describe 'Management Dashboard UI wiring' {
    It 'includes allocation state filters for timeline and log' {
        $script:DashboardContent | Should -Match 'timelineAllocationStateFilter'
        $script:DashboardContent | Should -Match 'logAllocationStateFilter'
    }

    It 'normalizes allocation state to unknown when missing' {
        $script:DashboardContent | Should -Match 'function getAllocationState'
        $script:DashboardContent | Should -Match "return 'unknown'"
    }

    It 'renders evidence labels with PM-friendly wording' {
        $script:DashboardContent | Should -Match 'Write proof'
        $script:DashboardContent | Should -Match 'Relationships checked'
    }
}
