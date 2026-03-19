function scoop {
    <#
    .SYNOPSIS
    Ultimate Non-Invasive Scoop Proxy Wrapper.
    Handles Known Buckets, GitHub Releases, and 7-Zip redirects.
    #>

    # --- 1. 配置与环境变量 ---
    $proxyPrefix = if ($env:SCOOP_GH_PROXY) { $env:SCOOP_GH_PROXY } else { "https://gh-proxy.com/" }
    if ($proxyPrefix -notmatch '/$') { $proxyPrefix += "/" }
    
    $env:SCOOP_INTERNAL_PROXY = $proxyPrefix
    $env:SCOOP_INTERNAL_DEBUG = ($env:SCOOP_DEBUG -eq 'true')
    
    # 拦截指令集
    $proxyCommands = @('install', 'update', 'download', 'reinstall', 'bucket')
    $currentSubCmd = $args[0]
    $isProxyAction = $proxyCommands -contains $currentSubCmd
    $env:SCOOP_HOOK_ACTIVE = $isProxyAction.ToString()

    $realScoop = (Get-Command -CommandType ExternalScript -Name scoop -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $realScoop) { return }

    if ($env:SCOOP_INTERNAL_DEBUG -eq 'True' -and $isProxyAction) {
        Write-Host "`n" + ("=" * 60) -ForegroundColor DarkGray
        Write-Host "🚀 SCOOP PROXY DEBUG MODE: ON (Action: $currentSubCmd)" -ForegroundColor Green
        Write-Host "🔗 Using Proxy: $proxyPrefix" -ForegroundColor DarkGray
        Write-Host ("=" * 60) -ForegroundColor DarkGray
    }

    # --- 2. 拦截器 1：JSON 解析器劫持 ---
    $jsonHook = {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline=$true)] $InputObject,[int]$Depth, [switch]$AsHashtable, [switch]$NoEnumerate)
        begin { $inputStr = @() }
        process { if ($null -ne $InputObject) { $inputStr += $InputObject } }
        end {
            $jsonString = $inputStr -join "`n"
            if ([string]::IsNullOrWhiteSpace($jsonString)) { return }

            $cmd = Get-Command -Name Microsoft.PowerShell.Utility\ConvertFrom-Json -CommandType Cmdlet
            $execParams = @{ InputObject = $jsonString }
            if ($PSBoundParameters.ContainsKey('Depth') -and $cmd.Parameters.ContainsKey('Depth')) { $execParams['Depth'] = $Depth }
            if ($PSBoundParameters.ContainsKey('AsHashtable') -and $cmd.Parameters.ContainsKey('AsHashtable')) { $execParams['AsHashtable'] = $AsHashtable }
            if ($PSBoundParameters.ContainsKey('NoEnumerate') -and $cmd.Parameters.ContainsKey('NoEnumerate')) { $execParams['NoEnumerate'] = $NoEnumerate }

            try { $obj = & $cmd @execParams } catch { throw }

            if ($env:SCOOP_HOOK_ACTIVE -ne 'True') { return $obj }

            function Proxify-Str($str) {
                if ($str -is [string]) {
                    $newUrl = $null
                    $proxyPrefix = $env:SCOOP_INTERNAL_PROXY

                    # Skip if already proxified
                    if ($str -match [regex]::Escape($proxyPrefix)) {
                        return $str
                    }

                    # 匹配 GitHub Releases / Raw / Archive
                    if ($str -match '^https://(github\.com|raw\.githubusercontent\.com)/') {
                        $newUrl = $str -replace '^https://', ($proxyPrefix + 'https://')
                    }
                    # 匹配 7-Zip 并重定向到 GitHub 镜像 (更稳健的正则)
                    elseif ($str -match 'https?://www\.7-zip\.org/a/7z(\d+)([^\s"]+)') {
                        $verMajor = $matches[1]; $verFull = $matches[2]
                        $newUrl = $proxyPrefix + "https://github.com/ip7z/7zip/releases/download/$($verMajor.Insert($verMajor.Length-2,'.'))$verFull/7z$verMajor$verFull"
                    }

                    if ($null -ne $newUrl) {
                        if ($env:SCOOP_INTERNAL_DEBUG -eq 'True') {
                            Write-Host "➔ [JSON Hook] Redirecting: $str" -ForegroundColor Cyan
                        }
                        return $newUrl
                    }
                }
                return $str
            }

            function Proxify-Obj($node) {
                if ($null -eq $node -or $node -is [string]) { return }
                if ($node -is [array]) {
                    for ($i = 0; $i -lt $node.Count; $i++) {
                        if ($node[$i] -is [string]) { $node[$i] = Proxify-Str $node[$i] } else { Proxify-Obj $node[$i] }
                    }
                } elseif ($node -is [System.Management.Automation.PSCustomObject]) {
                    foreach ($prop in $node.psobject.properties) {
                        if ($prop.Value -is [string] -and $prop.Name -match 'url') { $prop.Value = Proxify-Str $prop.Value } else { Proxify-Obj $prop.Value }
                    }
                } elseif ($node -is [hashtable]) {
                    $keys = @($node.Keys)
                    foreach ($k in $keys) {
                        if ($node[$k] -is [string] -and $k -match 'url') { $node[$k] = Proxify-Str $node[$k] } else { Proxify-Obj $node[$k] }
                    }
                }
            }
            try { Proxify-Obj $obj } catch {}
            return $obj
        }
    }

    # --- 3. 拦截器 2：Aria2c 免检证书 ---
    $scoopPath = if ($env:SCOOP) { $env:SCOOP } else { "$env:USERPROFILE\scoop" }
    $aria2Path = "$scoopPath\apps\aria2\current\aria2c.exe"
    $aria2Hook = {
        if ($env:SCOOP_INTERNAL_DEBUG -eq 'True' -and $env:SCOOP_HOOK_ACTIVE -eq 'True') {
            Write-Host "➔ [Aria2c Hook] Certificate check bypassed." -ForegroundColor Yellow
        }
        $appCmd = Get-Command $aria2Path -CommandType Application
        & $appCmd @args "--check-certificate=false"
        $global:LASTEXITCODE = $LASTEXITCODE
    }

    # --- 4. 挂载与执行 ---
    Set-Item -Path "Function:global:ConvertFrom-Json" -Value $jsonHook
    if (Test-Path $aria2Path) { Set-Item -Path "Function:global:$aria2Path" -Value $aria2Hook }

    # Git insteadOf 核心逻辑：解决已知仓库加速
    $gitProxyKey = "url.${proxyPrefix}https://github.com/.insteadOf"
    $originalGitConfig = git config --global --get $gitProxyKey 2>$null
    if ($isProxyAction -and -not $originalGitConfig) {
        if ($env:SCOOP_INTERNAL_DEBUG -eq 'True') {
            Write-Host "➔ [Git Hook] Applied github.com redirection for Buckets." -ForegroundColor Magenta
        }
        git config --global $gitProxyKey "https://github.com/" 2>$null
    }

    try {
        & $realScoop @args
    } 
    finally {
        if (Test-Path "Function:global:ConvertFrom-Json") { Remove-Item "Function:global:ConvertFrom-Json" }
        if (Test-Path "Function:global:$aria2Path") { Remove-Item "Function:global:$aria2Path" }
        
        if ($isProxyAction -and -not $originalGitConfig) {
            git config --global --unset $gitProxyKey 2>$null
        }

        if ($env:SCOOP_INTERNAL_DEBUG -eq 'True' -and $isProxyAction) {
            Write-Host ("-" * 60) + "`n" -ForegroundColor DarkGray
        }

        $env:SCOOP_INTERNAL_PROXY = $null
        $env:SCOOP_INTERNAL_DEBUG = $null
        $env:SCOOP_HOOK_ACTIVE = $null
    }
}

# If this script is called directly (not sourced), invoke scoop with arguments
if ($MyInvocation.InvocationName -ne '.') {
    scoop @args
}
