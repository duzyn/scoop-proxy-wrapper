#Requires -Module Pester

Describe 'Scoop Proxy Wrapper Command Tests' {
    BeforeAll {
        $env:SCOOP_DEBUG = 'true'
        $profilePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'profile.ps1'
        . $profilePath
    }

    AfterAll {
        $env:SCOOP_DEBUG = $null
    }

    Context 'scoop update' {
        It 'Should update scoop without double proxy error' {
            { scoop update } | Should Not Throw
        }
    }

    Context 'scoop list' {
        It 'Should list installed apps' {
            { scoop list } | Should Not Throw
        }
    }

    Context 'scoop status' {
        It 'Should show status' {
            { scoop status } | Should Not Throw
        }
    }

    Context 'scoop bucket list' {
        It 'Should list buckets' {
            { scoop bucket list } | Should Not Throw
        }
    }

    Context 'scoop search' {
        It 'Should search for apps' {
            { scoop search git } | Should Not Throw
        }
    }

    Context 'scoop --version' {
        It 'Should show version' {
            { scoop --version } | Should Not Throw
        }
    }

    Context 'scoop help' {
        It 'Should show help' {
            { scoop help } | Should Not Throw
        }
    }

    Context 'scoop checkup' {
        It 'Should run checkup' {
            { scoop checkup } | Should Not Throw
        }
    }

    Context 'scoop cache show' {
        It 'Should show cache' {
            { scoop cache show } | Should Not Throw
        }
    }

    Context 'scoop export' {
        It 'Should export app list' {
            { scoop export } | Should Not Throw
        }
    }
}
