<#
.SYNOPSIS
    verify-windows-environment.ps1: Rigorous Runtime Verification of Windows Studio
.DESCRIPTION
    Validates RDP, OpenSSH, Tailscale, persistent workspace structure,
    Node.js ecosystem, Python ecosystem, Cloud CLIs, and AI Coding Assistants.
#>

[CmdletBinding()]
param(
    [string]$WorkspaceDir = "C:\Users\runneradmin\workspace"
)

$ErrorActionPreference = "Continue"

# Refresh Process PATH from Machine and User environments
$machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
$env:PATH = "C:\npm\prefix;C:\npm\prefix\bin;C:\Program Files\nodejs;C:\ProgramData\chocolatey\bin;C:\Users\runneradmin\AppData\Local\agy\bin;$env:USERPROFILE\.local\bin;$env:USERPROFILE\.bun\bin;$env:USERPROFILE\.cargo\bin;$env:USERPROFILE\AppData\Roaming\npm;C:\Users\runneradmin\AppData\Roaming\npm;$machinePath;$userPath;$env:PATH"

$extraPaths = @(
    "C:\npm\prefix",
    "C:\npm\prefix\bin",
    "C:\Program Files\nodejs",
    "$env:APPDATA\npm",
    "C:\ProgramData\chocolatey\bin",
    "$env:USERPROFILE\.bun\bin",
    "$env:USERPROFILE\.cargo\bin",
    "$env:USERPROFILE\.local\bin",
    "C:\Users\runneradmin\AppData\Local\agy\bin",
    "C:\Users\runneradmin\.local\bin",
    "C:\tools\php84",
    "C:\tools\php83",
    "C:\tools\php82",
    "C:\ProgramData\ComposerSetup\bin"
)
Resolve-Path "C:\hostedtoolcache\windows\node\*\x64" 2>$null | ForEach-Object { $extraPaths += $_.Path }
Resolve-Path "C:\hostedtoolcache\windows\Python\*\x64" 2>$null | ForEach-Object { $extraPaths += $_.Path }
Resolve-Path "C:\hostedtoolcache\windows\Python\*\x64\Scripts" 2>$null | ForEach-Object { $extraPaths += $_.Path }

foreach ($ep in $extraPaths) {
    if ($ep -and (Test-Path $ep) -and (-not ($env:PATH -split ';' -contains $ep))) {
        $env:PATH = "$ep;$env:PATH"
    }
}

Write-Host "=================================================="
Write-Host "🧪 Running Rigorous Verification of Windows Studio"
Write-Host "=================================================="

$failedCount = 0

function Test-Tool {
    param(
        [string]$CommandName,
        [string]$Description,
        [string]$VersionArg = "--version"
    )

    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($cmd) {
        try {
            $ver = & $CommandName $VersionArg 2>&1 | Select-Object -First 1
            Write-Host "✅ $Description ($CommandName): $ver"
        } catch {
            Write-Host "✅ $Description ($CommandName): available"
        }
    } else {
        Write-Host "❌ FAILED: $Description ($CommandName) NOT found in PATH!" -ForegroundColor Red
        $script:failedCount++
    }
}

Write-Host "`n--- 1. Verifying Network & Remote Access Services ---"

# Test RDP Port 3389
$rdpPort = Test-NetConnection -ComputerName 127.0.0.1 -Port 3389 -WarningAction SilentlyContinue
if ($rdpPort.TcpTestSucceeded) {
    Write-Host "✅ Remote Desktop Server (RDP) listening on Port 3389."
} else {
    Write-Host "❌ FAILED: RDP is not listening on Port 3389!" -ForegroundColor Red
    $script:failedCount++
}

# Test OpenSSH Port 22
$sshPort = Test-NetConnection -ComputerName 127.0.0.1 -Port 22 -WarningAction SilentlyContinue
if ($sshPort.TcpTestSucceeded) {
    Write-Host "✅ OpenSSH Server listening on Port 22."
} else {
    Write-Host "❌ FAILED: OpenSSH Server is not listening on Port 22!" -ForegroundColor Red
    $script:failedCount++
}

# Test Tailscale
if (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe") {
    $tsIP = & "$env:ProgramFiles\Tailscale\tailscale.exe" ip -4 2>$null
    if ($tsIP) {
        Write-Host "✅ Tailscale private network IP: $tsIP"
    } else {
        Write-Host "⚠️ Tailscale executable present, IP resolving..."
    }
} else {
    Write-Host "❌ FAILED: Tailscale binary not found!" -ForegroundColor Red
    $script:failedCount++
}

Write-Host "`n--- 2. Verifying Core Runtime & CLI Toolchains ---"
Test-Tool "node" "Node.js LTS"
Test-Tool "npm" "Node Package Manager"
Test-Tool "pnpm" "pnpm Package Manager"
Test-Tool "yarn" "Yarn Package Manager"
Test-Tool "bun" "Bun JavaScript Runtime"
Test-Tool "python" "Python Runtime"
Test-Tool "uv" "Astral uv Tool"
Test-Tool "git" "Git Version Control"
Test-Tool "gh" "GitHub CLI"
Test-Tool "rclone" "Rclone Cloud Sync"

Write-Host "`n--- 3. Verifying Cloud Platform & Coding Agent CLIs ---"
Test-Tool "wrangler" "Cloudflare Wrangler CLI"
Test-Tool "vercel" "Vercel CLI"
Test-Tool "opencode" "OpenCode CLI"
Test-Tool "oc" "OpenCode Alias Wrapper"
Test-Tool "dsh" "DeepSeek Harness CLI"
Test-Tool "agy" "Google Antigravity CLI"

Write-Host "`n--- 4. Verifying Browser Testing Tools ---"
Test-Tool "playwright" "Playwright CLI"
Test-Tool "lighthouse" "Lighthouse CLI"

Write-Host "`n--- 5. Verifying Persistent Workspace Structure ---"
if (Test-Path $WorkspaceDir) {
    Write-Host "✅ Root workspace directory exists: $WorkspaceDir"
    $subdirs = @("projects", "frontend", "backend", "web", "apis", "deployments", "scripts", "downloads", "backups", "tmp")
    $allSubdirsPresent = $true
    foreach ($sd in $subdirs) {
        $p = Join-Path -Path $WorkspaceDir -ChildPath $sd
        if (-not (Test-Path $p)) {
            Write-Host "❌ FAILED: Missing subfolder $sd" -ForegroundColor Red
            $allSubdirsPresent = $false
            $script:failedCount++
        }
    }
    if ($allSubdirsPresent) {
        Write-Host "✅ All 10 workspace subdirectories are present."
    }
} else {
    Write-Host "❌ FAILED: Workspace directory $WorkspaceDir does not exist!" -ForegroundColor Red
    $script:failedCount++
}

Write-Host "`n=================================================="
if ($script:failedCount -eq 0) {
    Write-Host "🎉 ALL VERIFICATION CHECKS PASSED (0 Failures)" -ForegroundColor Green
} else {
    Write-Host "❌ VERIFICATION COMPLETED WITH $($script:failedCount) FAILURE(S)" -ForegroundColor Red
    Write-Error "Verification failed with $($script:failedCount) missing component(s)."
    exit 1
}
Write-Host "=================================================="
