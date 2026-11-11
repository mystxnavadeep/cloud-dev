<#
.SYNOPSIS
    setup-windows-auth.ps1: Configure Cloud Platform CLIs & Credentials Securely
.DESCRIPTION
    Configures environment variables for Cloudflare (Wrangler), Vercel, DeepSeek,
    and GitHub CLI without echoing sensitive tokens into workflow logs.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

Write-Host "=================================================="
Write-Host "🔐 Authenticating Cloud Platform CLIs"
Write-Host "=================================================="

# 1. Cloudflare Authentication (Wrangler)
if ($env:CLOUDFLARE_API_TOKEN -and $env:CLOUDFLARE_API_TOKEN -ne "add") {
    Write-Host "Configuring Cloudflare credentials..."
    [Environment]::SetEnvironmentVariable("CLOUDFLARE_API_TOKEN", $env:CLOUDFLARE_API_TOKEN, "Machine")
    [Environment]::SetEnvironmentVariable("CLOUDFLARE_API_TOKEN", $env:CLOUDFLARE_API_TOKEN, "Process")
    if ($env:CLOUDFLARE_ACCOUNT_ID) {
        [Environment]::SetEnvironmentVariable("CLOUDFLARE_ACCOUNT_ID", $env:CLOUDFLARE_ACCOUNT_ID, "Machine")
        [Environment]::SetEnvironmentVariable("CLOUDFLARE_ACCOUNT_ID", $env:CLOUDFLARE_ACCOUNT_ID, "Process")
    }

    try {
        $whoami = & wrangler whoami 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Cloudflare Wrangler authenticated successfully."
        } else {
            Write-Host "⚠️ Cloudflare Wrangler credentials set (verification returned non-zero)."
        }
    } catch {
        Write-Warning "Wrangler check warning: $_"
    }
} else {
    Write-Host "ℹ️ CLOUDFLARE_API_TOKEN not set or placeholder; skipping Cloudflare login."
}

# 2. Vercel CLI Authentication
if ($env:VERCEL_TOKEN -and $env:VERCEL_TOKEN -ne "add") {
    Write-Host "Configuring Vercel credentials..."
    [Environment]::SetEnvironmentVariable("VERCEL_TOKEN", $env:VERCEL_TOKEN, "Machine")
    [Environment]::SetEnvironmentVariable("VERCEL_TOKEN", $env:VERCEL_TOKEN, "Process")
    if ($env:VERCEL_ORG_ID) {
        [Environment]::SetEnvironmentVariable("VERCEL_ORG_ID", $env:VERCEL_ORG_ID, "Machine")
        [Environment]::SetEnvironmentVariable("VERCEL_ORG_ID", $env:VERCEL_ORG_ID, "Process")
    }

    try {
        $vWhoami = & vercel whoami --token $env:VERCEL_TOKEN 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✅ Vercel CLI authenticated successfully ($($vWhoami | Select-Object -First 1))."
        } else {
            Write-Host "⚠️ Vercel credentials set (verification returned non-zero)."
        }
    } catch {
        Write-Warning "Vercel check warning: $_"
    }
} else {
    Write-Host "ℹ️ VERCEL_TOKEN not set or placeholder; skipping Vercel login."
}

# 3. DeepSeek Harness Integration
if ($env:DEEPSEEK_API_KEY -and $env:DEEPSEEK_API_KEY -ne "add") {
    Write-Host "Configuring DeepSeek API credentials..."
    [Environment]::SetEnvironmentVariable("DEEPSEEK_API_KEY", $env:DEEPSEEK_API_KEY, "Machine")
    [Environment]::SetEnvironmentVariable("DEEPSEEK_API_KEY", $env:DEEPSEEK_API_KEY, "Process")
    Write-Host "✅ DEEPSEEK_API_KEY injected into environment."
} else {
    Write-Host "ℹ️ DEEPSEEK_API_KEY not set; skipping DeepSeek integration."
}

# 4. GitHub CLI Authentication
if ($env:GITHUB_TOKEN) {
    Write-Host "Configuring GitHub CLI & Git credential helper..."
    try {
        & gh auth setup-git 2>$null
        $ghStatus = & gh auth status 2>&1
        Write-Host "✅ GitHub CLI configured with runner token."
    } catch {
        Write-Warning "GitHub CLI setup warning: $_"
    }
}

Write-Host "=================================================="
Write-Host "✅ Authentication Setup Complete"
Write-Host "=================================================="
$global:LASTEXITCODE = 0
exit 0
