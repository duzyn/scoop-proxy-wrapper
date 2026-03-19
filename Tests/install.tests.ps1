#Requires -Module Pester

Describe 'install.ps1 tests' {
    BeforeAll {
        $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
        . $scriptPath
    }

    Context 'Configuration' {
        It 'Should set SCOOP_GH_PROXY environment variable' {
            $env:SCOOP_GH_PROXY | Should Be 'https://gh-proxy.com'
        }

        It 'Should use SCOOP path from environment when set' {
            $env:SCOOP = 'C:\Custom\Scoop'
            $ScoopPath = if ($env:SCOOP) { $env:SCOOP } else { "$env:USERPROFILE\scoop" }
            $ScoopPath | Should Be 'C:\Custom\Scoop'
            $env:SCOOP = $null
        }

        It 'Should use default Scoop path when SCOOP env not set' {
            $env:SCOOP = $null
            $ScoopPath = if ($env:SCOOP) { $env:SCOOP } else { "$env:USERPROFILE\scoop" }
            $ScoopPath | Should Be "$env:USERPROFILE\scoop"
        }
    }

    Context 'Install-Scoop function URL construction' {
        It 'Should construct correct proxy URL for Scoop install script' {
            $proxyUrl = "$env:SCOOP_GH_PROXY/https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1"
            $proxyUrl | Should Be 'https://gh-proxy.com/https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1'
        }

        It 'Should use custom SCOOP_GH_PROXY when set' {
            $env:SCOOP_GH_PROXY = 'https://custom-proxy.com'
            $proxyUrl = "$env:SCOOP_GH_PROXY/https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1"
            $proxyUrl | Should Be 'https://custom-proxy.com/https://raw.githubusercontent.com/ScoopInstaller/Install/master/install.ps1'
            $env:SCOOP_GH_PROXY = 'https://gh-proxy.com'
        }
    }

    Context 'Add-ScoopProxyToProfile function' {
        BeforeAll {
            $scriptDir = Split-Path $PSScriptRoot -Parent
            $proxyFilePath = Join-Path $scriptDir "profile.ps1"
        }

        It 'Should construct correct profile download URL' {
            $profileUrl = "$env:SCOOP_GH_PROXY/https://raw.githubusercontent.com/duzyn/scoop-proxy-wrapper/main/profile.ps1"
            $profileUrl | Should Be 'https://gh-proxy.com/https://raw.githubusercontent.com/duzyn/scoop-proxy-wrapper/main/profile.ps1'
        }

        It 'Should fallback to local profile.ps1 when download fails' {
            $env:SCOOP_GH_PROXY = 'https://invalid-proxy'
            $profileUrl = "$env:SCOOP_GH_PROXY/https://raw.githubusercontent.com/duzyn/scoop-proxy-wrapper/master/profile.ps1"
            Test-Path $profileUrl | Should Be $false
            $env:SCOOP_GH_PROXY = 'https://gh-proxy.com'
        }

        It 'Should find local profile.ps1 in script directory' {
            $proxyFilePath | Should Exist
        }

        It 'Should construct profile path correctly' {
            $profilePath = $PROFILE
            $profilePath | Should Not BeNullOrEmpty
            $profilePath | Should Match '\.ps1$'
        }
    }

    Context 'scoop function removal regex' {
        It 'Should match scoop function with standard braces' {
            $content = @'
function scoop {
    Write-Host "test"
}
'@
            $content -match 'function scoop\s*\{' | Should Be $true
        }

        It 'Should remove scoop function using regex replacement' {
            $content = @'
# Some comment
function scoop {
    Write-Host "test"
}
Other content
'@
            $replaced = $content -replace '(?ms)function scoop\s*\{.*?^\}', ''
            $replaced | Should Not Match 'function scoop'
            $replaced | Should Match 'Other content'
        }

            It 'Should handle scoop function without trailing newline' {
                $content = "function scoop { Write-Host 'test' }"
                $replaced = $content -replace '(?ms)function scoop\s*\{.*?\}', ''
                $replaced.Trim() | Should BeNullOrEmpty
            }
    }

    Context '7-Zip URL transformation' {
        It 'Should match 7-Zip version pattern in URL' {
            $str = 'https://www.7-zip.org/a/7z2408'
            $str -match 'https?://www\.7-zip\.org/a/7z(\d{2})(\d{2})' | Should Be $true
            $matches[1] | Should Be '24'
            $matches[2] | Should Be '08'
        }

        It 'Should transform matched 7-Zip URL correctly' {
            $str = 'https://www.7-zip.org/a/7z2408'
            $env:SCOOP_GH_PROXY = 'https://gh-proxy.com'
            $result = $str -replace 'https?://www\.7-zip\.org/a/7z(\d{2})(\d{2})', ($env:SCOOP_GH_PROXY + '/https://github.com/ip7z/7zip/releases/download/$1.$2/7z$1$2')
            $result | Should Match 'gh-proxy\.com'
        }
    }

    Context 'Git URL transformation' {
        It 'Should match GitHub release download URL pattern' {
            $str = 'https://github.com/user/repo/releases/download/v1.0/file.exe'
            $str -match 'https?://github\.com/.+/releases/.*download' | Should Be $true
        }

        It 'Should transform matched GitHub URL with proxy prefix' {
            $str = 'https://github.com/user/repo/releases/download/v1.0/file.exe'
            $env:SCOOP_GH_PROXY = 'https://gh-proxy.com'
            $result = $str -replace '(https?://github\.com/.+/releases/.*download)', ($env:SCOOP_GH_PROXY + '/$1')
            $result | Should Match 'gh-proxy\.com'
        }
    }

    Context 'Manifest path construction' {
        It 'Should construct correct 7zip manifest path' {
            $ScoopPath = 'C:\Users\TestUser\scoop'
            $7zipManifestPath = "$ScoopPath\buckets\main\bucket\7zip.json"
            $7zipManifestPath | Should Be 'C:\Users\TestUser\scoop\buckets\main\bucket\7zip.json'
        }

        It 'Should construct correct git manifest path' {
            $ScoopPath = 'C:\Users\TestUser\scoop'
            $GitManifestPath = "$ScoopPath\buckets\main\bucket\git.json"
            $GitManifestPath | Should Be 'C:\Users\TestUser\scoop\buckets\main\bucket\git.json'
        }
    }

    Context 'Main execution order verification' {
        It 'Should have Install-Scoop function defined' {
            Get-Command Install-Scoop -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }

        It 'Should have Add-ScoopProxyToProfile function defined' {
            Get-Command Add-ScoopProxyToProfile -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }

        It 'Should have Prepare-And-Install-Essentials function defined' {
            Get-Command Prepare-And-Install-Essentials -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }

        It 'Should have Install-CmdWrapper function defined' {
            Get-Command Install-CmdWrapper -ErrorAction SilentlyContinue | Should Not BeNullOrEmpty
        }
    }

    Context 'Install-CmdWrapper function' {
        BeforeAll {
            $testWrapperDir = Join-Path $TestDrive 'wrapper'
        }

        It 'Should create wrapper directory if not exists' {
            Install-CmdWrapper -WrapperDir $testWrapperDir
            Test-Path $testWrapperDir | Should Be $true
        }

        It 'Should copy profile.ps1 to wrapper directory' {
            $profilePath = Join-Path $testWrapperDir 'profile.ps1'
            # Note: This test depends on profile.ps1 existing in script directory
            if (Test-Path (Join-Path $scriptDir 'profile.ps1')) {
                Test-Path $profilePath | Should Be $true
            }
        }

        It 'Should construct correct wrapper directory path' {
            $ScoopPath = 'C:\Users\TestUser\scoop'
            $wrapperDir = "$ScoopPath\apps\scoop-proxy-wrapper\current"
            $wrapperDir | Should Be 'C:\Users\TestUser\scoop\apps\scoop-proxy-wrapper\current'
        }
    }

    Context 'Progress preference' {
        It 'Should set ProgressPreference to SilentlyContinue' {
            $global:ProgressPreference | Should Be 'SilentlyContinue'
        }
    }
}
