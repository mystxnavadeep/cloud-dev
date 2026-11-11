<#
.SYNOPSIS
    maintain-windows-studio.ps1: Displays studio credentials & maintains connection loop
#>

[CmdletBinding()]
param()

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

# Maintain connection loop until cancellation or timeout (6 hours)
$cycle = 0
while ($true) {
    $cycle++
    $time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    Write-Host "[$time] Windows Studio Active (Cycle #$cycle) - RDP and SSH listening on $ip"
    Start-Sleep -Seconds 300
}
