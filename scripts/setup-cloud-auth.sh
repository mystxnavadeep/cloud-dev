#!/usr/bin/env bash
# ==============================================================================
# setup-cloud-auth.sh: Configure authentication for Cloud CLIs (gh, wrangler, vercel)
# Securely sets up credentials without leaking any secret values into logs.
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

ENV_FILE="${HOME}/.cloud_dev_env"
touch "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

echo "=================================================="
echo "🔐 Configuring Cloud Platform CLI Authentication"
echo "=================================================="

# ------------------------------------------------------------------------------
# 1. GitHub CLI (gh)
# ------------------------------------------------------------------------------
if [ -n "${GH_TOKEN:-}" ]; then
    echo "Configuring GitHub CLI (gh)..."
    echo "${GH_TOKEN}" | gh auth login --with-token >/dev/null 2>&1 || true
    gh auth setup-git >/dev/null 2>&1 || true
    echo "export GH_TOKEN=\"${GH_TOKEN}\"" >> "${ENV_FILE}"
    echo "export GITHUB_TOKEN=\"${GH_TOKEN}\"" >> "${ENV_FILE}"

    if gh auth status >/dev/null 2>&1; then
        GH_USER=$(gh api user -q .login 2>/dev/null || echo "authenticated user")
        echo "✅ GitHub CLI authenticated as: ${GH_USER}"
    else
        echo "⚠️ Warning: GitHub CLI auth login completed, but status check failed."
    fi
else
    echo "ℹ️ GH_TOKEN not provided; skipping custom GitHub CLI authentication."
fi

# ------------------------------------------------------------------------------
# 2. Cloudflare Wrangler CLI (wrangler)
# ------------------------------------------------------------------------------
if [ -n "${CLOUDFLARE_API_TOKEN:-}" ]; then
    echo "Configuring Cloudflare Wrangler..."
    echo "export CLOUDFLARE_API_TOKEN=\"${CLOUDFLARE_API_TOKEN}\"" >> "${ENV_FILE}"

    if [ -n "${CLOUDFLARE_ACCOUNT_ID:-}" ]; then
        echo "export CLOUDFLARE_ACCOUNT_ID=\"${CLOUDFLARE_ACCOUNT_ID}\"" >> "${ENV_FILE}"
    fi

    # Test Wrangler credentials without exposing token
    if CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN}" wrangler whoami >/dev/null 2>&1; then
        echo "✅ Cloudflare Wrangler authenticated successfully."
    else
        echo "⚠️ Warning: Cloudflare credentials configured, but wrangler whoami verification returned non-zero."
    fi
else
    echo "ℹ️ CLOUDFLARE_API_TOKEN not provided; skipping Wrangler authentication."
fi

# ------------------------------------------------------------------------------
# 3. Vercel CLI (vercel)
# ------------------------------------------------------------------------------
if [ -n "${VERCEL_TOKEN:-}" ]; then
    echo "Configuring Vercel CLI..."
    mkdir -p "${HOME}/.vercel"
    chmod 700 "${HOME}/.vercel"

    # Write auth token file
    cat << EOF > "${HOME}/.vercel/auth.json"
{"token":"${VERCEL_TOKEN}"}
EOF
    chmod 600 "${HOME}/.vercel/auth.json"

    echo "export VERCEL_TOKEN=\"${VERCEL_TOKEN}\"" >> "${ENV_FILE}"
    if [ -n "${VERCEL_ORG_ID:-}" ]; then
        echo "export VERCEL_ORG_ID=\"${VERCEL_ORG_ID}\"" >> "${ENV_FILE}"
    fi
    if [ -n "${VERCEL_PROJECT_ID:-}" ]; then
        echo "export VERCEL_PROJECT_ID=\"${VERCEL_PROJECT_ID}\"" >> "${ENV_FILE}"
    fi

    if vercel whoami >/dev/null 2>&1; then
        VERCEL_USER=$(vercel whoami 2>/dev/null | tr -d '\n' || echo "authenticated user")
        echo "✅ Vercel CLI authenticated as: ${VERCEL_USER}"
    else
        echo "⚠️ Warning: Vercel CLI configured, but vercel whoami check returned non-zero."
    fi
else
    echo "ℹ️ VERCEL_TOKEN not provided; skipping Vercel CLI authentication."
fi

# Ensure .cloud_dev_env is sourced in all future bash sessions
if ! grep -q "source ${ENV_FILE}" "${HOME}/.bashrc" 2>/dev/null; then
    echo "source ${ENV_FILE}" >> "${HOME}/.bashrc"
fi

echo "✅ Cloud CLI authentication setup complete."
