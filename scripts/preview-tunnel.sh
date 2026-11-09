#!/usr/bin/env bash
# ==============================================================================
# preview-tunnel.sh: Create on-demand temporary Cloudflare Quick Tunnel for preview
# Creates a tunnel ONLY when explicitly requested from DeepSeek Harness or terminal.
# Keeps the tunnel running in background while the cloud environment is active.
# ==============================================================================

set -eo pipefail

PORT="${1:-}"

if [ -z "${PORT}" ] || [[ ! "${PORT}" =~ ^[0-9]+$ ]]; then
    echo "Usage: preview-tunnel <port>" >&2
    echo "Example: preview-tunnel 5173" >&2
    exit 1
fi

TUNNEL_DIR="/tmp/tunnels"
mkdir -p "${TUNNEL_DIR}"

PID_FILE="${TUNNEL_DIR}/tunnel_${PORT}.pid"
LOG_FILE="${TUNNEL_DIR}/tunnel_${PORT}.log"

# Check if tunnel is already active for this port
if [ -f "${PID_FILE}" ]; then
    EXISTING_PID=$(cat "${PID_FILE}" 2>/dev/null || true)
    if [ -n "${EXISTING_PID}" ] && kill -0 "${EXISTING_PID}" 2>/dev/null; then
        EXISTING_URL=$(grep -o -E "https://[-a-zA-Z0-9.]+\.trycloudflare\.com" "${LOG_FILE}" 2>/dev/null | head -n 1 || true)
        if [ -n "${EXISTING_URL}" ]; then
            echo "================================================================================"
            echo "🌐 Cloudflare Preview Tunnel already running for Port ${PORT}!"
            echo "🔗 Public Preview URL: ${EXISTING_URL}"
            echo "================================================================================"
            exit 0
        fi
    fi
fi

# Ensure cloudflared is installed
if ! command -v cloudflared &>/dev/null; then
    echo "Installing cloudflared for on-demand preview tunnel..."
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb
    sudo dpkg -i /tmp/cloudflared.deb >/dev/null 2>&1 || true
    rm -f /tmp/cloudflared.deb
fi

echo "=================================================="
echo "🌐 Launching Temporary Cloudflare Quick Tunnel"
echo "=================================================="
echo "Target: http://127.0.0.1:${PORT}"

rm -f "${LOG_FILE}"
cloudflared tunnel --url "http://127.0.0.1:${PORT}" --http-host-header "localhost:${PORT}" --no-autoupdate > "${LOG_FILE}" 2>&1 &
TUNNEL_PID=$!
echo "${TUNNEL_PID}" > "${PID_FILE}"

# Wait for quick tunnel URL to appear in logs
TUNNEL_URL=""
for i in $(seq 1 30); do
    if grep -q "trycloudflare.com" "${LOG_FILE}" 2>/dev/null; then
        TUNNEL_URL=$(grep -o -E "https://[-a-zA-Z0-9.]+\.trycloudflare\.com" "${LOG_FILE}" | head -n 1)
        if [ -n "${TUNNEL_URL}" ]; then
            break
        fi
    fi
    sleep 1
done

if [ -z "${TUNNEL_URL}" ]; then
    echo "❌ Error: Could not obtain Cloudflare Tunnel URL. Tunnel logs:" >&2
    cat "${LOG_FILE}" >&2
    exit 1
fi

echo ""
echo "================================================================================"
echo "🎉 CLOUDFLARE PREVIEW TUNNEL ONLINE (PORT ${PORT})"
echo "================================================================================"
echo ""
echo "🔗 Public Browser Preview: ${TUNNEL_URL}"
echo ""
echo "ℹ️ This tunnel will remain active while your cloud-dev session is running."
echo "================================================================================"
echo ""

# Record active preview
echo "Port ${PORT}: ${TUNNEL_URL}" >> /tmp/active_previews.txt

# Update GitHub Step Summary if available
if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
    {
        echo "### 🌐 On-Demand Cloudflare Preview Tunnel"
        echo "- **Port:** \`${PORT}\`"
        echo "- **Preview URL:** [${TUNNEL_URL}](${TUNNEL_URL})"
        echo "- **Created At:** $(date -u +"%Y-%m-%d %H:%M:%SZ")"
        echo ""
    } >> "${GITHUB_STEP_SUMMARY}"
fi
