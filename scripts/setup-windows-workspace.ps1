<#
.SYNOPSIS
    setup-windows-workspace.ps1: Configure Windows Workspace, Rclone & Google Drive Persistence
.DESCRIPTION
    Creates directory hierarchy under C:\Users\runneradmin\workspace, links it to C:\Users\RDP\workspace,
    configures rclone, and restores persistent state from Google Drive.
#>

[CmdletBinding()]
param(
    [string]$WorkspaceDir = "C:\Users\runneradmin\workspace",
    [string]$RemoteSubdir = "cloud-dev/windows-workspace",
    [switch]$ForceClean = $false
)

$ErrorActionPreference = "Continue"

Write-Host "=================================================="
Write-Host "📁 Configuring Windows Cloud Development Workspace"
Write-Host "=================================================="

# 1. Create Workspace Subdirectories
$subdirs = @(
    "projects",
    "frontend",
    "backend",
    "web",
    "apis",
    "deployments",
    "scripts",
    "downloads",
    "backups",
    "tmp"
)

foreach ($subdir in $subdirs) {
    $targetPath = Join-Path -Path $WorkspaceDir -ChildPath $subdir
    if (-not (Test-Path $targetPath)) {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
        Write-Host "Created: $targetPath"
    }
}

# 2. Junction to C:\Users\RDP\workspace so RDP user shares the exact same workspace
$rdpHome = "C:\Users\RDP"
if (Test-Path $rdpHome) {
    $rdpWorkspace = Join-Path -Path $rdpHome -ChildPath "workspace"
    if (-not (Test-Path $rdpWorkspace)) {
        try {
            New-Item -ItemType Junction -Path $rdpWorkspace -Target $WorkspaceDir -Force | Out-Null
            Write-Host "✅ Created Junction: $rdpWorkspace -> $WorkspaceDir"
        } catch {
            Write-Warning "Could not create junction: $_"
        }
    }
}

# 3. Create Welcome Guide if workspace is fresh
$welcomeFile = Join-Path -Path $WorkspaceDir -ChildPath "WELCOME.md"
if (-not (Test-Path $welcomeFile)) {
    $welcomeContent = @"
# 🪟 Windows Cloud Web Development Studio

Welcome to your persistent Windows cloud development environment!

## 📁 Workspace Hierarchy
- **projects/**: All Git repositories and full-stack projects
- **frontend/**: React, Next.js, Vite, Vue, Angular, Astro applications
- **backend/**: Node.js, Express, FastAPI, Django, Flask, PHP services
- **web/**: Static sites and web apps
- **apis/**: REST, GraphQL, and microservice definitions
- **deployments/**: Cloudflare Workers, Vercel, Docker configurations
- **scripts/**: Custom automation scripts and utilities
- **downloads/**: Development packages and downloaded assets
- **backups/**: Local backup snapshots and recovery metadata
- **tmp/**: Transient workspace temporary files

## ⚡ Developer Aliases (PowerShell)
- \`ws\`: Switch directly to \`$WorkspaceDir\`
- \`projects\`: Switch directly to \`$WorkspaceDir\projects\`
- \`web\`: Switch directly to \`$WorkspaceDir\web\`
- \`oc\`: OpenCode CLI
- \`agy\`: Antigravity CLI
- \`dsh\`: DeepSeek Harness CLI
- \`wrangler\`: Cloudflare Workers & Pages CLI
- \`vercel\`: Vercel Deployment CLI

## 🔄 Persistence
Your workspace is automatically synchronized to Google Drive every 5 minutes.
Remote: \`gdrive:$RemoteSubdir\`
"@
    Set-Content -Path $welcomeFile -Value $welcomeContent -Encoding UTF8
}

# 4. Configure PowerShell Profile for runneradmin and RDP users
$profileSnippet = @"

# ==============================================================================
# Windows Cloud Development Studio Aliases & Helpers
# ==============================================================================
function ws { Set-Location "$WorkspaceDir" }
function projects { Set-Location "$WorkspaceDir\projects" }
function web { Set-Location "$WorkspaceDir\web" }
Set-Alias -Name ll -Value Get-ChildItem -Option AllScope -ErrorAction SilentlyContinue

# Ensure tool paths in environment
`$env:WORKSPACE = "$WorkspaceDir"
`$env:DSH_HOME = "$WorkspaceDir\.dsh"
`$env:DSH_AGENTS_HOME = "$WorkspaceDir\.agents"
"@

$profilePaths = @(
    "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
    "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1",
    "C:\Users\runneradmin\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
    "C:\Users\RDP\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
)

foreach ($pPath in $profilePaths) {
    try {
        $parentDir = Split-Path -Path $pPath -Parent
        if (-not (Test-Path $parentDir)) {
            New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
        }
        if (-not (Test-Path $pPath)) {
            Set-Content -Path $pPath -Value $profileSnippet -Encoding UTF8
        } elseif (-not ((Get-Content $pPath -Raw) -like "*Windows Cloud Development Studio*")) {
            Add-Content -Path $pPath -Value "`n$profileSnippet" -Encoding UTF8
        }
    } catch {
        # Silently continue if user home does not exist yet
    }
}

# 5. Configure Rclone from RCLONE_CONFIG_B64
$rcloneConfContent = $null
if ($env:RCLONE_CONFIG_B64) {
    try {
        $bytes = [System.Convert]::FromBase64String($env:RCLONE_CONFIG_B64)
        $rcloneConfContent = [System.Text.Encoding]::UTF8.GetString($bytes)
        Write-Host "✅ Decoded rclone configuration from RCLONE_CONFIG_B64"
    } catch {
        Write-Warning "Failed to decode RCLONE_CONFIG_B64: $_"
    }
}

if ($rcloneConfContent) {
    $rcloneDestinations = @(
        "$env:USERPROFILE\.config\rclone\rclone.conf",
        "$env:APPDATA\rclone\rclone.conf",
        "C:\Users\runneradmin\.config\rclone\rclone.conf",
        "C:\Users\runneradmin\AppData\Roaming\rclone\rclone.conf",
        "C:\Users\RDP\.config\rclone\rclone.conf",
        "C:\Users\RDP\AppData\Roaming\rclone\rclone.conf"
    )

    foreach ($dest in $rcloneDestinations) {
        try {
            $destDir = Split-Path -Path $dest -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Set-Content -Path $dest -Value $rcloneConfContent -Encoding UTF8
        } catch {
            # User directory might not exist yet
        }
    }

    # 6. Restore Workspace from Google Drive
    Write-Host "`n📥 Restoring persistent workspace from Google Drive (gdrive:$RemoteSubdir)..."
    if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
        Write-Host "Installing rclone for workspace restoration..."
        try {
            choco install rclone -y --no-progress
            $env:PATH = "C:\ProgramData\chocolatey\bin;$env:PATH"
        } catch {
            Write-Warning "Could not install rclone via Chocolatey: $_"
        }
    }
    if (Get-Command rclone -ErrorAction SilentlyContinue) {
        try {
            # Test connectivity to remote
            $remotes = & rclone listremotes 2>$null
            if ($remotes -contains "gdrive:") {
                Write-Host "Testing Google Drive remote connection..."
                $test = & rclone lsd "gdrive:" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✅ Google Drive connection successful."
                    
                    # Create filter file for safe sync without BOM
                    $filterFile = "$env:TEMP\rclone-windows-filters.txt"
                    $filters = @"
- node_modules/**
- .next/**
- dist/**
- build/**
- .cache/**
- __pycache__/**
- *.pyc
- .venv/**
- venv/**
- *.tmp
- *.log
- .git/objects/**
- AppData/Local/Temp/**
+ *
"@
                    [System.IO.File]::WriteAllText($filterFile, $filters)

                    Write-Host "Restoring files to $WorkspaceDir..."
                    & rclone copy "gdrive:$RemoteSubdir" $WorkspaceDir `
                        --filter-from $filterFile `
                        --transfers 8 `
                        --checkers 16 `
                        --fast-list `
                        --stats 5s `
                        --stats-one-line

                    Write-Host "✅ Workspace restoration completed."

                    # Restore safe user configuration files if present
                    $safeConfigRemote = "gdrive:$RemoteSubdir/.config/safe-configs"
                    $safeConfigLocal = "$env:TEMP\safe-configs"
                    & rclone copy $safeConfigRemote $safeConfigLocal 2>$null
                    if (Test-Path $safeConfigLocal) {
                        Write-Host "Restoring user configurations..."
                        if (Test-Path "$safeConfigLocal\.gitconfig") {
                            Copy-Item "$safeConfigLocal\.gitconfig" "$env:USERPROFILE\.gitconfig" -Force
                            Copy-Item "$safeConfigLocal\.gitconfig" "C:\Users\RDP\.gitconfig" -Force -ErrorAction SilentlyContinue
                        }
                        if (Test-Path "$safeConfigLocal\.ssh") {
                            Copy-Item "$safeConfigLocal\.ssh\*" "$env:USERPROFILE\.ssh\" -Recurse -Force -ErrorAction SilentlyContinue
                            Copy-Item "$safeConfigLocal\.ssh\*" "C:\Users\RDP\.ssh\" -Recurse -Force -ErrorAction SilentlyContinue
                        }
                    }
                } else {
                    Write-Warning "Google Drive remote test failed. Fresh workspace initialized."
                }
            } else {
                Write-Warning "'gdrive:' remote not configured in rclone.conf. Fresh workspace initialized."
            }
        } catch {
            Write-Warning "Error during rclone restore: $_"
        }
    } else {
        Write-Warning "rclone command not found. Skipping restore."
    }
} else {
    Write-Host "RCLONE_CONFIG_B64 secret not provided. Initializing clean local workspace."
}

Write-Host "=================================================="
Write-Host "✅ Workspace Ready: $WorkspaceDir"
Write-Host "=================================================="
$global:LASTEXITCODE = 0
exit 0
