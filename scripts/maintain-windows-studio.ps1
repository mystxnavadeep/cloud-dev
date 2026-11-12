<#
.SYNOPSIS
    maintain-windows-studio.ps1: Displays studio credentials & maintains connection loop
.DESCRIPTION
    Keeps Windows RDP + OpenSSH environment alive within a safe runtime budget (default 340 min)
    to guarantee graceful shutdown and final Google Drive backup prior to GitHub's 6-hour limit.
#>

[CmdletBinding()]
param(
    [int]$SessionDurationMinutes = 340
)

# Parse environment override if present
if ($env:SESSION_DURATION_MINUTES -and ($env:SESSION_DURATION_MINUTES -match '^\d+$')) {
    $SessionDurationMinutes = [int]$env:SESSION_DURATION_MINUTES
}

# Cap session duration at 345 minutes to guarantee at least 15 minutes for final sync & verification
if ($SessionDurationMinutes -gt 345) {
    Write-Warning "Requested duration ($SessionDurationMinutes min) exceeds safe runner margin. Capping at 345 min."
    $SessionDurationMinutes = 345
}

$ip = $env:TAILSCALE_IP
$hostname = $env:TAILSCALE_HOSTNAME
$password = $env:RDP_PASSWORD

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "   WINDOWS CLOUD WEB DEVELOPMENT STUDIO - LIVE & PERSISTENT" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "REMOTE ACCESS DETAILS:" -ForegroundColor Yellow
Write-Host "   * Tailscale IP:       $ip"
Write-Host "   * Tailscale Hostname: $hostname"
Write-Host ""
Write-Host "REMOTE DESKTOP (RDP):" -ForegroundColor Yellow
Write-Host "   * Host / Port:        $ip`:3389  (or $hostname`:3389)"
Write-Host "   * Username:           RDP"
Write-Host "   * Password:           $password"
Write-Host ""
Write-Host "SECURE SHELL (SSH):" -ForegroundColor Yellow
Write-Host "   * SSH Command:        ssh RDP@$ip"
Write-Host "   * SSH via Hostname:   ssh RDP@$hostname"
Write-Host "   * Runner Admin SSH:   ssh runneradmin@$ip"
Write-Host "   * SSH Password:       $password"
Write-Host ""
Write-Host "PERSISTENT WORKSPACE:" -ForegroundColor Yellow
Write-Host "   * Local Path:         C:\Users\runneradmin\workspace"
Write-Host "   * RDP User Path:      C:\Users\RDP\workspace (Junction Link)"
Write-Host "   * Google Drive Path:  gdrive:cloud-dev/windows-workspace"
Write-Host "   * Auto-Sync:          Every 5 minutes in background"
Write-Host ""
Write-Host "SESSION BUDGET:" -ForegroundColor Yellow
Write-Host "   * Maximum Duration:   $SessionDurationMinutes minutes (Safe 6-Hour Runner Budget)"
Write-Host "   * Graceful Shutdown:  Automatic termination before GitHub hard timeout"
Write-Host ""
Write-Host "DEVELOPER SHORTCUTS (PowerShell):" -ForegroundColor Yellow
Write-Host "   * 'ws'                -> cd C:\Users\runneradmin\workspace"
Write-Host "   * 'projects'          -> cd C:\Users\runneradmin\workspace\projects"
Write-Host "   * 'web'               -> cd C:\Users\runneradmin\workspace\web"
Write-Host "   * 'oc'                -> OpenCode CLI"
Write-Host "   * 'agy'               -> Google Antigravity CLI"
Write-Host "   * 'dsh'               -> DeepSeek Harness CLI"
Write-Host "   * 'wrangler'          -> Cloudflare Workers & Pages CLI"
Write-Host "   * 'vercel'            -> Vercel Deployment CLI"
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""

# Write to GitHub Step Summary
if ($env:GITHUB_STEP_SUMMARY) {
    $summary = @"
## 🪟 Windows Cloud Web Development Studio

### 📡 Remote Access Details
| Protocol | Address | Username | Password / Auth |
|---|---|---|---|
| **RDP (Desktop)** | ``$ip`:3389`` (or ``$hostname`:3389``) | ``RDP`` | ``$password`` |
| **SSH (Shell)** | ``$ip`:22`` (or ``$hostname`:22``) | ``RDP`` / ``runneradmin`` | ``$password`` |

#### 💻 Quick SSH Command
````bash
ssh RDP@$ip
# Or via MagicDNS:
ssh RDP@$hostname
````

### 📁 Persistent Workspace & Cloud Sync
- **Local Workspace:** ``C:\Users\runneradmin\workspace``
- **RDP Junction:** ``C:\Users\RDP\workspace``
- **Google Drive Remote:** ``gdrive:cloud-dev/windows-workspace``
- **Auto-Sync:** Every 5 minutes in background
- **Session Duration:** $SessionDurationMinutes minutes (Graceful shutdown before 6-hour limit)
"@
    Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $summary -Encoding UTF8
}

$startTime = Get-Date
$totalDurationSeconds = $SessionDurationMinutes * 60
$cycle = 0

Write-Host "Session active for $SessionDurationMinutes minutes ($totalDurationSeconds seconds)..."

while ($true) {
    $elapsed = (Get-Date) - $startTime
    $elapsedSeconds = $elapsed.TotalSeconds

    if ($elapsedSeconds -ge $totalDurationSeconds) {
        Write-Host ""
        Write-Host "⏰ Session duration budget ($SessionDurationMinutes min) reached. Initiating graceful shutdown..." -ForegroundColor Yellow
        break
    }

    $cycle++
    $remainingMinutes = [math]::Round(($totalDurationSeconds - $elapsedSeconds) / 60, 1)
    $time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Write-Host "[$time] Windows Studio Active (Cycle #$cycle) - Remaining: ${remainingMinutes}m - RDP & SSH listening on $ip"

    $sleepDuration = [math]::Min(300, [math]::Max(5, [int]($totalDurationSeconds - $elapsedSeconds)))
    Start-Sleep -Seconds $sleepDuration
}

Write-Host ""
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "✅ Keep-alive loop ended gracefully. Proceeding to final backup and cleanup." -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan

$global:LASTEXITCODE = 0
exit 0
