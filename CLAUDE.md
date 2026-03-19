# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Scoop proxy wrapper for Windows that helps users install Scoop and apps through a GitHub proxy (gh-proxy.com). It is particularly useful for users in regions with slow GitHub access.

## Build/Test Commands

### Running Tests

Run all tests:
```powershell
Invoke-Pester -Path '.\Tests'
```

Run a single test file:
```powershell
Invoke-Pester -Path '.\Tests\install.tests.ps1'
Invoke-Pester -Path '.\Tests\profile.tests.ps1'
```

Run tests with detailed output:
```powershell
Invoke-Pester -Path '.\Tests' -Output Detailed
```

Run a specific test by name:
```powershell
Invoke-Pester -Path '.\Tests\install.tests.ps1' -TestName "Should match 7-Zip version pattern in URL"
```

### Manual Testing

The GitHub Actions workflow (`.github/workflows/test.yml`) can be triggered manually via `workflow_dispatch`.

## Architecture

### Core Components

1. **install.ps1** - Main installation script
   - Installs Scoop via proxy
   - Modifies manifests for 7-Zip and Git to use proxy URLs
   - Adds the proxy wrapper function to user's PowerShell profile

2. **profile.ps1** - PowerShell profile wrapper
   - Defines a `scoop` function that wraps the real Scoop command
   - Intercepts and proxies GitHub URLs through the configured proxy
   - Uses function interception to modify JSON parsing (`ConvertFrom-Json`) and aria2c calls

3. **Tests/** - Pester test suite
   - `install.tests.ps1` - Tests for install.ps1 functions
   - `profile.tests.ps1` - Tests for profile.ps1 proxy transformations

### Critical Execution Order

The main execution order in `install.ps1` is critical and must not be changed:

```powershell
Install-Scoop                              # 1. Install Scoop
Prepare-And-Install-Essentials -Path ...   # 2. Install git (profile.ps1 needs git)
Add-ScoopProxyToProfile                    # 3. Load profile (uses git config internally)
```

Git must be installed before loading the profile because `profile.ps1` uses `git config` commands internally.

### Proxy Mechanism

The wrapper uses multiple interception techniques:

1. **JSON Hook**: Overrides `ConvertFrom-Json` to transform URLs in parsed JSON objects
2. **Git insteadOf**: Temporarily configures git to redirect github.com URLs through the proxy
3. **Aria2c Hook**: Overrides aria2c.exe function to disable certificate checking

URL transformation patterns:
- `github.com/*` and `raw.githubusercontent.com/*` → `{proxy}/https://github.com/...`
- `7-zip.org/a/7z*.exe` → Redirected to GitHub releases via proxy

### Important Regex Pattern

When using `-replace` with captured groups (`$1`, `$2`), always use parentheses for string concatenation:

```powershell
# WRONG - $1 gets interpreted as empty variable
$result = $url -replace 'pattern', "$env:SCOOP_GH_PROXY/$1"

# CORRECT - use parentheses to preserve captured groups
$result = $url -replace 'pattern', ($env:SCOOP_GH_PROXY + '/$1')
```

## Environment Variables

- `SCOOP_GH_PROXY` - The GitHub proxy URL (default: `https://gh-proxy.com`)
- `SCOOP` - Custom Scoop installation path (optional)
- `SCOOP_DEBUG` - Set to `true` to enable debug output

## Code Style

- Use PascalCase for function names (Verb-Noun pattern)
- Use 4 spaces for indentation (not tabs)
- Opening brace on same line: `function MyFunction {`
- Use `$null` instead of `NULL` or `null`
- Use `$true` and `$false` for booleans
