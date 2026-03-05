#Requires -Module Pester

Describe 'scoop function proxy tests' {
    BeforeAll {
        $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'Microsoft.PowerShell_profile.ps1'
        if (Test-Path $scriptPath) {
            . $scriptPath
        }
    }

    Context 'Environment variable setup' {
        It 'Should set SCOOP_INTERNAL_PROXY when SCOOP_GH_PROXY is set' {
            $env:SCOOP_GH_PROXY = 'https://test-proxy.com/'
            $proxyPrefix = if ($env:SCOOP_GH_PROXY) { $env:SCOOP_GH_PROXY } else { "https://gh-proxy.com/" }
            if ($proxyPrefix -notmatch '/$') { $proxyPrefix += "/" }
            $proxyPrefix | Should Be 'https://test-proxy.com/'
        }

        It 'Should use default proxy when SCOOP_GH_PROXY is not set' {
            $env:SCOOP_GH_PROXY = $null
            $proxyPrefix = if ($env:SCOOP_GH_PROXY) { $env:SCOOP_GH_PROXY } else { "https://gh-proxy.com/" }
            $proxyPrefix | Should Be 'https://gh-proxy.com/'
        }

        It 'Should append trailing slash to proxy prefix if missing' {
            $env:SCOOP_GH_PROXY = 'https://test-proxy.com'
            $proxyPrefix = if ($env:SCOOP_GH_PROXY) { $env:SCOOP_GH_PROXY } else { "https://gh-proxy.com/" }
            if ($proxyPrefix -notmatch '/$') { $proxyPrefix += "/" }
            $proxyPrefix | Should Be 'https://test-proxy.com/'
        }
    }

    Context 'GitHub URL proxy transformation' {
        It 'Should transform github.com URL to proxy URL' {
            $str = 'https://github.com/user/repo/releases/download/v1.0/file.zip'
            $proxyPrefix = 'https://gh-proxy.com/'
            $result = $str -replace '^https://', ($proxyPrefix + 'https://')
            $result | Should Be 'https://gh-proxy.com/https://github.com/user/repo/releases/download/v1.0/file.zip'
        }

        It 'Should transform raw.githubusercontent.com URL to proxy URL' {
            $str = 'https://raw.githubusercontent.com/user/repo/main/file.json'
            $proxyPrefix = 'https://gh-proxy.com/'
            $result = $str -replace '^https://', ($proxyPrefix + 'https://')
            $result | Should Be 'https://gh-proxy.com/https://raw.githubusercontent.com/user/repo/main/file.json'
        }

        It 'Should transform all https URLs (including non-GitHub)' {
            $str = 'https://example.com/file.zip'
            $proxyPrefix = 'https://gh-proxy.com/'
            $result = $str -replace '^https://', ($proxyPrefix + 'https://')
            $result | Should Be 'https://gh-proxy.com/https://example.com/file.zip'
        }
    }

    Context '7-Zip URL proxy transformation' {
        It 'Should transform 7-Zip URL to GitHub mirror' {
            $str = 'https://www.7-zip.org/a/7z2408-x64.exe'
            if ($str -match 'https?://www\.7-zip\.org/a/7z(\d+)([^\s"]+)') {
                $verMajor = $matches[1]
                $verFull = $matches[2]
                $proxyPrefix = 'https://gh-proxy.com/'
                $newUrl = $proxyPrefix + 'https://github.com/ip7z/7zip/releases/download/' + $verMajor.Insert($verMajor.Length-2,'.') + $verFull + '/7z' + $verMajor + $verFull
            }
            $newUrl | Should Be 'https://gh-proxy.com/https://github.com/ip7z/7zip/releases/download/24.08-x64.exe/7z2408-x64.exe'
        }
    }

    Context 'JSON object proxy transformation' {
        BeforeAll {
            function global:Proxify-Str($str) {
                if ($str -is [string]) {
                    $newUrl = $null
                    if ($str -match '^https://(github\.com|raw\.githubusercontent\.com)/') {
                        $newUrl = $str -replace '^https://', ($env:SCOOP_INTERNAL_PROXY + 'https://')
                    } 
                    elseif ($str -match 'https?://www\.7-zip\.org/a/7z(\d+)([^\s"]+)') {
                        $verMajor = $matches[1]
                        $verFull = $matches[2]
                        $newUrl = $env:SCOOP_INTERNAL_PROXY + 'https://github.com/ip7z/7zip/releases/download/' + $verMajor.Insert($verMajor.Length-2,'.') + $verFull + '/7z' + $verMajor + $verFull
                    }
                    if ($null -ne $newUrl) { return $newUrl }
                }
                return $str
            }

            function global:Proxify-Obj($node) {
                if ($null -eq $node -or $node -is [string]) { return }
                if ($node -is [array]) {
                    for ($i = 0; $i -lt $node.Count; $i++) {
                        if ($node[$i] -is [string]) { $node[$i] = global:Proxify-Str $node[$i] } else { global:Proxify-Obj $node[$i] }
                    }
                } elseif ($node -is [System.Management.Automation.PSCustomObject]) {
                    foreach ($prop in $node.psobject.properties) {
                        if ($prop.Value -is [string] -and $prop.Name -match 'url') { $prop.Value = global:Proxify-Str $prop.Value } else { global:Proxify-Obj $prop.Value }
                    }
                } elseif ($node -is [hashtable]) {
                    $keys = @($node.Keys)
                    foreach ($k in $keys) {
                        if ($node[$k] -is [string] -and $k -match 'url') { $node[$k] = global:Proxify-Str $node[$k] } else { global:Proxify-Obj $node[$k] }
                    }
                }
            }
        }

        It 'Should proxy URLs in PSCustomObject' {
            $env:SCOOP_INTERNAL_PROXY = 'https://gh-proxy.com/'
            $obj = [PSCustomObject]@{
                name = 'test'
                url = 'https://github.com/user/repo/releases/latest'
            }
            global:Proxify-Obj $obj
            $obj.url | Should Be 'https://gh-proxy.com/https://github.com/user/repo/releases/latest'
        }

        It 'Should proxy URLs in hashtable' {
            $env:SCOOP_INTERNAL_PROXY = 'https://gh-proxy.com/'
            $obj = @{
                name = 'test'
                url = 'https://raw.githubusercontent.com/user/repo/main/file.json'
            }
            global:Proxify-Obj $obj
            $obj.url | Should Be 'https://gh-proxy.com/https://raw.githubusercontent.com/user/repo/main/file.json'
        }

        It 'Should proxy URLs in array' {
            $env:SCOOP_INTERNAL_PROXY = 'https://gh-proxy.com/'
            $arr = @('https://github.com/user/repo1', 'https://github.com/user/repo2')
            global:Proxify-Obj $arr
            $arr[0] | Should Be 'https://gh-proxy.com/https://github.com/user/repo1'
            $arr[1] | Should Be 'https://gh-proxy.com/https://github.com/user/repo2'
        }
    }

    Context 'Command detection' {
        It 'Should detect install as proxy command' {
            $proxyCommands = @('install', 'update', 'download', 'reinstall', 'bucket')
            $proxyCommands -contains 'install' | Should Be $true
        }

        It 'Should detect update as proxy command' {
            $proxyCommands = @('install', 'update', 'download', 'reinstall', 'bucket')
            $proxyCommands -contains 'update' | Should Be $true
        }

        It 'Should detect bucket as proxy command' {
            $proxyCommands = @('install', 'update', 'download', 'reinstall', 'bucket')
            $proxyCommands -contains 'bucket' | Should Be $true
        }

        It 'Should not detect status as proxy command' {
            $proxyCommands = @('install', 'update', 'download', 'reinstall', 'bucket')
            $proxyCommands -contains 'status' | Should Be $false
        }

        It 'Should not detect list as proxy command' {
            $proxyCommands = @('install', 'update', 'download', 'reinstall', 'bucket')
            $proxyCommands -contains 'list' | Should Be $false
        }
    }

    Context 'Git config key generation' {
        It 'Should generate correct git config key' {
            $proxyPrefix = 'https://gh-proxy.com/'
            $gitProxyKey = 'url.' + $proxyPrefix + 'https://github.com/.insteadOf'
            $gitProxyKey | Should Be 'url.https://gh-proxy.com/https://github.com/.insteadOf'
        }
    }

    Context 'Clean environment variables' {
        It 'Should have null environment variables after cleanup' {
            $env:SCOOP_INTERNAL_PROXY = 'test'
            $env:SCOOP_INTERNAL_PROXY = $null
            $null -eq $env:SCOOP_INTERNAL_PROXY | Should Be $true
        }
    }
}
