# Scoop Proxy Wrapper - Auto Test & Update Script
# 自动测试并更新CLAUDE.md的脚本

param(
    [string]$CommitMessage = "Auto test: update install.ps1",
    [int]$MaxRetries = 5,
    [int]$WaitSeconds = 30
)

$ErrorActionPreference = "Stop"

# Add gh to PATH
$env:PATH = "C:\Users\WPS\scoop\shims;$env:PATH"
$GhExePath = "C:\Users\WPS\scoop\shims\gh.exe"

# --- Configuration ---
$RepoOwner = "duzyn"
$RepoName = "scoop-proxy-wrapper"
$WorkflowFile = "test.yml"
$Branch = "main"

# Colors for output
function Write-Status { param($msg, $color = "Cyan") Write-Host $msg -ForegroundColor $color }
function Write-Success { param($msg) Write-Host $msg -ForegroundColor Green }
function Write-Error { param($msg) Write-Host $msg -ForegroundColor Red }
function Write-Warning { param($msg) Write-Host $msg -ForegroundColor Yellow }

# --- Helper function to run gh ---
function Invoke-GhApi {
    param([string]$Endpoint, [string]$jqFilter = $null)
    $cmd = "$GhExePath api $Endpoint"
    if ($jqFilter) {
        $cmd += " --jq '$jqFilter'"
    }
    Invoke-Expression $cmd
}

# --- Step 1: Check gh auth ---
Write-Status "=== Step 1: Checking GitHub CLI authentication ==="

$authStatus = & $GhExePath auth status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not logged in to GitHub. Please run: gh auth login"
    exit 1
}
Write-Success "GitHub CLI authenticated"

# --- Step 2: Commit and Push changes ---
Write-Status "=== Step 2: Committing and pushing changes ==="

# Check if there are changes
$status = git status --porcelain
if (-not $status) {
    Write-Warning "No changes to commit. Skipping commit step."
} else {
    # Add all changes
    git add install.ps1
    git add CLAUDE.md
    git add auto-test.ps1
    git add .github/workflows/test.yml

    # Commit
    git commit -m $CommitMessage
    Write-Success "Changes committed"

    # Push
    git push origin $Branch
    Write-Success "Changes pushed to GitHub"
}

# --- Step 3: Trigger and wait for workflow ---
Write-Status "=== Step 3: Triggering workflow run ==="

# Get the latest commit SHA
$commitSha = git rev-parse HEAD
Write-Status "Commit SHA: $commitSha"

Write-Status "Waiting for workflow to start..."
Start-Sleep -Seconds 5

# Find the latest workflow run for this commit
$retryCount = 0
$runId = $null

while ($retryCount -lt $MaxRetries -and -not $runId) {
    # Get all runs and filter in PowerShell
    $runsJson = & $GhExePath api "repos/$RepoOwner/$RepoName/actions/runs" 2>$null | ConvertFrom-Json
    $matchingRun = $runsJson.workflow_runs | Where-Object { $_.head_sha -eq $commitSha } | Select-Object -First 1

    if ($matchingRun) {
        $runId = $matchingRun.id
    }

    if (-not $runId) {
        $retryCount++
        Write-Status "Waiting for workflow to appear... (attempt $retryCount/$MaxRetries)"
        Start-Sleep -Seconds $WaitSeconds
    }
}

if (-not $runId) {
    Write-Error "Could not find workflow run after $MaxRetries attempts"
    exit 1
}

Write-Success "Found workflow run: $runId"

# --- Step 4: Wait for workflow to complete ---
Write-Status "=== Step 4: Waiting for workflow to complete ==="

$completed = $false
$success = $false

while (-not $completed) {
    $runInfo = & $GhExePath api "repos/$RepoOwner/$RepoName/actions/runs/$runId" --jq '.status, .conclusion'
    $status = $runInfo[0]
    $conclusion = $runInfo[1]

    if ($status -eq "completed") {
        $completed = $true
        if ($conclusion -eq "success") {
            $success = $true
        }
    } else {
        Write-Status "Workflow status: $status... waiting"
        Start-Sleep -Seconds 30
    }
}

if ($success) {
    Write-Success "Workflow completed successfully!"
} else {
    Write-Error "Workflow failed with conclusion: $conclusion"
    exit 1
}

# --- Step 5: Get and parse workflow output ---
Write-Status "=== Step 5: Getting workflow output ==="

# Get jobs
$jobsJson = & $GhExePath api "repos/$RepoOwner/$RepoName/actions/runs/$runId/jobs" | ConvertFrom-Json

# Print summary
Write-Host "`n=== Workflow Summary ===" -ForegroundColor Cyan

$failedSteps = @()
foreach ($job in $jobsJson.jobs) {
    Write-Host "`nJob: $($job.name) - $($job.conclusion)" -ForegroundColor $(if ($job.conclusion -eq "success") { "Green" } else { "Red" })

    foreach ($step in $job.steps) {
        $color = if ($step.conclusion -eq "success") { "Green" } elseif ($step.conclusion -eq "skipped") { "Gray" } else { "Red" }
        Write-Host "  - $($step.name): $($step.conclusion)" -ForegroundColor $color

        if ($step.conclusion -ne "success" -and $step.conclusion -ne "skipped") {
            $failedSteps += "$($job.name): $($step.name)"
        }
    }
}

if ($failedSteps.Count -gt 0) {
    Write-Error "Failed steps: $($failedSteps -join ', ')"
    exit 1
}

# --- Step 6: Verify target achieved ---
Write-Status "=== Step 6: Verifying target achievements ==="

$allPassed = $true
foreach ($job in $jobsJson.jobs) {
    if ($job.name -eq "test") {
        foreach ($step in $job.steps) {
            if ($step.name -match "Verification") {
                Write-Host "$($step.name): $($step.conclusion)" -ForegroundColor $(if ($step.conclusion -eq "success") { "Green" } else { "Red" })
                if ($step.conclusion -ne "success") {
                    $allPassed = $false
                }
            }
        }
    }
}

if (-not $allPassed) {
    Write-Error "Some verifications failed"
    exit 1
}

Write-Success "All verifications passed!"

# --- Step 7: Update CLAUDE.md ---
Write-Status "=== Step 7: Updating CLAUDE.md ==="

# Read current CLAUDE.md
$claudeMdPath = "CLAUDE.md"
$content = Get-Content $claudeMdPath -Raw

# Update the last-updated timestamp or add status
$date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$newStatus = @"

## Last Auto-Test Result

- **Date**: $date
- **Status**: PASSED
- **Workflow Run**: https://github.com/$RepoOwner/$RepoName/actions/runs/$runId
- **Commit**: $commitSha
"@

# Check if there's already a status section
if ($content -match '(?s)## Last Auto-Test Result.*?(?=##|$)') {
    # Replace existing status
    $content = $content -replace '(?s)## Last Auto-Test Result.*?(?=##|$)', $newStatus.Trim()
} else {
    # Append new status
    $content = $content.TrimEnd() + "`n`n$newStatus"
}

Set-Content -Path $claudeMdPath -Value $content -Encoding UTF8
Write-Success "CLAUDE.md updated"

# Commit and push CLAUDE.md update
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with test results"
git push origin $Branch

Write-Success "`n=== All tasks completed successfully! ==="
Write-Host "Workflow: https://github.com/$RepoOwner/$RepoName/actions/runs/$runId"
