<#
.SYNOPSIS
    sync-windows-workspace.ps1: Background & Final Workspace Synchronization to Google Drive
.DESCRIPTION
    Safely synchronizes C:\Users\runneradmin\workspace to gdrive:cloud-dev/windows-workspace
    preventing overlapping sync operations and excluding temporary build artifacts and secrets.
#>

[CmdletBinding()]
param(
    [string]$WorkspaceDir = "C:\Users\runneradmin\workspace",
    [string]$RemoteSubdir = "cloud-dev/windows-workspace",
    [switch]$Final = $false,
    [switch]$Daemon = $false
)

$ErrorActionPreference = "Continue"

$LockFile = "$env:TEMP\windows-workspace-sync.lock"

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

        # Generate backup manifest
        $manifestPath = Join-Path -Path $WorkspaceDir -ChildPath "backups\backup-manifest.json"
        $manifestDir = Split-Path -Path $manifestPath -Parent
        if (-not (Test-Path $manifestDir)) {
            New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
        }

        $manifestData = @{
            timestamp = (Get-Date -Format "o")
            sync_type = if ($IsFinal) { "final" } else { "interval" }
            os = "windows"
            workspace = $WorkspaceDir
            remote = "gdrive:$RemoteSubdir"
        }
        $manifestData | ConvertTo-Json | Set-Content -Path $manifestPath -Encoding UTF8

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

if ($Daemon) {
    Write-Host "Starting continuous 5-minute workspace synchronization daemon..."
    while ($true) {
        Start-Sleep -Seconds 300
        Invoke-WorkspaceSync -IsFinal $false
    }
} else {
    Invoke-WorkspaceSync -IsFinal $Final
}
