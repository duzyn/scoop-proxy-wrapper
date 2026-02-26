# Disable progress bar
$global:ProgressPreference = 'SilentlyContinue'

# --- Configuration ---
$SCOOP_GH_PROXY = if ($env:SCOOP_GH_PROXY) { $env:SCOOP_GH_PROXY } else { "https://gh-proxy.com/" }
if ($SCOOP_GH_PROXY -notmatch '/$') { $SCOOP_GH_PROXY += "/" }
$SCOOP_PATH = if ($env:SCOOP) { $env:SCOOP } else { "$env:USERPROFILE\scoop" }

# --- Helper: Define the Wrapper Function Logic ---
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
        $apps = @($args | Where-Object { $_.Trim() -and $_.Substring(0,1) -ne '-' }) | Select-Object -Skip 1
        
        foreach ($app in $apps) {
            # BUG FIX: On fresh install, 'scoop info' is empty. Search physical path directly.
            $path = "$env:USERPROFILE\scoop\buckets\main\bucket\$app.json"
            if (-not (Test-Path $path)) {
                $info = & powershell -File $realScoop info $app 2>$null | Out-String
                if ($info -match "(?m)^Manifest:\s*(.+)$") { $path = $matches[1].Trim() }
            }

            if (Test-Path $path) {
                $content = [System.IO.File]::ReadAllText($path)
                $escapedProxy = [regex]::Escape($INTERNAL_PROXY)
                # Standard GitHub pattern
                $pattern = "(?<!$escapedProxy)(https://github\.com/[^/]+/[^/]+/(?:releases/(?:latest/)?download|archive)/)"
                # 7zip specific pattern (handles version digits)
                $szPattern = 'https?://www\.7-zip\.org/a/7z[^\s"]+'

                if ($content -match $pattern -or $content -match $szPattern) {
                    Write-Host ">>> Injecting Proxy [$INTERNAL_PROXY] for '$app'..." -ForegroundColor Cyan
                    $newContent = $content -replace $pattern, "${INTERNAL_PROXY}$1"
                    $newContent = $newContent -replace '(https?://www\.7-zip\.org/a/7z)(\d+)([^\s"]+)', "${INTERNAL_PROXY}https://github.com/ip7z/7zip/releases/download/`$2.`$3/7z`$2`$3"
                    # If the above GitHub redirect for 7zip is too complex, just prefix the original:
                    if ($app -eq "7zip" -and $newContent -notmatch $escapedProxy) {
                        $newContent = $content -replace "($szPattern)", "${INTERNAL_PROXY}`$1"
                    }
                    
                    [System.IO.File]::WriteAllText($path, $newContent, (New-Object System.Text.UTF8Encoding $false))
                    $modifiedManifests += @{ Path = $path; Content = $content }
                }
            }
        }
        try { & powershell -File $realScoop @modifiedArgs }
        finally {
            foreach ($m in $modifiedManifests) {
                [System.IO.File]::WriteAllText($m.Path, $m.Content, (New-Object System.Text.UTF8Encoding $false))
            }
        }
        return
    }

    & powershell -File $realScoop @modifiedArgs
}
'@

# --- Execution ---

# 1. Clean current session
if (Test-Path function:scoop) { Remove-Item function:scoop }

# 2. Step 1: Install Scoop Core
Write-Host "`n>>> STEP 1: Installing Scoop Core..." -ForegroundColor Cyan
$CoreInstallUrl = "${SCOOP_GH_PROXY}https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1"
Write-Host "Downloading from: $CoreInstallUrl" -ForegroundColor Yellow
$InstallScript = Invoke-RestMethod $CoreInstallUrl
Invoke-Expression $InstallScript

# 3. Step 2: Load Wrapper
$env:PATH = "$SCOOP_PATH\current\bin;$SCOOP_PATH\shims;" + $env:PATH
Invoke-Expression $WrapperCodeBlock

# 4. Step 3: Set Repo Proxy
Write-Host "`n>>> STEP 2: Configuring Scoop Core Repo Proxy..." -ForegroundColor Cyan
scoop config scoop_repo "${SCOOP_GH_PROXY}https://github.com/ScoopInstaller/Scoop.git"

# 5. Step 4: Install Essentials
Write-Host "`n>>> STEP 3: Installing Essentials (7zip, git)..." -ForegroundColor Cyan
# Now the wrapper will find manifests in $env:USERPROFILE\scoop\buckets\main\bucket\ even without index
scoop install 7zip
scoop install git

# 6. Step 5: Reset Bucket
Write-Host "`n>>> STEP 4: Resetting Main Bucket with Git Proxy..." -ForegroundColor Cyan
scoop bucket rm main 2>$null
scoop bucket add main

# 7. Step 6: Persist
Write-Host "`n>>> STEP 5: Persisting Wrapper to Profile..." -ForegroundColor Cyan
$ProfileFolder = Split-Path -Parent $PROFILE
if (-not (Test-Path $ProfileFolder)) { New-Item -Type Directory -Path $ProfileFolder -Force | Out-Null }
$FullWrapper = "`n# --- Scoop Proxy Wrapper Start ---`n$WrapperCodeBlock`n# --- Scoop Proxy Wrapper End ---"
Set-Content -Path $PROFILE -Value $FullWrapper -Encoding UTF8

Write-Host "`n[SUCCESS] Scoop is fully installed and accelerated!" -ForegroundColor Green
