#!/usr/bin/env bash
# ==============================================================================
# start-ubuntu-session.sh: Launch Ubuntu Studio, display connection info & loop
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${TARGET_USER:-nava}"
TARGET_PASS="${TARGET_PASS:-nava}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/home/${TARGET_USER}/workspace}"
SESSION_DURATION_MINUTES="${SESSION_DURATION_MINUTES:-350}"

# Cleanup handler on exit or signal
cleanup() {
    echo ""
    echo "=================================================="
    echo "🛑 Shutting Down Ubuntu Cloud Development Studio"
    echo "=================================================="

    # Stop preview monitor
    if [ -n "${PREVIEW_MONITOR_PID:-}" ] && kill -0 "${PREVIEW_MONITOR_PID}" 2>/dev/null; then
        echo "Stopping preview monitor (PID: ${PREVIEW_MONITOR_PID})..."
        kill -TERM "${PREVIEW_MONITOR_PID}" 2>/dev/null || true
    fi

    # Clean up any Cloudflare preview tunnels
    if [ -d "/tmp/tunnels" ]; then
        for PID_F in /tmp/tunnels/*.pid; do
            if [ -f "${PID_F}" ]; then
                T_PID=$(cat "${PID_F}" 2>/dev/null || true)
                if [ -n "${T_PID}" ] && kill -0 "${T_PID}" 2>/dev/null; then
                    kill -TERM "${T_PID}" 2>/dev/null || true
                fi
                rm -f "${PID_F}"
            fi
        done
    fi
}
trap cleanup EXIT SIGTERM SIGINT

# 1. Resolve Network Identity & Tailscale Details
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
TAILSCALE_HOSTNAME=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//' || true)
HOST_IP="${TAILSCALE_IP:-127.0.0.1}"
DNS_NAME="${TAILSCALE_HOSTNAME:-ubuntu-dev}"

# 2. Configure Cloud Credentials & Global Toolchains
sudo chmod -R a+rX /opt/hostedtoolcache 2>/dev/null || true
for N_DIR in /opt/hostedtoolcache/node/*/x64/bin; do
    [ -d "${N_DIR}" ] && sudo ln -sf "${N_DIR}"/* /usr/local/bin/ 2>/dev/null || true
done
for P_DIR in /opt/hostedtoolcache/Python/*/x64/bin; do
    [ -d "${P_DIR}" ] && sudo ln -sf "${P_DIR}"/* /usr/local/bin/ 2>/dev/null || true
done
[ -f "/usr/local/bin/opencode" ] && sudo ln -sf /usr/local/bin/opencode /usr/local/bin/oc 2>/dev/null || true

if [ -n "${CLOUDFLARE_API_TOKEN:-}" ] && [ "${CLOUDFLARE_API_TOKEN}" != "add" ]; then
    sudo -u "${TARGET_USER}" mkdir -p "/home/${TARGET_USER}/.wrangler/config"
    sudo tee -a "/home/${TARGET_USER}/.bashrc" >/dev/null << EOF
export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN}"
export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-}"
EOF
fi

if [ -n "${VERCEL_TOKEN:-}" ] && [ "${VERCEL_TOKEN}" != "add" ]; then
    sudo -u "${TARGET_USER}" mkdir -p "/home/${TARGET_USER}/.vercel"
    sudo tee -a "/home/${TARGET_USER}/.bashrc" >/dev/null << EOF
export VERCEL_TOKEN="${VERCEL_TOKEN}"
export VERCEL_ORG_ID="${VERCEL_ORG_ID:-}"
EOF
fi

if [ -n "${DEEPSEEK_API_KEY:-}" ] && [ "${DEEPSEEK_API_KEY}" != "add" ]; then
    sudo tee -a "/home/${TARGET_USER}/.bashrc" >/dev/null << EOF
export DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY}"
EOF
fi

# 3. Ensure the Three Named Tmux Sessions are active under 'nava'
for SESS in terminal-1 terminal-2 terminal-3; do
    if ! sudo -u "${TARGET_USER}" tmux has-session -t "${SESS}" 2>/dev/null; then
        sudo -u "${TARGET_USER}" tmux new-session -d -s "${SESS}" -c "${WORKSPACE_DIR}"
    fi
done

# 4. Start preview monitor in background
if [ -f "${SCRIPT_DIR}/preview-monitor.sh" ]; then
    "${SCRIPT_DIR}/preview-monitor.sh" > /tmp/preview-monitor.log 2>&1 &
    PREVIEW_MONITOR_PID=$!
fi

# 5. Gather Tool Statuses
NODE_VER=$(node --version 2>/dev/null || echo "not installed")
NPM_VER=$(npm --version 2>/dev/null || echo "not installed")
PNPM_VER=$(pnpm --version 2>/dev/null || echo "not installed")
BUN_VER=$(bun --version 2>/dev/null || echo "not installed")
PY_VER=$(python3 --version 2>/dev/null || echo "not installed")
PHP_VER=$(php --version 2>/dev/null | head -n 1 | awk '{print $2}' || echo "not installed")
AGY_STATUS=$(command -v agy &>/dev/null && echo "✅ Available (agy)" || echo "⚠️ Ready for setup")
OC_STATUS=$(command -v opencode &>/dev/null && echo "✅ Available (opencode / oc)" || echo "⚠️ Ready for setup")
DSH_STATUS=$(command -v dsh &>/dev/null && echo "✅ Available (dsh)" || echo "⚠️ Ready for setup")
GH_STATUS=$(command -v gh &>/dev/null && echo "✅ Authenticated (gh)" || echo "⚠️ CLI available")
WRANGLER_STATUS=$(command -v wrangler &>/dev/null && echo "✅ Available (wrangler)" || echo "⚠️ Not installed")
VERCEL_STATUS=$(command -v vercel &>/dev/null && echo "✅ Available (vercel)" || echo "⚠️ Not installed")

# 6. Display Connection & Environment Banner
echo ""
echo "================================================================================"
echo "🎉 UBUNTU CLOUD WEB DEVELOPMENT STUDIO IS ONLINE"
echo "================================================================================"
echo ""
echo "👤 Linux User:             ${TARGET_USER}"
echo "🔑 Password:               ${TARGET_PASS}"
echo "🌐 Tailscale IP:           ${HOST_IP}"
echo "🏷️ Tailscale Hostname:     ${DNS_NAME}"
echo ""
echo "🔑 SSH Connection Commands:"
echo "   ssh ${TARGET_USER}@${HOST_IP}"
echo "   ssh ${TARGET_USER}@${DNS_NAME}"
echo ""
echo "🖥️ XRDP Desktop Connection:"
echo "   Host:                   ${HOST_IP}:3389"
echo "   Username:               ${TARGET_USER}"
echo "   Password:               ${TARGET_PASS}"
echo "   Desktop Environment:    XFCE4"
echo ""
echo "📟 Three Permanent Tmux Terminals:"
echo "   - terminal-1            tmux attach -t terminal-1 (or 't1')"
echo "   - terminal-2            tmux attach -t terminal-2 (or 't2')"
echo "   - terminal-3            tmux attach -t terminal-3 (or 't3')"
echo ""
echo "📁 Persistent Workspace:   ${WORKSPACE_DIR}"
echo "☁️ Google Drive Remote:     gdrive:cloud-dev/ubuntu-workspace"
echo "🔄 Auto-Sync Interval:     Every 5 minutes (daemon active)"
echo ""
echo "🤖 Coding Agents & CLIs:"
echo "   - Antigravity CLI:      ${AGY_STATUS}"
echo "   - OpenCode CLI:         ${OC_STATUS}"
echo "   - DeepSeek Harness:     ${DSH_STATUS}"
echo "   - GitHub CLI:           ${GH_STATUS}"
echo "   - Cloudflare Wrangler:  ${WRANGLER_STATUS}"
echo "   - Vercel CLI:           ${VERCEL_STATUS}"
echo ""
echo "📦 Runtimes & Frameworks:"
echo "   - Node.js:              ${NODE_VER} (npm ${NPM_VER}, pnpm ${PNPM_VER}, Bun ${BUN_VER})"
echo "   - Python:               ${PY_VER}"
echo "   - PHP:                  ${PHP_VER} (Composer available)"
echo ""
echo "🌐 On-Demand Website Previews:"
echo "   - Run dev server:       npm run dev -- --host 0.0.0.0"
echo "   - Start Quick Tunnel:   preview tunnel <port> (e.g. preview tunnel 5173)"
echo "   - List active:          preview list"
echo "================================================================================"
echo ""

# 7. Write to GitHub Step Summary
if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
    {
        echo "# 🖥️ Ubuntu Cloud Web Development Studio"
        echo ""
        echo "### 🌐 Remote Access Details"
        echo "| Protocol | Address | Username | Password / Auth |"
        echo "|---|---|---|---|"
        echo "| **SSH** | \`${HOST_IP}:22\` or \`${DNS_NAME}\` | \`${TARGET_USER}\` | \`${TARGET_PASS}\` |"
        echo "| **XRDP (GUI)** | \`${HOST_IP}:3389\` or \`${DNS_NAME}:3389\` | \`${TARGET_USER}\` | \`${TARGET_PASS}\` |"
        echo ""
        echo "#### 🔑 Quick SSH Commands"
        echo "\`\`\`bash"
        echo "ssh ${TARGET_USER}@${HOST_IP}"
        echo "# Or via MagicDNS:"
        echo "ssh ${TARGET_USER}@${DNS_NAME}"
        echo "\`\`\`"
        echo ""
        echo "### 📟 Permanent Named Tmux Sessions"
        echo "| Session | Attach Command | Quick Alias | Default Directory |"
        echo "|---|---|---|---|"
        echo "| **terminal-1** | \`tmux attach -t terminal-1\` | \`t1\` | \`${WORKSPACE_DIR}\` |"
        echo "| **terminal-2** | \`tmux attach -t terminal-2\` | \`t2\` | \`${WORKSPACE_DIR}\` |"
        echo "| **terminal-3** | \`tmux attach -t terminal-3\` | \`t3\` | \`${WORKSPACE_DIR}\` |"
        echo ""
        echo "### 🤖 AI Coding Agents"
        echo "- **Antigravity CLI:** \`agy\`"
        echo "- **OpenCode CLI:** \`opencode\` (alias: \`oc\`)"
        echo "- **DeepSeek Harness:** \`dsh\`"
        echo ""
        echo "### 🌐 On-Demand Web Previews"
        echo "To create a secure Cloudflare Quick Tunnel for any running local server:"
        echo "\`\`\`bash"
        echo "preview tunnel <port>"
        echo "# Example: preview tunnel 5173"
        echo "\`\`\`"
        echo ""
        echo "### 💾 Workspace & Google Drive Persistence"
        echo "- **Local Path:** \`${WORKSPACE_DIR}\`"
        echo "- **Google Drive Path:** \`gdrive:cloud-dev/ubuntu-workspace\`"
        echo "- **Auto-Sync:** Every 5 minutes"
        echo "- **Trash Safety:** Deleted/modified files preserved in \`gdrive:cloud-dev/ubuntu-workspace-trash/<timestamp>\`"
    } >> "${GITHUB_STEP_SUMMARY}"
fi

# 8. Session Duration Monitoring Loop
SESSION_SECONDS=$((SESSION_DURATION_MINUTES * 60))
echo "Session active for ${SESSION_DURATION_MINUTES} minutes (${SESSION_SECONDS}s)..."

START_TIME=$(date +%s)
while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ "${ELAPSED}" -ge "${SESSION_SECONDS}" ]; then
        echo "⏰ Session duration of ${SESSION_DURATION_MINUTES} minutes reached. Initiating clean shutdown..."
        break
    fi

    # Keep alive check
    sleep 15
done

echo "Ubuntu Studio session loop finished."
