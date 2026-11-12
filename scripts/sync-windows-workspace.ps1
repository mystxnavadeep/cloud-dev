<#
.SYNOPSIS
    sync-windows-workspace.ps1: Background & Final Workspace Synchronization to Google Drive
.DESCRIPTION
    Safely synchronizes C:\Users\runneradmin\workspace to gdrive:cloud-dev/windows-workspace.
    Prevents overlapping sync operations, handles graceful daemon shutdown, saves recovery state,
    and performs safe final backup with backup-dir archive.
#>

[CmdletBinding()]
param(
    [string]$WorkspaceDir = "C:\Users\runneradmin\workspace",
    [string]$RemoteSubdir = "cloud-dev/windows-workspace",
    [switch]$Final = $false,
    [switch]$Daemon = $false,
    [switch]$StopDaemon = $false,
    [switch]$SaveRecoveryState = $false
)

$ErrorActionPreference = "Continue"

$LockFile = "$env:TEMP\windows-workspace-sync.lock"
$PidFile = "$env:TEMP\windows-sync-daemon.pid"

function Stop-SyncDaemon {
    Write-Host "Checking for active background synchronization daemon..."
    if (Test-Path $PidFile) {
        try {
            $daemonPid = (Get-Content -Path $PidFile -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
            if ($daemonPid -and ($daemonPid -match '^\d+$')) {
                $proc = Get-Process -Id ([int]$daemonPid) -ErrorAction SilentlyContinue
                if ($proc) {
                    Write-Host "Stopping sync daemon (PID: $daemonPid)..."
                    Stop-Process -Id ([int]$daemonPid) -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                }
            }
        } catch {
            Write-Warning "Daemon stop notice: $_"
        } finally {
            Remove-Item -Path $PidFile -Force -ErrorAction SilentlyContinue
        }
    }

    # Wait for any in-flight sync lock to clear (up to 60 seconds)
    $waited = 0
    while ((Test-Path $LockFile) -and ($waited -lt 60)) {
        Write-Host "Waiting for in-flight sync operation to complete ($waited s)..."
        Start-Sleep -Seconds 2
        $waited += 2
    }
    if (Test-Path $LockFile) {
        Write-Warning "Lock file remained after 60s. Forcing lock release for final operations."
        Remove-Item -Path $LockFile -Force -ErrorAction SilentlyContinue
    }
    Write-Host "✅ Sync daemon stopped and lock cleared."
}

function Save-SessionRecoveryState {
    Write-Host "Saving session recovery state and metadata..."
    $backupDir = Join-Path -Path $WorkspaceDir -ChildPath "backups"
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    }

    $timestamp = (Get-Date -Format "o")
    $tools = @{}
    foreach ($cmdName in @("node", "npm", "pnpm", "yarn", "bun", "python", "uv", "php", "composer", "git", "gh", "wrangler", "vercel", "opencode", "dsh", "agy", "playwright", "lighthouse")) {
        $found = Get-Command $cmdName -ErrorAction SilentlyContinue
        if ($found) {
            $ver = & $cmdName --version 2>&1 | Select-Object -First 1
            $tools[$cmdName] = "$ver"
        } else {
            $tools[$cmdName] = "not installed"
        }
    }

    $subdirsStats = @{}
    if (Test-Path $WorkspaceDir) {
        Get-ChildItem -Path $WorkspaceDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $fCount = (Get-ChildItem -Path $_.FullName -File -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
            $subdirsStats[$_.Name] = $fCount
        }
    }

    $recoveryData = @{
        timestamp = $timestamp
        os = "windows"
        runner_user = $env:USERNAME
        tailscale_ip = $env:TAILSCALE_IP
        tailscale_hostname = $env:TAILSCALE_HOSTNAME
        workspace_dir = $WorkspaceDir
        remote_target = "gdrive:$RemoteSubdir"
        installed_tools = $tools
        workspace_subdirs = $subdirsStats
    }

    $recoveryJsonPath = Join-Path -Path $backupDir -ChildPath "recovery-state.json"
    $manifestJsonPath = Join-Path -Path $backupDir -ChildPath "backup-manifest.json"

    $recoveryData | ConvertTo-Json -Depth 5 | Set-Content -Path $recoveryJsonPath -Encoding UTF8
    $recoveryData | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestJsonPath -Encoding UTF8

    Write-Host "✅ Session recovery state saved to $recoveryJsonPath"
}

function Invoke-WorkspaceSync {
    param([bool]$IsFinal = $false)

    # Check lock file
    if (Test-Path $LockFile) {
        $lockAge = (Get-Date) - (Get-Item $LockFile).LastWriteTime
        if ($lockAge.TotalMinutes -lt 10) {
            Write-Host "[$(Get-Date -Format 'u')] Another sync process is running. Skipping."
            return
        } else {
            Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
        }
    }

    # Set lock
    Set-Content -Path $LockFile -Value $PID -Encoding ASCII

    try {
        if (-not (Get-Command rclone -ErrorAction SilentlyContinue)) {
            Write-Warning "rclone not found. Cannot synchronize workspace."
            return
        }

        if (-not (Test-Path $WorkspaceDir)) {
            Write-Warning "Workspace directory does not exist: $WorkspaceDir"
            return
        }

        # Create filter file without UTF-8 BOM
        $filterFile = "$env:TEMP\rclone-windows-sync-filters.txt"
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
- *.env
- *.env.*
- *.key
- *.pem
- id_rsa*
- id_ed25519*
- rclone.conf
+ *
"@
        [System.IO.File]::WriteAllText($filterFile, $filters)

        $timestamp = (Get-Date -Format "yyyyMMdd-HHmmss")
        $backupDirArg = @()
        if ($IsFinal) {
            $backupDirArg = @("--backup-dir", "gdrive:$RemoteSubdir-archive/$timestamp")
        }

        Write-Host "[$(Get-Date -Format 'u')] Synchronizing workspace to gdrive:$RemoteSubdir..."
        & rclone sync $WorkspaceDir "gdrive:$RemoteSubdir" `
            --filter-from $filterFile `
            --transfers 8 `
            --checkers 16 `
            --fast-list `
            @backupDirArg `
            --stats 5s `
            --stats-one-line 2>&1

        # Synchronize safe user configurations
        $safeConfigLocal = "$env:TEMP\safe-configs"
        New-Item -ItemType Directory -Path $safeConfigLocal -Force | Out-Null
        if (Test-Path "$env:USERPROFILE\.gitconfig") {
            Copy-Item "$env:USERPROFILE\.gitconfig" $safeConfigLocal -Force
        }
        if (Test-Path "$env:USERPROFILE\.ssh\config") {
            New-Item -ItemType Directory -Path "$safeConfigLocal\.ssh" -Force | Out-Null
            Copy-Item "$env:USERPROFILE\.ssh\config" "$safeConfigLocal\.ssh\" -Force
        }
        if (Test-Path "$env:USERPROFILE\.ssh\known_hosts") {
            New-Item -ItemType Directory -Path "$safeConfigLocal\.ssh" -Force | Out-Null
            Copy-Item "$env:USERPROFILE\.ssh\known_hosts" "$safeConfigLocal\.ssh\" -Force
        }

        & rclone sync $safeConfigLocal "gdrive:$RemoteSubdir/.config/safe-configs" 2>$null

        Write-Host "[$(Get-Date -Format 'u')] ✅ Workspace synchronization completed."
    } catch {
        Write-Warning "Workspace sync encountered an error: $_"
    } finally {
        Remove-Item $LockFile -Force -ErrorAction SilentlyContinue
    }
}

if ($StopDaemon) {
    Stop-SyncDaemon
    $global:LASTEXITCODE = 0
    exit 0
}

if ($SaveRecoveryState) {
    Save-SessionRecoveryState
    $global:LASTEXITCODE = 0
    exit 0
}

if ($Daemon) {
    Write-Host "Starting continuous 5-minute workspace synchronization daemon (PID: $PID)..."
    Set-Content -Path $PidFile -Value $PID -Encoding ASCII
    while ($true) {
        Start-Sleep -Seconds 300
        Invoke-WorkspaceSync -IsFinal $false
    }
} elseif ($Final) {
    Write-Host "=================================================="
    Write-Host "💾 Performing Final Workspace Backup to Google Drive"
    Write-Host "=================================================="
    Stop-SyncDaemon
    Save-SessionRecoveryState
    Invoke-WorkspaceSync -IsFinal $true
    $global:LASTEXITCODE = 0
    exit 0
} else {
    Invoke-WorkspaceSync -IsFinal $false
    $global:LASTEXITCODE = 0
    exit 0
}
