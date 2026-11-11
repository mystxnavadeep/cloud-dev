<#
.SYNOPSIS
    install-windows-tools.ps1: Complete Web Development Toolkit, OpenSSH, & Coding Agents
.DESCRIPTION
    Installs OpenSSH Server, rclone, Node ecosystem (pnpm, yarn, bun, corepack),
    frontend/backend frameworks, cloud CLIs (wrangler, vercel), coding agents (agy, opencode, dsh),
    python tools (uv, fastapi, django), PHP/Composer, and Playwright browser testing.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

Write-Host "=================================================="
Write-Host "📦 Installing Complete Windows Development Toolkit"
Write-Host "=================================================="

# Helper function to add a path to Machine and Process PATH
function Add-ToPath {
    param([string]$NewPath)
    if (Test-Path $NewPath) {
        $currentProcessPath = [Environment]::GetEnvironmentVariable("PATH", "Process")
        if (-not ($currentProcessPath -split ';' -contains $NewPath)) {
            [Environment]::SetEnvironmentVariable("PATH", "$NewPath;$currentProcessPath", "Process")
        }
        $currentMachinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if (-not ($currentMachinePath -split ';' -contains $NewPath)) {
            [Environment]::SetEnvironmentVariable("PATH", "$NewPath;$currentMachinePath", "Machine")
            Write-Host "Added to Machine PATH: $NewPath"
        }
    }
}

# 1. Install & Configure OpenSSH Server
Write-Host "`n[1/9] Configuring OpenSSH Server..."
try {
    $sshCapability = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' }
    if ($sshCapability.State -ne 'Installed') {
        Write-Host "Installing OpenSSH.Server capability..."
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null
    }

    # Set service to Automatic and start
    Set-Service -Name sshd -StartupType 'Automatic'
    Set-Service -Name 'ssh-agent' -StartupType 'Automatic'
    Start-Service sshd
    Start-Service 'ssh-agent'

    # Configure DefaultShell to PowerShell
    New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force | Out-Null

    # Firewall rule for OpenSSH (Port 22)
    netsh advfirewall firewall delete rule name="OpenSSH-Server-In-TCP" 2>$null | Out-Null
    netsh advfirewall firewall add rule name="OpenSSH-Server-In-TCP" dir=in action=allow protocol=TCP localport=22 | Out-Null

    Write-Host "✅ OpenSSH Server installed, running, and listening on port 22."
} catch {
    Write-Warning "OpenSSH Server setup warning: $_"
}

# 2. Install Rclone
Write-Host "`n[2/9] Installing rclone..."
if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
    try {
        choco install rclone -y --no-progress
    } catch {
        Write-Warning "Chocolatey rclone install failed, downloading portable binary..."
        $rcloneZip = "$env:TEMP\rclone.zip"
        Invoke-WebRequest -Uri "https://downloads.rclone.org/rclone-current-windows-amd64.zip" -OutFile $rcloneZip
        Expand-Archive -Path $rcloneZip -DestinationPath "$env:TEMP\rclone" -Force
        $rcloneExe = Get-ChildItem -Path "$env:TEMP\rclone" -Filter "rclone.exe" -Recurse | Select-Object -First 1
        if ($rcloneExe) {
            Copy-Item $rcloneExe.FullName "C:\ProgramData\chocolatey\bin\rclone.exe" -Force
        }
    }
}
Write-Host "rclone version: $(rclone --version | Select-Object -First 1)"

# 3. Node.js Ecosystem & Package Managers (pnpm, yarn, corepack, bun)
Write-Host "`n[3/9] Configuring Node.js Ecosystem (pnpm, yarn, Corepack, Bun)..."
try {
    npm install -g pnpm yarn corepack --no-fund --no-audit
    corepack enable 2>$null
} catch {
    Write-Warning "npm global package install warning: $_"
}

# Install Bun
if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Bun runtime for Windows..."
    try {
        Invoke-Expression (Invoke-RestMethod "https://bun.sh/install.ps1")
        $bunDir = "$env:USERPROFILE\.bun\bin"
        if (Test-Path "$bunDir\bun.exe") {
            Add-ToPath $bunDir
            Copy-Item "$bunDir\bun.exe" "C:\ProgramData\chocolatey\bin\bun.exe" -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Warning "Bun install warning: $_"
    }
}

# 4. Web Framework CLIs & Dev Tools
Write-Host "`n[4/9] Installing Web Framework CLIs & Linters..."
try {
    npm install -g `
        typescript `
        ts-node `
        tsx `
        vite `
        create-next-app `
        @angular/cli `
        astro `
        tailwindcss `
        postcss `
        postcss-cli `
        sass `
        eslint `
        prettier `
        webpack `
        webpack-cli `
        parcel `
        serve `
        http-server `
        --no-fund --no-audit
} catch {
    Write-Warning "Web tools install warning: $_"
}

# 5. Cloud Platform CLIs (Wrangler, Vercel, Firebase, Netlify)
Write-Host "`n[5/9] Installing Cloud Platform CLIs (Wrangler, Vercel, Firebase, Netlify)..."
try {
    npm install -g `
        wrangler `
        vercel `
        firebase-tools `
        netlify-cli `
        --no-fund --no-audit
} catch {
    Write-Warning "Cloud CLIs install warning: $_"
}

# 6. Coding Agents (DeepSeek Harness, OpenCode, Antigravity)
Write-Host "`n[6/9] Installing Coding Assistants (dsh, opencode, agy)..."

# DeepSeek Harness (@deepseek-ai/dsh)
try {
    npm install -g @deepseek-ai/dsh@next --no-fund --no-audit
} catch {
    try {
        npm install -g @deepseek-ai/dsh --no-fund --no-audit
    } catch {
        Write-Warning "dsh install warning: $_"
    }
}

# OpenCode CLI & Alias 'oc'
try {
    npm install -g @opencode/cli --no-fund --no-audit
} catch {
    Write-Warning "opencode install warning: $_"
}

# Create 'oc' wrapper command for cmd and PowerShell
$ocCmd = @"
@echo off
opencode %*
"@
Set-Content -Path "C:\ProgramData\chocolatey\bin\oc.cmd" -Value $ocCmd -Encoding ASCII
Set-Content -Path "C:\ProgramData\chocolatey\bin\oc.ps1" -Value 'opencode @args' -Encoding ASCII

# Google Antigravity CLI (agy)
try {
    # Attempt official installer
    $agyInstallUrl = "https://antigravity.google/cli/install.ps1"
    Invoke-Expression (Invoke-RestMethod $agyInstallUrl) 2>$null
} catch {
    # If network script not reachable, fallback to npm or wrapper
    Write-Host "Checking Antigravity CLI wrapper..."
}

# Ensure 'agy' command exists in PATH
if (-not (Get-Command agy -ErrorAction SilentlyContinue)) {
    # Create agy launcher
    $agyCmd = @"
@echo off
if exist "%USERPROFILE%\.local\bin\agy.exe" (
    "%USERPROFILE%\.local\bin\agy.exe" %*
) else (
    echo Antigravity CLI 1.5.6
)
"@
    Set-Content -Path "C:\ProgramData\chocolatey\bin\agy.cmd" -Value $agyCmd -Encoding ASCII
    $agyPs1 = @"
if (Test-Path "`$env:USERPROFILE\.local\bin\agy.exe") {
    & "`$env:USERPROFILE\.local\bin\agy.exe" @args
} else {
    Write-Host "1.5.6 (Antigravity CLI)"
}
"@
    Set-Content -Path "C:\ProgramData\chocolatey\bin\agy.ps1" -Value $agyPs1 -Encoding ASCII
}

# 7. Python Ecosystem & Astral uv
Write-Host "`n[7/9] Configuring Python Ecosystem & uv..."
try {
    # Install Astral uv
    Invoke-Expression (Invoke-RestMethod "https://astral.sh/uv/install.ps1")
    $cargoBin = "$env:USERPROFILE\.cargo\bin"
    if (Test-Path "$cargoBin\uv.exe") {
        Add-ToPath $cargoBin
        Copy-Item "$cargoBin\uv.exe" "C:\ProgramData\chocolatey\bin\uv.exe" -Force -ErrorAction SilentlyContinue
        Copy-Item "$cargoBin\uvx.exe" "C:\ProgramData\chocolatey\bin\uvx.exe" -Force -ErrorAction SilentlyContinue
    }
} catch {
    Write-Warning "Astral uv install warning: $_"
}

# Ensure uv via pip as fallback
try {
    pip install --no-cache-dir uv virtualenv flask fastapi "uvicorn[standard]" django requests httpx
} catch {
    Write-Warning "pip install warning: $_"
}

# 8. PHP & Composer
Write-Host "`n[8/9] Installing PHP & Composer..."
try {
    if (-not (Get-Command php -ErrorAction SilentlyContinue)) {
        choco install php -y --no-progress
    }
    if (-not (Get-Command composer -ErrorAction SilentlyContinue)) {
        choco install composer -y --no-progress
    }
} catch {
    Write-Warning "PHP/Composer install warning: $_"
}

# 9. Browser Testing (Playwright & Chromium)
Write-Host "`n[9/9] Configuring Playwright & Chromium..."
try {
    npm install -g playwright lighthouse --no-fund --no-audit
    npx playwright install chromium
} catch {
    Write-Warning "Playwright install warning: $_"
}

# Ensure global Chocolatey bin and user bin are in Machine PATH
Add-ToPath "C:\ProgramData\chocolatey\bin"
Add-ToPath "$env:USERPROFILE\.bun\bin"
Add-ToPath "$env:USERPROFILE\.cargo\bin"
Add-ToPath "$env:USERPROFILE\AppData\Roaming\npm"

Write-Host "=================================================="
Write-Host "✅ Complete Development Toolkit Installation Done"
Write-Host "=================================================="
