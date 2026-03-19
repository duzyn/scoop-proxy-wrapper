param(
    [switch]$Force
)

# 隐藏进度条
$global:ProgressPreference = 'SilentlyContinue'

# --- Configuration ---
$env:SCOOP_GH_PROXY = "https://gh-proxy.com"
$ScoopPath = if ($env:SCOOP) { $env:SCOOP } else { "$env:USERPROFILE\scoop" }

# --- Functions ---

function Test-ScoopInstalled {
    $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
    if ($scoopCmd) {
        return $true
    }
    # Check common Scoop installation paths
    $scoopShimPath = "$env:USERPROFILE\scoop\shims\scoop.cmd"
    $customScoopShimPath = if ($env:SCOOP) { "$env:SCOOP\shims\scoop.cmd" } else { $null }
    if (Test-Path $scoopShimPath) {
        return $true
    }
    if ($customScoopShimPath -and (Test-Path $customScoopShimPath)) {
        return $true
    }
    return $false
}

function Install-Scoop {
    if ((Test-ScoopInstalled) -and -not $Force) {
        Write-Host "Scoop is already installed. Skipping installation..."
        Write-Host "Use -Force parameter to reinstall Scoop if needed."
        return $false
    }

    if ($Force -and (Test-ScoopInstalled)) {
        Write-Host "Force parameter specified. Reinstalling Scoop..."
    } else {
        Write-Host "Installing Scoop..."
    }

    try {
        $proxyUrl = "$env:SCOOP_GH_PROXY/https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1"
        Invoke-RestMethod $proxyUrl -ErrorAction Stop | Invoke-Expression
        Write-Host "Scoop installed successfully"
        return $true
    }
    catch {
        Write-Host "Failed to install Scoop: $_"
        exit 1
    }
}

function Install-CmdWrapper {
    param(
        [Parameter(Mandatory=$true)]
        [string]$WrapperDir
    )

    Write-Host "Installing CMD wrapper for scoop..."

    # Ensure wrapper directory exists
    if (-not (Test-Path $WrapperDir)) {
        New-Item -ItemType Directory -Path $WrapperDir -Force | Out-Null
    }

    # Copy profile.ps1 to wrapper directory
    $scriptDir = Split-Path -Parent $PSCommandPath
    $sourceProfile = Join-Path $scriptDir "profile.ps1"
    $sourceCmd = Join-Path $scriptDir "scoop.cmd"

    if (Test-Path $sourceProfile) {
        Copy-Item -Path $sourceProfile -Destination "$WrapperDir\profile.ps1" -Force
        Write-Host "Copied profile.ps1 to: $WrapperDir"
    }

    if (Test-Path $sourceCmd) {
        Copy-Item -Path $sourceCmd -Destination "$WrapperDir\scoop.cmd" -Force
        Write-Host "Copied scoop.cmd to: $WrapperDir"
    } else {
        Write-Host "Warning: scoop.cmd not found in script directory"
    }

    # Add wrapper directory to PATH if not already present
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($userPath -notlike "*$WrapperDir*") {
        [Environment]::SetEnvironmentVariable('PATH', "$WrapperDir;$userPath", 'User')
        Write-Host "Added $WrapperDir to User PATH"
    }
}

function Add-ScoopProxyToProfile {
    Write-Host "Downloading and installing Scoop proxy function to Profile..."

    $profileUrl = "$env:SCOOP_GH_PROXY/https://raw.githubusercontent.com/duzyn/scoop-proxy-wrapper/main/profile.ps1"

    try {
        $proxyContent = Invoke-RestMethod -Uri $profileUrl -ErrorAction Stop
    }
    catch {
        Write-Host "Warning: Failed to download profile, using local file"
        $scriptDir = Split-Path -Parent $PSCommandPath
        $proxyFilePath = Join-Path $scriptDir "profile.ps1"
        if (-not (Test-Path $proxyFilePath)) {
            Write-Host "Error: profile.ps1 not found"
            return
        }
        $proxyContent = Get-Content $proxyFilePath -Raw
    }

    $profilePath = $PROFILE
    $profileDir = Split-Path $profilePath -Parent

    if (-not (Test-Path $profileDir)) {
        New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
    }

    if (Test-Path $profilePath) {
        $existingContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
        if ($existingContent -match 'function scoop\s*\{') {
            $existingContent = $existingContent -replace '(?ms)function scoop\s*\{.*?^\}', ''
            $existingContent = $existingContent.Trim()
        }
        if ($existingContent) {
            Set-Content -Path $profilePath -Value $existingContent -Encoding UTF8
        }
    }

    Add-Content -Path $profilePath -Value $proxyContent -Encoding UTF8
    Write-Host "Scoop proxy function added to Profile: $profilePath"

    # 立即加载新函数到当前会话
    $tempFile = [System.IO.Path]::GetTempFileName() + ".ps1"
    try {
        [System.IO.File]::WriteAllText($tempFile, $proxyContent, [System.Text.Encoding]::UTF8)
        . $tempFile
        Write-Host "Scoop proxy function loaded in current session"
    }
    finally {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
    }
}

function Prepare-And-Install-Essentials {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    # Check if essentials are already installed
    $sevenZipInstalled = Get-Command 7z -ErrorAction SilentlyContinue
    $gitInstalled = Get-Command git -ErrorAction SilentlyContinue

    if ($sevenZipInstalled -and $gitInstalled -and -not $Force) {
        Write-Host "Essential apps (7zip, git) are already installed. Skipping..."
        Write-Host "Use -Force parameter to reinstall if needed."
        return
    }

    Write-Host "Temporarily modifying 7zip and git manifests for proxy download..."

    $7zipManifestPath = "$Path\buckets\main\bucket\7zip.json"
    $GitManifestPath = "$Path\buckets\main\bucket\git.json"

    if (Test-Path -Path $7zipManifestPath) {
        (Get-Content $7zipManifestPath) -replace 'https?://www\.7-zip\.org/a/7z(\d{2})(\d{2})', ($env:SCOOP_GH_PROXY + '/https://github.com/ip7z/7zip/releases/download/$1.$2/7z$1$2') | Set-Content $7zipManifestPath
    }

    if (Test-Path -Path $GitManifestPath) {
        (Get-Content $GitManifestPath) -replace '(https?://github\.com/.+/releases/.*download)', ($env:SCOOP_GH_PROXY + '/$1') | Set-Content $GitManifestPath
    }

    Write-Host "Installing essential apps (7zip, git)..."

    try {
        if (-not $sevenZipInstalled -or $Force) {
            scoop install 7zip
        }
        if (-not $gitInstalled -or $Force) {
            scoop install git
        }
    }
    catch {
        Write-Host "Failed to install essential apps: $_"
        exit 1
    }

    # 验证安装
    $gitCmd = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitCmd) {
        Write-Host "Warning: git installation may have failed"
    }

    Write-Host "Resetting main bucket..."
    scoop bucket rm main 2>$null
    scoop bucket add main
}

# --- Main Execution ---

$scoopWasInstalled = Install-Scoop

# Only install essentials if Scoop was just installed or Force is specified
if ($scoopWasInstalled -or $Force) {
    Prepare-And-Install-Essentials -Path $ScoopPath
} else {
    Write-Host "Skipping essential apps installation (already installed)."
}

Add-ScoopProxyToProfile

# Install CMD wrapper
$wrapperDir = "$ScoopPath\apps\scoop-proxy-wrapper\current"
Install-CmdWrapper -WrapperDir $wrapperDir

if (Test-ScoopInstalled) {
    if ($Force) {
        Write-Host "Scoop proxy wrapper has been updated successfully!"
    } else {
        Write-Host "Scoop and proxy wrapper are ready!"
    }
} else {
    Write-Host "Scoop was installed successfully!"
}
