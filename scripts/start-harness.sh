#!/usr/bin/env bash
# ==============================================================================
# start-harness.sh: Launch DeepSeek Harness Web UI and Development Environment
# Preserves preview behavior:
# - Does NOT automatically create Cloudflare Quick Tunnels on startup.
# - On-demand Cloudflare tunnels created via 'preview tunnel <port>' or Harness.
# - Keeps preview servers and tunnels alive while environment is active.
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-/home/runner}"
WORKSPACE_DIR="${WORKSPACE_DIR:-${GITHUB_WORKSPACE}/workspace}"
PORT="${DSH_PORT:-3080}"
SESSION_DURATION_MINUTES="${SESSION_DURATION_MINUTES:-350}"

export DSH_HOME="${WORKSPACE_DIR}/.dsh"
export DSH_AGENTS_HOME="${WORKSPACE_DIR}/.agents"

# Sanitize placeholder DEEPSEEK_API_KEY
if [ "${DEEPSEEK_API_KEY:-}" = "add" ]; then
    unset DEEPSEEK_API_KEY
fi

mkdir -p "${DSH_HOME}" "${DSH_AGENTS_HOME}" "${WORKSPACE_DIR}"
cd "${WORKSPACE_DIR}"

DSH_LOG="/tmp/dsh.log"
rm -f "${DSH_LOG}"

# Cleanup handler on exit or signal
cleanup() {
    echo ""
    echo "=================================================="
    echo "🛑 Shutting Down Cloud Development Session"
    echo "=================================================="

    # Stop preview monitor
    if [ -n "${PREVIEW_MONITOR_PID:-}" ] && kill -0 "${PREVIEW_MONITOR_PID}" 2>/dev/null; then
        echo "Stopping preview monitor (PID: ${PREVIEW_MONITOR_PID})..."
        kill -TERM "${PREVIEW_MONITOR_PID}" 2>/dev/null || true
    fi

    # Clean up any on-demand Cloudflare preview tunnels
    if [ -d "/tmp/tunnels" ]; then
        for PID_F in /tmp/tunnels/*.pid; do
            if [ -f "${PID_F}" ]; then
                T_PID=$(cat "${PID_F}" 2>/dev/null || true)
                if [ -n "${T_PID}" ] && kill -0 "${T_PID}" 2>/dev/null; then
                    echo "Stopping preview tunnel PID ${T_PID}..."
                    kill -TERM "${T_PID}" 2>/dev/null || true
                fi
                rm -f "${PID_F}"
            fi
        done
    fi

    # Stop DeepSeek Harness
    if [ -n "${DSH_PID:-}" ] && kill -0 "${DSH_PID}" 2>/dev/null; then
        echo "Terminating DeepSeek Harness (PID: ${DSH_PID})..."
        kill -TERM "${DSH_PID}" 2>/dev/null || true
    fi
}
trap cleanup EXIT SIGTERM SIGINT

# Resolve Network Host
BIND_HOST="127.0.0.1"
ACCESS_HOST="127.0.0.1"

TAILSCALE_IP="${TAILSCALE_IP:-}"
if [ -z "${TAILSCALE_IP}" ]; then
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
fi

TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-}"
if [ -z "${TAILSCALE_HOSTNAME}" ]; then
    TAILSCALE_HOSTNAME=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//' || true)
fi

TRUSTED_ARGS=()
if [ -n "${TAILSCALE_IP}" ] && [[ "${TAILSCALE_IP}" =~ ^100\. ]]; then
    BIND_HOST="${TAILSCALE_IP}"
    ACCESS_HOST="${TAILSCALE_HOSTNAME:-$TAILSCALE_IP}"
    echo "Tailscale detected: Binding Harness to ${BIND_HOST} (Access via http://${ACCESS_HOST}:${PORT})"
    TRUSTED_ARGS+=("--trusted-host" "${ACCESS_HOST}")
    TRUSTED_ARGS+=("--trusted-host" "${TAILSCALE_IP}")
    if [ -n "${TAILSCALE_HOSTNAME}" ]; then
        TRUSTED_ARGS+=("--trusted-host" "${TAILSCALE_HOSTNAME}")
    fi
    # Also expose via Tailscale Serve if available
    tailscale serve --bg --set-path / "http://${BIND_HOST}:${PORT}" 2>/dev/null || true
fi

TRUSTED_ARGS+=("--trusted-host" "localhost")
TRUSTED_ARGS+=("--trusted-host" "127.0.0.1")

echo "=================================================="
echo "🤖 Starting DeepSeek Harness Web UI"
echo "=================================================="
echo "Bind Host:       ${BIND_HOST}"
echo "Access Host:     ${ACCESS_HOST}"
echo "Port:            ${PORT}"
echo "Workspace:       ${WORKSPACE_DIR}"
echo "Preview Tunnels: On-demand only ('preview tunnel <port>')"

# Start preview monitor in background to detect listening development servers
if [ -f "$(dirname "$0")/preview-monitor.sh" ]; then
    "$(dirname "$0")/preview-monitor.sh" > /tmp/preview-monitor.log 2>&1 &
    PREVIEW_MONITOR_PID=$!
fi

# Launch DeepSeek Harness Web UI
dsh web \
    --no-open \
    --host "${BIND_HOST}" \
    --port "${PORT}" \
    --public-url "http://${ACCESS_HOST}:${PORT}" \
    "${TRUSTED_ARGS[@]}" \
    > "${DSH_LOG}" 2>&1 &
DSH_PID=$!

# Wait for Harness to output the authenticated URL
echo "Waiting for DeepSeek Harness Web UI to be ready..."
sleep 3
FINAL_WEB_URL=""
for i in $(seq 1 45); do
    if ! kill -0 "${DSH_PID}" 2>/dev/null; then
        echo "❌ DeepSeek Harness process exited. Logs:" >&2
        cat "${DSH_LOG}" >&2
        if [ "${BIND_HOST}" != "127.0.0.1" ]; then
            echo "Attempting fallback bind to 127.0.0.1..."
            BIND_HOST="127.0.0.1"
            tailscale serve --bg --set-path / "http://127.0.0.1:${PORT}" 2>/dev/null || true
            dsh web \
                --no-open \
                --host "127.0.0.1" \
                --port "${PORT}" \
                --public-url "http://${ACCESS_HOST}:${PORT}" \
                "${TRUSTED_ARGS[@]}" \
                > "${DSH_LOG}" 2>&1 &
            DSH_PID=$!
            sleep 3
            continue
        fi
        exit 1
    fi

    if grep -q -i "dsh web:" "${DSH_LOG}" 2>/dev/null; then
        RAW_URL=$(grep -i "dsh web:" "${DSH_LOG}" | head -n 1 | sed -E 's/.*dsh web:[[:space:]]*//')
        if [ -n "${RAW_URL}" ]; then
            FINAL_WEB_URL="${RAW_URL}"
            break
        fi
    fi
    sleep 1
done

if [ -z "${FINAL_WEB_URL}" ]; then
    FINAL_WEB_URL="http://${ACCESS_HOST}:${PORT}"
fi

echo ""
echo "================================================================================"
echo "🎉 DEEPSEEK HARNESS WEB UI IS ONLINE"
echo "================================================================================"
echo ""
echo "🔗 Access URL:            ${FINAL_WEB_URL}"
echo "📁 Workspace Directory:    ${WORKSPACE_DIR}"
echo "⏱️ Session Duration:       ${SESSION_DURATION_MINUTES} minutes"
echo "🔄 Persistence:            Auto-syncing to gdrive:cloud-dev/workspace every 5m"
echo ""
echo "🌐 Website Previews:"
echo "   - Run dev server:       npm run dev -- --host 0.0.0.0"
echo "   - On-demand Tunnel:     preview tunnel <port> (e.g. preview tunnel 5173)"
echo "   - List active:          preview list"
echo "================================================================================"
echo ""

# Write to GitHub Step Summary
if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
    {
        echo "## 🚀 DeepSeek Harness Cloud Environment"
        echo ""
        echo "### 🤖 DeepSeek Harness Access"
        echo "- **Web UI URL:** [${FINAL_WEB_URL}](${FINAL_WEB_URL})"
        echo ""
        echo "```text"
        echo "${FINAL_WEB_URL}"
        echo "```"
        echo ""
        echo "### 🌐 On-Demand Website Preview"
        echo "To create a Cloudflare Quick Tunnel for any running development server, run in terminal or DeepSeek Harness:"
        echo "```bash"
        echo "preview tunnel <port>"
        echo "# Example: preview tunnel 5173"
        echo "```"
        echo ""
        echo "### 📋 Session Details"
        echo "- **Status:** 🟢 Active"
        echo "- **Workspace:** \`${WORKSPACE_DIR}\`"
        echo "- **Google Drive Path:** \`gdrive:cloud-dev/workspace\`"
        echo "- **Auto-sync Interval:** Every 5 minutes"
    } >> "${GITHUB_STEP_SUMMARY}"
fi

# Stream logs in background while monitoring session duration
tail -n 20 -f "${DSH_LOG}" &
TAIL_PID=$!

SESSION_SECONDS=$((SESSION_DURATION_MINUTES * 60))
echo "Session active for ${SESSION_DURATION_MINUTES} minutes (${SESSION_SECONDS}s)..."

START_TIME=$(date +%s)
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ "${ELAPSED}" -ge "${SESSION_SECONDS}" ]; then
        echo "⏰ Session duration of ${SESSION_DURATION_MINUTES} minutes reached. Initiating shutdown..."
        break
    fi

    if ! kill -0 "${DSH_PID}" 2>/dev/null; then
        echo "⚠️ DeepSeek Harness stopped."
        break
    fi

    sleep 10
done

kill "${TAIL_PID}" 2>/dev/null || true
echo "Session loop finished."
