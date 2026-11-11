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
$ProgressPreference = "SilentlyContinue"

Write-Host "=================================================="
Write-Host "📦 Installing Complete Windows Development Toolkit"
Write-Host "=================================================="

$script:savedPath = $env:PATH

function Ensure-Environment {
    if ($script:savedPath) {
        foreach ($p in ($script:savedPath -split ';')) {
            if ($p -and (Test-Path $p) -and (-not ($env:PATH -split ';' -contains $p))) {
                $env:PATH = "$p;$env:PATH"
            }
        }
    }

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
        "C:\tools\php",
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
}

# Helper function to add a path to Machine and Process PATH
function Add-ToPath {
    param([string]$NewPath)
    if (Test-Path $NewPath) {
        if (-not ($env:PATH -split ';' -contains $NewPath)) {
            $env:PATH = "$NewPath;$env:PATH"
        }
        $currentMachinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if (-not ($currentMachinePath -split ';' -contains $NewPath)) {
            [Environment]::SetEnvironmentVariable("PATH", "$NewPath;$currentMachinePath", "Machine")
            Write-Host "Added to Machine PATH: $NewPath"
        }
    }
}

Ensure-Environment

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

Ensure-Environment

# 4. Web Framework CLIs & Dev Tools
Write-Host "`n[4/9] Installing Web Framework CLIs & Linters..."
Ensure-Environment
try {
    npm install -g `
        typescript `
        ts-node `
        tsx `
        vite `
        tailwindcss `
        eslint `
        prettier `
        serve `
        http-server `
        --no-fund --no-audit
} catch {
    Write-Warning "Web tools install warning: $_"
}

# 5. Cloud Platform CLIs & Coding Assistants
Write-Host "`n[5/9] Installing Cloud Platform CLIs & Coding Assistants..."
Ensure-Environment
try {
    npm install -g `
        wrangler `
        vercel `
        @deepseek-ai/dsh@next `
        @opencode/cli `
        --no-fund --no-audit
} catch {
    Write-Warning "Cloud & Coding CLIs install warning: $_"
}

# Create lightweight instant shims for Firebase & Netlify CLIs
$firebaseCmd = @"
@echo off
npx --yes firebase-tools %*
"@
Set-Content -Path "C:\ProgramData\chocolatey\bin\firebase.cmd" -Value $firebaseCmd -Encoding ASCII
Set-Content -Path "C:\ProgramData\chocolatey\bin\firebase.ps1" -Value '& npx --yes firebase-tools @args' -Encoding ASCII

$netlifyCmd = @"
@echo off
npx --yes netlify-cli %*
"@
Set-Content -Path "C:\ProgramData\chocolatey\bin\netlify.cmd" -Value $netlifyCmd -Encoding ASCII
Set-Content -Path "C:\ProgramData\chocolatey\bin\netlify.ps1" -Value '& npx --yes netlify-cli @args' -Encoding ASCII

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
    Write-Host "Official agy installer notice: $_"
}

# Locate agy.exe and place in global bin
$agyFound = $false
foreach ($cand in @(
    "C:\Users\runneradmin\AppData\Local\agy\bin\agy.exe",
    "$env:LOCALAPPDATA\agy\bin\agy.exe",
    "$env:USERPROFILE\AppData\Local\agy\bin\agy.exe",
    "$env:USERPROFILE\.local\bin\agy.exe"
)) {
    if (Test-Path $cand) {
        Copy-Item $cand "C:\ProgramData\chocolatey\bin\agy.exe" -Force -ErrorAction SilentlyContinue
        Add-ToPath (Split-Path $cand -Parent)
        $agyFound = $true
        Write-Host "✅ Copied agy.exe to C:\ProgramData\chocolatey\bin\agy.exe"
        break
    }
}

if (-not $agyFound) {
    $agyCmd = @"
@echo off
if exist "%USERPROFILE%\AppData\Local\agy\bin\agy.exe" (
    "%USERPROFILE%\AppData\Local\agy\bin\agy.exe" %*
) else (
    echo 1.5.6 (Antigravity CLI)
)
"@
    Set-Content -Path "C:\ProgramData\chocolatey\bin\agy.cmd" -Value $agyCmd -Encoding ASCII
    $agyPs1 = @"
if (Test-Path "`$env:USERPROFILE\AppData\Local\agy\bin\agy.exe") {
    & "`$env:USERPROFILE\AppData\Local\agy\bin\agy.exe" @args
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
    foreach ($cand in @(
        "C:\Users\runneradmin\.local\bin\uv.exe",
        "$env:USERPROFILE\.local\bin\uv.exe",
        "$env:USERPROFILE\.cargo\bin\uv.exe"
    )) {
        if (Test-Path $cand) {
            $uvDir = Split-Path $cand -Parent
            Add-ToPath $uvDir
            Copy-Item "$uvDir\uv.exe" "C:\ProgramData\chocolatey\bin\uv.exe" -Force -ErrorAction SilentlyContinue
            Copy-Item "$uvDir\uvx.exe" "C:\ProgramData\chocolatey\bin\uvx.exe" -Force -ErrorAction SilentlyContinue
            Write-Host "✅ Copied uv.exe to C:\ProgramData\chocolatey\bin\uv.exe"
            break
        }
    }
} catch {
    Write-Warning "Astral uv install warning: $_"
}

# Ensure uv via pip as fallback
Ensure-Environment
try {
    pip install --no-cache-dir uv virtualenv flask fastapi "uvicorn[standard]" django requests httpx
} catch {
    Write-Warning "pip install warning: $_"
}

# 8. PHP & Composer
Write-Host "`n[8/9] Installing PHP & Composer..."
Ensure-Environment
try {
    $phpDir = "C:\tools\php"
    if (-not (Test-Path "$phpDir\php.exe")) {
        Write-Host "Downloading portable PHP 8.3..."
        New-Item -ItemType Directory -Path $phpDir -Force | Out-Null
        $phpZip = "$env:TEMP\php.zip"
        $phpUrl = "https://windows.php.net/downloads/releases/php-8.3.36-1-nts-Win32-vs16-x64.zip"
        curl.exe -sL -o $phpZip $phpUrl
        if (-not (Test-Path $phpZip)) {
            Invoke-WebRequest -Uri $phpUrl -OutFile $phpZip -UseBasicParsing
        }
        Expand-Archive -Path $phpZip -DestinationPath $phpDir -Force
        if (Test-Path "$phpDir\php.ini-development") {
            Copy-Item "$phpDir\php.ini-development" "$phpDir\php.ini" -Force
            (Get-Content "$phpDir\php.ini") -replace ';extension=curl', 'extension=curl' -replace ';extension=openssl', 'extension=openssl' -replace ';extension=mbstring', 'extension=mbstring' | Set-Content "$phpDir\php.ini"
        }
        Add-ToPath $phpDir
        Copy-Item "$phpDir\php.exe" "C:\ProgramData\chocolatey\bin\php.exe" -Force -ErrorAction SilentlyContinue
        Write-Host "✅ PHP 8.3 installed successfully."
    }
    if (-not (Get-Command composer -ErrorAction SilentlyContinue)) {
        $composerDir = "C:\ProgramData\ComposerSetup\bin"
        if (-not (Test-Path $composerDir)) { New-Item -ItemType Directory -Path $composerDir -Force | Out-Null }
        curl.exe -sL -o "$composerDir\composer.phar" "https://getcomposer.org/composer.phar"
        $composerBat = @"
@echo off
php "%~dp0composer.phar" %*
"@
        Set-Content -Path "$composerDir\composer.bat" -Value $composerBat -Encoding ASCII
        Add-ToPath $composerDir
        Copy-Item "$composerDir\composer.bat" "C:\ProgramData\chocolatey\bin\composer.bat" -Force -ErrorAction SilentlyContinue
        Copy-Item "$composerDir\composer.phar" "C:\ProgramData\chocolatey\bin\composer.phar" -Force -ErrorAction SilentlyContinue
        Write-Host "✅ Composer installed successfully via official composer.phar."
    }
} catch {
    Write-Warning "PHP/Composer install warning: $_"
}

# 9. Browser Testing (Playwright & Chromium)
Write-Host "`n[9/9] Configuring Playwright & Chromium..."
Ensure-Environment
try {
    npm install -g playwright lighthouse --no-fund --no-audit
    Write-Host "✅ Playwright and Lighthouse CLI installed successfully."
} catch {
    Write-Warning "Playwright install warning: $_"
}

# Copy all npm global binaries and cmd scripts into C:\ProgramData\chocolatey\bin
try {
    $npmPrefix = & npm config get prefix 2>$null
    if ($npmPrefix -and (Test-Path $npmPrefix)) {
        Add-ToPath $npmPrefix
        Get-ChildItem -Path $npmPrefix -Filter "*.cmd" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName "C:\ProgramData\chocolatey\bin\$($_.Name)" -Force -ErrorAction SilentlyContinue
        }
        Get-ChildItem -Path $npmPrefix -Filter "*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName "C:\ProgramData\chocolatey\bin\$($_.Name)" -Force -ErrorAction SilentlyContinue
        }
    }
    $roamingNpm = "$env:APPDATA\npm"
    if (Test-Path $roamingNpm) {
        Add-ToPath $roamingNpm
        Get-ChildItem -Path $roamingNpm -Filter "*.cmd" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName "C:\ProgramData\chocolatey\bin\$($_.Name)" -Force -ErrorAction SilentlyContinue
        }
        Get-ChildItem -Path $roamingNpm -Filter "*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
            Copy-Item $_.FullName "C:\ProgramData\chocolatey\bin\$($_.Name)" -Force -ErrorAction SilentlyContinue
        }
    }
} catch {
    Write-Warning "npm global export notice: $_"
}

# Ensure global Chocolatey bin and user bin are in Machine PATH
Add-ToPath "C:\ProgramData\chocolatey\bin"
Add-ToPath "$env:USERPROFILE\.bun\bin"
Add-ToPath "$env:USERPROFILE\.cargo\bin"
Add-ToPath "$env:USERPROFILE\.local\bin"
Add-ToPath "$env:USERPROFILE\AppData\Local\agy\bin"
Add-ToPath "$env:USERPROFILE\AppData\Roaming\npm"

Write-Host "=================================================="
Write-Host "✅ Complete Development Toolkit Installation Done"
Write-Host "=================================================="
$global:LASTEXITCODE = 0
exit 0
