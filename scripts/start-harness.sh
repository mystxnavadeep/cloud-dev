#!/usr/bin/env bash
# ==============================================================================
# start-harness.sh: Launch DeepSeek Harness Web UI with Tailscale-Only Access
# NO public tunnels (Cloudflare/ngrok removed).
# Services bind strictly to the private Tailscale network.
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

WORKSPACE_DIR="${WORKSPACE_DIR:-/home/runner/workspace}"
PORT="${DSH_PORT:-3080}"
SESSION_DURATION_MINUTES="${SESSION_DURATION_MINUTES:-350}"

export DSH_HOME="${WORKSPACE_DIR}/.dsh"
export DSH_AGENTS_HOME="${WORKSPACE_DIR}/.agents"

mkdir -p "${DSH_HOME}" "${DSH_AGENTS_HOME}"
cd "${WORKSPACE_DIR}"

DSH_LOG="/tmp/dsh.log"
rm -f "${DSH_LOG}"

# Cleanup handler on exit or signal
cleanup() {
    echo ""
    echo "=================================================="
    echo "🛑 Shutting Down Cloud Development Session"
    echo "=================================================="
    if [ -n "${PREVIEW_MONITOR_PID:-}" ] && kill -0 "${PREVIEW_MONITOR_PID}" 2>/dev/null; then
        echo "Stopping preview monitor (PID: ${PREVIEW_MONITOR_PID})..."
        kill -SIGTERM "${PREVIEW_MONITOR_PID}" 2>/dev/null || true
    fi
    if [ -n "${DSH_PID:-}" ] && kill -0 "${DSH_PID}" 2>/dev/null; then
        echo "Terminating DeepSeek Harness (PID: ${DSH_PID})..."
        kill -SIGTERM "${DSH_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT SIGTERM SIGINT

# 1. Resolve and verify Tailscale network identity
TAILSCALE_IP="${TAILSCALE_IP:-}"
if [ -z "${TAILSCALE_IP}" ]; then
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
fi

if [ -z "${TAILSCALE_IP}" ] || [[ ! "${TAILSCALE_IP}" =~ ^100\. ]]; then
    echo "❌ Error: Valid Tailscale IP not found (${TAILSCALE_IP}). Tailscale is required for private access!" >&2
    exit 1
fi

TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-}"
if [ -z "${TAILSCALE_HOSTNAME}" ]; then
    TAILSCALE_HOSTNAME=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//' || echo "${TAILSCALE_IP}")
fi

echo "=================================================="
echo "🛡️ Starting Private DeepSeek Harness on Tailscale"
echo "=================================================="
echo "Bind Address:       ${TAILSCALE_IP} (tailscale0)"
echo "Port:               ${PORT}"
echo "MagicDNS Hostname:  ${TAILSCALE_HOSTNAME}"
echo "Public Tunnels:     DISABLED"

# 2. Start the Private Website Preview Monitor in background
echo "Starting Website Preview Monitor..."
"$(dirname "$0")/preview-monitor.sh" > /tmp/preview-monitor.log 2>&1 &
PREVIEW_MONITOR_PID=$!

# 3. Launch DeepSeek Harness Web UI bound to Tailscale IP
# Pass --no-open to avoid xdg-open in headless environment
# Pass --host to bind strictly to the Tailscale interface
# Pass --public-url and --trusted-host so dsh creates the authenticated access URL
dsh web \
    --no-open \
    --host "${TAILSCALE_IP}" \
    --port "${PORT}" \
    --public-url "http://${TAILSCALE_IP}:${PORT}" \
    --trusted-host "${TAILSCALE_IP}" \
    --trusted-host "${TAILSCALE_HOSTNAME}" \
    > "${DSH_LOG}" 2>&1 &
DSH_PID=$!

# 4. Wait for Harness to output the authenticated URL
echo "Waiting for DeepSeek Harness Web UI to be ready..."
FINAL_WEB_URL=""
for i in $(seq 1 45); do
    if ! kill -0 "${DSH_PID}" 2>/dev/null; then
        echo "❌ Error: DeepSeek Harness process exited unexpectedly. Logs:" >&2
        cat "${DSH_LOG}" >&2
        exit 1
    fi

    # Search for authenticated URL from dsh logs
    if grep -q -i "dsh web:" "${DSH_LOG}" 2>/dev/null; then
        RAW_URL=$(grep -i "dsh web:" "${DSH_LOG}" | head -n 1 | sed -E 's/.*dsh web:[[:space:]]*//')
        if [ -n "${RAW_URL}" ]; then
            FINAL_WEB_URL="${RAW_URL}"
            break
        fi
    fi
    sleep 1
done

# Fallback if specific log format differed
if [ -z "${FINAL_WEB_URL}" ]; then
    FINAL_WEB_URL="http://${TAILSCALE_IP}:${PORT}"
fi

# Also formulate MagicDNS URL with authentication query params
AUTH_QUERY=$(echo "${FINAL_WEB_URL}" | grep -o -E '\?.*$' || true)
MAGICDNS_URL="http://${TAILSCALE_HOSTNAME}:${PORT}${AUTH_QUERY}"

echo ""
echo "================================================================================"
echo "🔒 DEEPSEEK HARNESS WEB UI IS ONLINE (TAILSCALE PRIVATE ACCESS ONLY)"
echo "================================================================================"
echo ""
echo "🔗 Direct Tailscale IP URL:    ${FINAL_WEB_URL}"
echo "🔗 MagicDNS Hostname URL:     ${MAGICDNS_URL}"
echo ""
echo "🌐 Website Previews:           http://${TAILSCALE_IP}:<PREVIEW_PORT>"
echo "   Example (React/Vite):       npm run dev -- --host 0.0.0.0 (Port 5173)"
echo "   Example (Next.js):          npx next dev -H 0.0.0.0 -p 3000"
echo "   Example (FastAPI):          uvicorn main:app --host 0.0.0.0 --port 8000"
echo ""
echo "📁 Workspace Directory:        ${WORKSPACE_DIR}"
echo "⏱️ Session Duration:           ${SESSION_DURATION_MINUTES} minutes (Max 6 hours)"
echo "🔄 Persistence:                Auto-syncing to Google Drive every 5 minutes"
echo "🔒 Remote Access Policy:       Tailscale ONLY (Zero public tunnels/ports)"
echo ""
echo "================================================================================"
echo ""

# Write to GitHub Step Summary
if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
    {
        echo "## 🚀 DeepSeek Harness Cloud Environment (Tailscale Private)"
        echo ""
        echo "### 🤖 DeepSeek Harness Web UI"
        echo "- **Direct Tailscale IP URL:** [${FINAL_WEB_URL}](${FINAL_WEB_URL})"
        echo "- **MagicDNS URL:** [${MAGICDNS_URL}](${MAGICDNS_URL})"
        echo ""
        echo "```text"
        echo "${FINAL_WEB_URL}"
        echo "```"
        echo ""
        echo "### 🌐 Private Website Preview Instructions"
        echo "To preview websites on your authenticated Tailscale device:"
        echo "1. Run your dev server bound to \`0.0.0.0\`:"
        echo "   - **Vite:** \`npm run dev -- --host 0.0.0.0\`"
        echo "   - **Next.js:** \`npx next dev -H 0.0.0.0 -p 3000\`"
        echo "   - **FastAPI:** \`uvicorn main:app --host 0.0.0.0 --port 8000\`"
        echo "   - **Static HTML:** \`preview serve <dir> [port]\`"
        echo "2. Open in browser: \`http://${TAILSCALE_IP}:<PORT>\`"
        echo ""
        echo "### 📋 Session Details"
        echo "- **Status:** 🟢 Active"
        echo "- **Tailscale IP:** \`${TAILSCALE_IP}\`"
        echo "- **MagicDNS:** \`${TAILSCALE_HOSTNAME}\`"
        echo "- **Workspace:** \`${WORKSPACE_DIR}\`"
        echo "- **Auto-sync Interval:** Every 5 minutes to Google Drive"
        echo ""
        echo "> **Note:** Access is restricted exclusively to devices on your Tailnet. No public ports or reverse tunnels are created."
    } >> "${GITHUB_STEP_SUMMARY}"
fi

# Stream logs in background while monitoring session duration
tail -n 20 -f "${DSH_LOG}" &
TAIL_PID=$!

SESSION_SECONDS=$((SESSION_DURATION_MINUTES * 60))
echo "Session active for ${SESSION_DURATION_MINUTES} minutes (${SESSION_SECONDS}s)..."

# Sleep in increments to remain responsive to SIGTERM
START_TIME=$(date +%s)
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ "${ELAPSED}" -ge "${SESSION_SECONDS}" ]; then
        echo "⏰ Session duration of ${SESSION_DURATION_MINUTES} minutes reached. Initiating shutdown..."
        break
    fi

    # Check if DSH died
    if ! kill -0 "${DSH_PID}" 2>/dev/null; then
        echo "⚠️ DeepSeek Harness stopped."
        break
    fi

    sleep 10
done

kill "${TAIL_PID}" 2>/dev/null || true
echo "Session loop finished."
