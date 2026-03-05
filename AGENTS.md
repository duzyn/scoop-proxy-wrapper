# AGENTS.md - Agent Coding Guidelines

This file provides guidelines for agentic coding agents operating in this repository.

## Project Overview

This is a Scoop proxy wrapper for Windows that helps install Scoop and apps through a GitHub proxy. The project consists of PowerShell scripts and Pester tests.

## Repository Structure

```
scoop-proxy-wrapper/
├── install.ps1          # Main installation script
├── profile.ps1          # PowerShell profile wrapper for Scoop
├── Tests/
│   ├── install.tests.ps1   # Unit tests for install.ps1
│   └── profile.tests.ps1   # Unit tests for profile.ps1
└── .github/
    └── workflows/
        └── test.yml     # GitHub Actions workflow
```

## Build/Lint/Test Commands

### Running Tests

**Run all tests:**
```powershell
Invoke-Pester -Path '.\Tests'
```

**Run a single test file:**
```powershell
Invoke-Pester -Path '.\Tests\install.tests.ps1'
Invoke-Pester -Path '.\Tests\profile.tests.ps1'
```

**Run tests with detailed output:**
```powershell
Invoke-Pester -Path '.\Tests' -Output Detailed
```

**Run a specific test by name:**
```powershell
Invoke-Pester -Path '.\Tests\install.tests.ps1' -TestName "Should match 7-Zip version pattern in URL"
```

### GitHub Actions

The workflow can be triggered manually via `workflow_dispatch` event in GitHub Actions.

## Code Style Guidelines

### General Principles

- PowerShell scripts should be clear and readable
- Use comments sparingly - code should be self-explanatory
- Follow Windows PowerShell conventions

### Naming Conventions

**Functions:**
- Use PascalCase: `Install-Scoop`, `Add-ScoopProxyToProfile`
- Verb-Noun pattern required
- Use approved verbs: `Get`, `Set`, `Add`, `Remove`, `Test`, `Invoke`

**Variables:**
- Use PascalCase for script-level: `$ScoopPath`, `$ProxyUrl`
- Use `$env:` prefix for environment variables: `$env:SCOOP_GH_PROXY`
- Use `$null` instead of `NULL` or `null`

**Files:**
- Use descriptive names: `install.ps1`, `profile.tests.ps1`

### Formatting

**Indentation:**
- Use 4 spaces (not tabs)
- Align pipe operators (`|`) at the start of new lines

**Line Length:**
- Keep lines under 120 characters when practical
- Break long strings using string concatenation

**Braces:**
- Opening brace on same line: `function MyFunction {`
- Closing brace on its own line

### Error Handling

**Try-Catch:**
```powershell
try {
    Invoke-RestMethod $proxyUrl -ErrorAction Stop | Invoke-Expression
}
catch {
    Write-Host "Failed to install Scoop: $_"
    exit 1
}
```

**Error Action Preferences:**
- Use `-ErrorAction Stop` for critical operations
- Use `-ErrorAction SilentlyContinue` for non-critical checks
- Use `-ErrorAction SilentlyContinue -ErrorAction Stop` for commands that may not exist

### String Handling

**Important - Regex Replacement in PowerShell:**
When using `-replace` operator with captured groups (`$1`, `$2`), use parentheses for string concatenation:

```powershell
# WRONG - $1 gets interpreted as empty variable
$result = $url -replace 'pattern', "$env:SCOOP_GH_PROXY/$1"

# CORRECT - use parentheses to preserve captured groups
$result = $url -replace 'pattern', ($env:SCOOP_GH_PROXY + '/$1')
```

**Quoting:**
- Use double quotes for strings with variables: `"Installing Scoop: $scoopPath"`
- Use single quotes for literal strings: `'SilentlyContinue'`

### Variables and Types

**Environment Variables:**
```powershell
$env:SCOOP_GH_PROXY = "https://gh-proxy.com"
$env:SCOOP = if ($env:SCOOP) { $env:SCOOP } else { "$env:USERPROFILE\scoop" }
```

**Global Variables:**
```powershell
$global:ProgressPreference = 'SilentlyContinue'
```

**Boolean Values:**
- Use `$true` and `$false` (not `1`, `0`, `"true"`, `"false"`)

### Working with Paths

**Use Join-Path:**
```powershell
$scriptDir = Split-Path -Parent $PSCommandPath
$proxyFilePath = Join-Path $scriptDir "profile.ps1"
```

**Path Separators:**
- Use backslash for Windows paths: `$env:USERPROFILE\scoop`
- PowerShell automatically handles path separators

### Testing Guidelines

**Pester Test Structure:**
```powershell
#Requires -Module Pester

Describe 'script function tests' {
    BeforeAll {
        # Setup code that runs once before all tests
    }

    Context 'specific feature' {
        It 'should do something specific' {
            $result | Should Be 'expected'
        }
    }
}
```

**Test Naming:**
- Use descriptive test names: "Should transform 7-Zip URL to GitHub mirror"
- Group related tests in Context blocks

### Common Pitfalls

1. **Variable expansion in regex replacement** - Always use parentheses for string concatenation when using captured groups

2. **Error handling in pipelines** - Pipeline errors may not trigger try-catch; use `-ErrorAction Stop`

3. **Path with spaces** - Always quote paths: `Get-Content "C:\My Folder\file.txt"`

4. **Array indexing** - Arrays are 0-indexed: `$array[0]`

5. **Null comparisons** - Use `-eq $null` or `$null -eq`, not `$variable -eq null`

### Git Commit Messages

- Use clear, concise commit messages
- Start with type: `fix:`, `test:`, `feat:`, `chore:`
- Example: `fix: correct regex replacement in install.ps1`

## Contact

For questions about this codebase, refer to the project README or open an issue.
