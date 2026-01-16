# Contributing to SimTreeNav

Thank you for your interest in contributing to SimTreeNav! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for everyone.

## Getting Started

### Prerequisites

- Windows PowerShell 5.1 or later
- Oracle 12c Instant Client
- Git
- Pester 5.0+ (for testing)
- PSScriptAnalyzer (for linting)

### Development Setup

1. **Fork and clone the repository**
   ```powershell
   git clone https://github.com/YOUR_USERNAME/SimTreeNav.git
   cd SimTreeNav
   ```

2. **Install development dependencies**
   ```powershell
   Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope CurrentUser
   Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser
   ```

3. **Run tests to verify setup**
   ```powershell
   Invoke-Pester -Path ./tests
   ```

4. **Run linter**
   ```powershell
   Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
   ```

## Development Workflow

### Branch Naming

- `feature/` - New features (e.g., `feature/json-export`)
- `fix/` - Bug fixes (e.g., `fix/icon-loading`)
- `docs/` - Documentation changes (e.g., `docs/api-reference`)
- `refactor/` - Code refactoring (e.g., `refactor/credential-manager`)

### Making Changes

1. **Create a feature branch**
   ```powershell
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes**
   - Follow the [coding standards](#coding-standards)
   - Add tests for new functionality
   - Update documentation as needed

3. **Run quality checks**
   ```powershell
   # Run linter
   Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
   
   # Run tests
   Invoke-Pester -Path ./tests
   ```

4. **Commit your changes**
   ```powershell
   git add .
   git commit -m "feat: add JSON export functionality"
   ```

5. **Push and create a Pull Request**
   ```powershell
   git push origin feature/your-feature-name
   ```

### Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation changes
- `style` - Code style changes (formatting, etc.)
- `refactor` - Code refactoring
- `test` - Adding or updating tests
- `chore` - Maintenance tasks

**Examples:**
```
feat(tree): add JSON export capability
fix(icons): resolve base64 encoding for large icons
docs(api): add query examples for custom ordering
test(credentials): add unit tests for DEV mode
```

## Coding Standards

### PowerShell Style Guide

1. **Use approved verbs**
   ```powershell
   # Good
   function Get-TreeData { }
   function Export-TreeToHtml { }
   
   # Bad
   function Retrieve-TreeData { }
   function TreeToHtml { }
   ```

2. **Use PascalCase for functions and parameters**
   ```powershell
   function Get-DatabaseConnection {
       param(
           [Parameter(Mandatory)]
           [string]$ServerName,
           
           [string]$SchemaName = "DESIGN12"
       )
   }
   ```

3. **Include comment-based help**
   ```powershell
   function Get-TreeNode {
       <#
       .SYNOPSIS
           Retrieves a tree node by ID.
       
       .DESCRIPTION
           Queries the database for a specific tree node and returns
           its properties including children.
       
       .PARAMETER NodeId
           The unique identifier of the node.
       
       .EXAMPLE
           Get-TreeNode -NodeId 18140190
       #>
       param(
           [Parameter(Mandatory)]
           [int]$NodeId
       )
   }
   ```

4. **Never store credentials in plain text**
   ```powershell
   # Good - use SecureString or CredentialManager
   $credential = Get-Credential
   
   # Bad - never do this
   $password = "plaintext"
   ```

5. **Use proper error handling**
   ```powershell
   try {
       $result = Invoke-DatabaseQuery -Query $sql
   }
   catch {
       Write-Error "Failed to execute query: $_"
       throw
   }
   ```

### SQL Style Guide

1. **Use UPPERCASE for SQL keywords**
   ```sql
   SELECT c.OBJECT_ID, c.CAPTION_S_
   FROM SCHEMA.COLLECTION_ c
   WHERE c.STATUS = 1
   ORDER BY c.CAPTION_S_
   ```

2. **Use meaningful aliases**
   ```sql
   -- Good
   SELECT c.OBJECT_ID, r.FORWARD_OBJECT_ID
   FROM COLLECTION_ c
   INNER JOIN REL_COMMON r ON c.OBJECT_ID = r.OBJECT_ID
   
   -- Bad
   SELECT a.OBJECT_ID, b.FORWARD_OBJECT_ID
   FROM COLLECTION_ a
   INNER JOIN REL_COMMON b ON a.OBJECT_ID = b.OBJECT_ID
   ```

## Testing

### Running Tests

```powershell
# Run all tests
Invoke-Pester -Path ./tests

# Run specific test file
Invoke-Pester -Path ./tests/CredentialManager.Tests.ps1

# Run with code coverage
$config = New-PesterConfiguration
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @("./src/**/*.ps1")
Invoke-Pester -Configuration $config
```

### Writing Tests

Tests should be placed in the `tests/` directory with the naming convention `*.Tests.ps1`.

```powershell
Describe "Get-TreeNode" {
    BeforeAll {
        . $PSScriptRoot/../src/powershell/main/tree-functions.ps1
    }
    
    Context "When node exists" {
        It "Should return node data" {
            # Arrange
            $nodeId = 18140190
            
            # Act
            $result = Get-TreeNode -NodeId $nodeId
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.ObjectId | Should -Be $nodeId
        }
    }
    
    Context "When node does not exist" {
        It "Should return null" {
            $result = Get-TreeNode -NodeId 99999999
            $result | Should -BeNullOrEmpty
        }
    }
}
```

## Documentation

### When to Update Documentation

- Adding new features
- Changing existing behavior
- Deprecating functionality
- Fixing documentation errors

### Documentation Files

- `README.md` - Project overview and quick start
- `docs/ARCHITECTURE.md` - System architecture
- `docs/FEATURES.md` - Feature documentation
- `docs/DEPLOYMENT.md` - Deployment guide
- `docs/ROADMAP.md` - Future plans
- `CHANGELOG.md` - Version history

## Pull Request Process

1. **Ensure CI passes**
   - All tests must pass
   - Linter must pass
   - No security violations

2. **Update documentation**
   - Add/update relevant docs
   - Update CHANGELOG.md if applicable

3. **Request review**
   - Assign reviewers
   - Respond to feedback promptly

4. **Merge**
   - Squash commits if requested
   - Delete branch after merge

## Release Process

See [scripts/Build-Release.ps1](scripts/Build-Release.ps1) for the release automation.

1. Update version in `manifest.json`
2. Update `CHANGELOG.md`
3. Run `./scripts/Build-Release.ps1`
4. Create GitHub release with artifacts

## Getting Help

- **Questions**: Open a [GitHub Discussion](https://github.com/GeorgeMcIntyre-Web/SimTreeNav/discussions)
- **Bugs**: Open a [GitHub Issue](https://github.com/GeorgeMcIntyre-Web/SimTreeNav/issues)
- **Security**: See [SECURITY.md](SECURITY.md)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

Thank you for contributing to SimTreeNav!
