# Disable progress bar
$global:ProgressPreference = 'SilentlyContinue'

# --- Configuration ---
$SCOOP_GH_PROXY = if ($env:SCOOP_GH_PROXY) { $env:SCOOP_GH_PROXY } else { "https://gh-proxy.com/" }
if ($SCOOP_GH_PROXY -notmatch '/$') { $SCOOP_GH_PROXY += "/" }
$SCOOP_PATH = if ($env:SCOOP) { $env:SCOOP } else { "$env:USERPROFILE\scoop" }
$EnvName = "SCOOP_GH_PROXY"

# --- Helper Functions ---

function Test-ScoopInstalled {
    # Check if Scoop is installed
    $scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
    if ($scoopCmd) {
        $scoopPath = scoop which scoop 2>$null
        if ($scoopPath) { return $true }
    }
    if (Test-Path "$SCOOP_PATH\apps\scoop\current") { return $true }
    return $false
}

function Set-ProxyEnvironmentVariable {
    param([switch]$Silent)
    if ($null -eq [Environment]::GetEnvironmentVariable($EnvName, "User")) {
        [Environment]::SetEnvironmentVariable($EnvName, $SCOOP_GH_PROXY, "User")
        $env:SCOOP_GH_PROXY = $SCOOP_GH_PROXY
        if (!$Silent) { Write-Host "Environment variable $EnvName set to $SCOOP_GH_PROXY" -ForegroundColor Green }
    }
}

function Get-ScoopPath {
    $scoopCmd = Get-Command -CommandType ExternalScript -Name scoop -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($scoopCmd) {
        $scoopScriptPath = $scoopCmd.Source
        # scoop.ps1 is at .../apps/scoop/current/bin/scoop.ps1
        # We need the Scoop root: .../scoop
        $ScoopPath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $scoopScriptPath))
        if ($ScoopPath -and (Test-Path "$ScoopPath\lib\download.ps1")) {
            return $ScoopPath
        }
    }
    # Fallback
    return $SCOOP_PATH
}

function Apply-DownloadPatch {
    param([string]$ScoopPath, [switch]$Silent)
    $DownloadLib = "$ScoopPath\lib\download.ps1"

    $DownloadPatch = @"
    # --- SCOOP_GH_PROXY PATCH START ---
    if (`$env:SCOOP_GH_PROXY -and `$url -match 'github\.com/.*/releases/download/') {
        `$url = "`$(`$env:SCOOP_GH_PROXY.TrimEnd('/'))/`$url"
    }
    # --- SCOOP_GH_PROXY PATCH END ---
"@

    if (Test-Path $DownloadLib) {
        $Content = Get-Content $DownloadLib -Raw
        if ($Content -notmatch 'SCOOP_GH_PROXY') {
            $NewContent = $Content -replace 'function handle_special_urls\(\$url\) \{', "function handle_special_urls(`$url) {`n$DownloadPatch"
            $NewContent | Set-Content $DownloadLib -NoNewline
            if (!$Silent) { Write-Host "Applied proxy patch to lib/download.ps1" -ForegroundColor Green }
        }
    }
}

function Apply-SelfHealingPatch {
    param([string]$ScoopPath, [switch]$Silent)
    $ScoopBin = "$ScoopPath\bin\scoop.ps1"

    $SelfHealingPatch = @"
# --- SCOOP_GH_PROXY SELF-HEALING START ---
`$DownloadLibFile = "`$PSScriptRoot\..\lib\download.ps1"
if (Test-Path `$DownloadLibFile) {
    `$LibContent = Get-Content `$DownloadLibFile -Raw
    if (`$LibContent -notmatch 'SCOOP_GH_PROXY') {
        `$PatchScript = "$PSCommandPath"
        if (Test-Path `$PatchScript) {
            powershell -File "`$PatchScript" -Silent
        }
    }
}
# --- SCOOP_GH_PROXY SELF-HEALING END ---
"@

    if (Test-Path $ScoopBin) {
        $Content = Get-Content $ScoopBin -Raw
        if ($Content -notmatch 'SCOOP_GH_PROXY') {
            if ($Content -match '#Requires') {
                $NewContent = $Content -replace '(#Requires -Version \d+)', "`$1`n`n$SelfHealingPatch"
            } else {
                $NewContent = "$SelfHealingPatch`n`n$Content"
            }
            $NewContent | Set-Content $ScoopBin -NoNewline
            if (!$Silent) { Write-Host "Applied self-healing patch to bin/scoop.ps1" -ForegroundColor Green }
        }
    }
}

function Invoke-PatchScoop {
    param([switch]$Silent)
    Write-Host "`n>>> Patching existing Scoop installation..." -ForegroundColor Cyan

    # 1. Set environment variable
    Set-ProxyEnvironmentVariable -Silent:$Silent

    # 2. Get Scoop path
    $ScoopPath = Get-ScoopPath

    # 3. Apply patches
    Apply-DownloadPatch -ScoopPath:$ScoopPath -Silent:$Silent
    Apply-SelfHealingPatch -ScoopPath:$ScoopPath -Silent:$Silent

    # 4. Update wrapper in profile
    Write-Host "`n>>> Updating wrapper in PowerShell profile..." -ForegroundColor Cyan
    Update-WrapperInProfile -Silent:$Silent

    if (!$Silent) { Write-Host "`n[SUCCESS] Scoop patch completed!" -ForegroundColor Green }
}

# --- Helper: Define the Wrapper Function Logic ---
# 使用单引号 Here-String (@' ... '@) 确保内部逻辑原样存储，不被提前解析
$WrapperCodeBlock = @'
function scoop {
    $INTERNAL_PROXY = if ($env:SCOOP_GH_PROXY) { $env:SCOOP_GH_PROXY } else { "https://gh-proxy.com/" }
    if ($INTERNAL_PROXY -notmatch '/$') { $INTERNAL_PROXY += "/" }

    $realScoop = "$env:USERPROFILE\scoop\apps\scoop\current\bin\scoop.ps1"
    if (-not (Test-Path $realScoop)) {
        $realScoop = (Get-Command -CommandType ExternalScript -Name scoop -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    }
    if (-not $realScoop) { return }

    $subCommand = $args[0]
    $modifiedArgs = @($args)

    # Logic 1: Intercept 'bucket add'
    if ($subCommand -eq 'bucket' -and $args[1] -eq 'add') {
        $bucketName = $args[2]
        $bucketUrl = if ($args.Count -gt 3) { $args[3] } else { $null }
        $knownBuckets = @{
            'main'          = 'https://github.com/ScoopInstaller/Main.git'
            'extras'        = 'https://github.com/ScoopInstaller/Extras.git'
            'versions'      = 'https://github.com/ScoopInstaller/Versions.git'
            'nirsoft'       = 'https://github.com/k6-0/nirsoft.git'
            'php'           = 'https://github.com/ScoopInstaller/PHP.git'
            'nerd-fonts'    = 'https://github.com/matthewjberger/scoop-nerd-fonts.git'
            'nonportable'   = 'https://github.com/ScoopInstaller/Nonportable.git'
            'java'          = 'https://github.com/ScoopInstaller/Java.git'
            'games'         = 'https://github.com/ScoopInstaller/Games.git'
            'sysinternals'  = 'https://github.com/niheaven/sysinternals.git'
        }
        if (-not $bucketUrl -and $knownBuckets.ContainsKey($bucketName)) { $bucketUrl = $knownBuckets[$bucketName] }
        if ($bucketUrl -and $bucketUrl -match 'https://github.com/') {
            if ($bucketUrl -notmatch '\.git$') { $bucketUrl += '.git' }
            $proxiedBucketUrl = "${INTERNAL_PROXY}${bucketUrl}"
            Write-Host ">>> Proxying Bucket Git URL: $proxiedBucketUrl" -ForegroundColor Yellow
            & powershell -File $realScoop bucket add $bucketName "$proxiedBucketUrl"
            return
        }
    }

    # Logic 2: Intercept 'install/update'
    $interceptDownload = @('install', 'update', 'reinstall')
    if ($interceptDownload -contains $subCommand) {
        $modifiedManifests = @()
        $apps = @($args | Where-Object { $_.Trim() -and -not $_.StartsWith('-') }) | Select-Object -Skip 1

        if ($apps.Count -gt 0) {
            try {
                foreach ($app in $apps) {
                    $info = & powershell -File $realScoop info $app 2>$null | Out-String
                    if ($info -match "(?m)^Manifest:\s*(.+)$") {
                        $path = $matches[1].Trim()
                        if (Test-Path $path) {
                            $content = [System.IO.File]::ReadAllText($path)
                            $escapedProxy = [regex]::Escape($INTERNAL_PROXY)
                            $pattern = "(?<!$escapedProxy)(https://github\.com/[^/]+/[^/]+/(?:releases/(?:latest/)?download|archive)/)"

                            if ($content -match $pattern -or $content -match 'https?://www\.7-zip\.org/a/7z') {
                                Write-Host ">>> Injecting Proxy [$INTERNAL_PROXY] for '$app' manifests..." -ForegroundColor Cyan
                                $newContent = $content -replace $pattern, "${INTERNAL_PROXY}$1"
                                $newContent = $newContent -replace 'https?://www\.7-zip\.org/a/7z(\d{2})(\d{2})', "https://github.com/ip7z/7zip/releases/download/$1.$2/7z$1$2"
                                [System.IO.File]::WriteAllText($path, $newContent, (New-Object System.Text.UTF8Encoding $false))
                                $modifiedManifests += @{ Path = $path; Content = $content }
                            }
                        }
                    }
                }
                & powershell -File $realScoop @modifiedArgs
            } finally {
                foreach ($m in $modifiedManifests) {
                    [System.IO.File]::WriteAllText($m.Path, $m.Content, (New-Object System.Text.UTF8Encoding $false))
                }
            }
            return
        }
    }

    & powershell -File $realScoop @modifiedArgs
}
'@

function Update-WrapperInProfile {
    param([switch]$Silent)
    # 1. 清理内存中可能存在的旧函数
    if (Test-Path function:scoop) { Remove-Item function:scoop }

    # 2. 持久化到 Profile
    $ProfileFolder = Split-Path -Parent $PROFILE
    if (-not (Test-Path $ProfileFolder)) { New-Item -Type Directory -Path $ProfileFolder -Force | Out-Null }

    # Remove old wrapper if exists
    if (Test-Path $PROFILE) {
        $ProfileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
        if ($ProfileContent -match '(?s)# --- Scoop Proxy Wrapper Start ---.*?# --- Scoop Proxy Wrapper End ---') {
            $ProfileContent = $ProfileContent -replace '(?s)# --- Scoop Proxy Wrapper Start ---.*?# --- Scoop Proxy Wrapper End ---\r?\n?', ''
            Set-Content -Path $PROFILE -Value $ProfileContent -Encoding UTF8
        }
    }

    $FullWrapper = "`n# --- Scoop Proxy Wrapper Start ---`n$WrapperCodeBlock`n# --- Scoop Proxy Wrapper End ---"
    Add-Content -Path $PROFILE -Value $FullWrapper -Encoding UTF8

    if (!$Silent) { Write-Host "Updated wrapper in PowerShell profile" -ForegroundColor Green }
}

# --- Execution ---

Write-Host "`n>>> Checking Scoop installation status..." -ForegroundColor Cyan
if (Test-ScoopInstalled) {
    # Scoop already installed - run patch mode
    Write-Host "Scoop detected! Running in patch mode..." -ForegroundColor Yellow
    Invoke-PatchScoop
} else {
    # Scoop not installed - run fresh install
    Write-Host "Scoop not detected! Running in install mode..." -ForegroundColor Yellow

    # 1. 清理内存中可能存在的旧函数
    if (Test-Path function:scoop) { Remove-Item function:scoop }

    # 2. 安装核心
    Write-Host "`n>>> STEP 1: Installing Scoop Core..." -ForegroundColor Cyan
    $CoreInstallUrl = "${SCOOP_GH_PROXY}https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1"
    Write-Host "Downloading from: $CoreInstallUrl" -ForegroundColor Yellow
    $InstallScript = Invoke-RestMethod $CoreInstallUrl
    Invoke-Expression $InstallScript

    # 3. 刷新环境并立即加载包装器
    $env:PATH = "$SCOOP_PATH\apps\scoop\current\bin;$SCOOP_PATH\shims;" + $env:PATH
    Invoke-Expression $WrapperCodeBlock

    # 4. 配置 Repo 代理
    Write-Host "`n>>> STEP 2: Configuring Scoop Core Repo Proxy..." -ForegroundColor Cyan
    $CoreRepoUrl = "${SCOOP_GH_PROXY}https://github.com/ScoopInstaller/Scoop.git"
    Write-Host "Setting scoop_repo to: $CoreRepoUrl" -ForegroundColor Yellow
    scoop config scoop_repo $CoreRepoUrl

    # 5. 安装 Essentials (7zip, git)
    Write-Host "`n>>> STEP 3: Installing Essentials (7zip, git) with Proxy Wrapper..." -ForegroundColor Cyan
    scoop install 7zip
    scoop install git

    # 6. 重置 Bucket (Git 现在可用)
    Write-Host "`n>>> STEP 4: Resetting Main Bucket with Git Proxy..." -ForegroundColor Cyan
    scoop bucket rm main 2>$null
    scoop bucket add main

    # 7. 持久化到 Profile
    Write-Host "`n>>> STEP 5: Persisting Wrapper to PowerShell Profile..." -ForegroundColor Cyan
    Update-WrapperInProfile

    Write-Host "`n[SUCCESS] Scoop is fully installed and accelerated!" -ForegroundColor Green
}
