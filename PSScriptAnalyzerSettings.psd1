# PSScriptAnalyzer Settings for SimTreeNav
# Lightweight lint checks for PowerShell style conventions

@{
    # Severity levels to include
    Severity = @('Error', 'Warning')
    
    # Exclude specific rules that are too strict for this project
    ExcludeRules = @(
        # Allow Write-Host for interactive scripts
        'PSAvoidUsingWriteHost',
        
        # Allow positional parameters in simple cases
        'PSAvoidUsingPositionalParameters',
        
        # Allow $env: usage for environment variables
        'PSAvoidUsingCmdletAliases'
    )
    
    # Include specific rules
    IncludeRules = @(
        # Critical rules - must pass
        'PSAvoidUsingPlainTextForPassword',
        'PSAvoidUsingConvertToSecureStringWithPlainText',
        'PSAvoidUsingUserNameAndPasswordParams',
        'PSCredentialTypeShouldBeUsed',
        
        # Code quality
        'PSUseApprovedVerbs',
        'PSReservedCmdletChar',
        'PSReservedParams',
        'PSShouldProcess',
        'PSUseSingularNouns',
        
        # Script safety
        'PSAvoidGlobalVars',
        'PSAvoidInvokingEmptyMembers',
        'PSAvoidNullOrEmptyHelpMessageAttribute',
        
        # Best practices
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSUsePSCredentialType',
        'PSUseShouldProcessForStateChangingFunctions',
        
        # Output clarity
        'PSAvoidDefaultValueForMandatoryParameter',
        'PSAvoidDefaultValueSwitchParameter'
    )
    
    # Rule-specific settings
    Rules = @{
        PSUseApprovedVerbs = @{
            Enable = $true
        }
        
        PSAvoidUsingPlainTextForPassword = @{
            Enable = $true
        }
        
        PSAvoidUsingConvertToSecureStringWithPlainText = @{
            Enable = $true
        }
    }
}
