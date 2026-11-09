#!/usr/bin/env bash
# ==============================================================================
# start-harness.sh: Launch Cloudflare Tunnel and DeepSeek Harness Web UI
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

CLOUDFLARED_LOG="/tmp/cloudflared.log"
DSH_LOG="/tmp/dsh.log"
rm -f "${CLOUDFLARED_LOG}" "${DSH_LOG}"

# Cleanup handler on exit or signal
cleanup() {
    echo ""
    echo "=================================================="
    echo "🛑 Shutting Down DeepSeek Harness Session"
    echo "=================================================="
    if [ -n "${DSH_PID:-}" ] && kill -0 "${DSH_PID}" 2>/dev/null; then
        echo "Terminating DeepSeek Harness (PID: ${DSH_PID})..."
        kill -SIGTERM "${DSH_PID}" 2>/dev/null || true
    fi
    if [ -n "${TUNNEL_PID:-}" ] && kill -0 "${TUNNEL_PID}" 2>/dev/null; then
        echo "Terminating Cloudflare Tunnel (PID: ${TUNNEL_PID})..."
        kill -SIGTERM "${TUNNEL_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT SIGTERM SIGINT

echo "=================================================="
echo "🌐 Starting Cloudflare Tunnel"
echo "=================================================="

# Check if a custom Cloudflare Tunnel token is provided
if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    echo "Using provided Cloudflare Tunnel Token..."
    cloudflared tunnel --no-autoupdate run --token "${CLOUDFLARE_TUNNEL_TOKEN}" > "${CLOUDFLARED_LOG}" 2>&1 &
    TUNNEL_PID=$!
    # If custom token is used, user already configured hostname or public URL
    TUNNEL_URL="${CUSTOM_TUNNEL_URL:-https://localhost:${PORT}}"
    TUNNEL_HOST=$(echo "${TUNNEL_URL}" | sed -E 's~https?://([^/:]+).*~\1~')
else
    echo "Using Cloudflare Quick Tunnel (zero-configuration)..."
    cloudflared tunnel --url "http://127.0.0.1:${PORT}" --http-host-header "localhost:${PORT}" --no-autoupdate > "${CLOUDFLARED_LOG}" 2>&1 &
    TUNNEL_PID=$!

    # Wait for tunnel URL to appear in logs
    echo "Waiting for Cloudflare Tunnel URL..."
    TUNNEL_URL=""
    for i in $(seq 1 45); do
        if grep -q "trycloudflare.com" "${CLOUDFLARED_LOG}" 2>/dev/null; then
            TUNNEL_URL=$(grep -o -E "https://[-a-zA-Z0-9.]+\.trycloudflare\.com" "${CLOUDFLARED_LOG}" | head -n 1)
            if [ -n "${TUNNEL_URL}" ]; then
                break
            fi
        fi
        sleep 1
    done

    if [ -z "${TUNNEL_URL}" ]; then
        echo "❌ Error: Could not establish Cloudflare Tunnel. Tunnel logs:" >&2
        cat "${CLOUDFLARED_LOG}" >&2
        exit 1
    fi
    TUNNEL_HOST=$(echo "${TUNNEL_URL}" | sed -E 's~https?://([^/:]+).*~\1~')
fi

echo "✅ Tunnel established: ${TUNNEL_URL}"

echo "=================================================="
echo "🤖 Starting DeepSeek Harness Web UI"
echo "=================================================="

# Launch dsh web
# Pass --no-open to avoid xdg-open failure in headless environment
# Pass --public-url and --trusted-host so dsh creates the authenticated access URL
dsh web \
    --no-open \
    --host 127.0.0.1 \
    --port "${PORT}" \
    --public-url "${TUNNEL_URL}" \
    --trusted-host "${TUNNEL_HOST}" \
    > "${DSH_LOG}" 2>&1 &
DSH_PID=$!

# Wait for Harness to output the authenticated URL
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
    FINAL_WEB_URL="${TUNNEL_URL}"
fi

echo ""
echo "================================================================================"
echo "🎉 DEEPSEEK HARNESS WEB UI IS ONLINE!"
echo "================================================================================"
echo ""
echo "🔗 Access URL: ${FINAL_WEB_URL}"
echo ""
echo "📁 Workspace Directory: ${WORKSPACE_DIR}"
echo "⏱️ Session Duration:    ${SESSION_DURATION_MINUTES} minutes (Max 6 hours)"
echo "🔄 Persistence:         Auto-syncing to Google Drive every 5 minutes"
echo ""
echo "================================================================================"
echo ""

# Write to GitHub Step Summary
if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
    {
        echo "## 🚀 DeepSeek Harness Cloud Environment"
        echo ""
        echo "### 🌐 Web Interface"
        echo "[**👉 Click Here to Open DeepSeek Harness**](${FINAL_WEB_URL})"
        echo ""
        echo "\`\`\`"
        echo "${FINAL_WEB_URL}"
        echo "\`\`\`"
        echo ""
        echo "### 📋 Session Details"
        echo "- **Status:** 🟢 Active"
        echo "- **Tunnel Host:** \`${TUNNEL_HOST}\`"
        echo "- **Workspace:** \`${WORKSPACE_DIR}\`"
        echo "- **Max Duration:** ${SESSION_DURATION_MINUTES} minutes"
        echo "- **Auto-sync Interval:** Every 5 minutes to Google Drive"
        echo ""
        echo "> **Tip:** Keep this workflow running while developing. All code and settings are saved automatically!"
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
