@echo off
:: Scoop Proxy Wrapper for CMD
setlocal

set "scriptDir=%~dp0"
set "profilePath=%scriptDir%profile.ps1"

if not exist "%profilePath%" (
    if defined SCOOP (
        set "profilePath=%SCOOP%\apps\scoop-proxy-wrapper\current\profile.ps1"
    ) else (
        set "profilePath=%USERPROFILE%\scoop\apps\scoop-proxy-wrapper\current\profile.ps1"
    )
)

if exist "%profilePath%" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%profilePath%" %*
) else (
    powershell.exe -NoProfile -Command "scoop %*"
)

exit /b %errorlevel%
