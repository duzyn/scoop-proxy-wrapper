# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Scoop proxy wrapper** for Windows - a tool that accelerates Scoop package manager downloads by routing GitHub traffic through a proxy service (gh-proxy.com by default).

## Commands

### Installation

```powershell
# Install Scoop with proxy (auto-detects existing installation)
powershell -ExecutionPolicy Bypass -File install.ps1
```

### Development

This is a simple single-script project with no build, lint, or test commands.

## Architecture

### Components

- **install.ps1** - Scoop installation with proxy wrapper
  - Auto-detects existing Scoop installation (runs patch mode) or performs fresh install
  - Downloads Scoop installer through proxy
  - Creates a PowerShell function wrapper (`scoop`) that intercepts commands
  - Persists wrapper to PowerShell profile (`$PROFILE`)
  - Supports proxy for: bucket add, install, update, reinstall commands
  - Patches `lib/download.ps1` to intercept GitHub release URLs
  - Patches `bin/scoop.ps1` with self-healing capability

### How It Works

1. **Environment Variable**: `SCOOP_GH_PROXY` controls the proxy URL (default: `https://gh-proxy.com/`)

2. **Auto-Detection**: `install.ps1` checks if Scoop is already installed
   - If installed: runs in patch mode (applies proxy patches)
   - If not installed: runs fresh install mode

3. **Wrapper Function**: The `scoop` function intercepts:
   - `bucket add` - Proxies known bucket Git URLs
   - `install/update/reinstall` - Modifies manifests to inject proxy URLs before running the real scoop

4. **Direct Patching**: `install.ps1` directly modifies Scoop's internal files for more permanent proxy support
