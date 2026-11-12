#!/usr/bin/env bash
# ==============================================================================
# start-ubuntu-gnome-session.sh: Launch Ubuntu GNOME PC, display connection info & loop
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${TARGET_USER:-nava}"
TARGET_PASS="${TARGET_PASS:-nava}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/home/${TARGET_USER}/workspace}"
SESSION_DURATION_MINUTES="${SESSION_DURATION_MINUTES:-340}"
if [ "${SESSION_DURATION_MINUTES}" -gt 345 ]; then
    echo "⚠️ Warning: Requested duration (${SESSION_DURATION_MINUTES}m) exceeds safe 6-hour runner limit. Capping at 345m."
    SESSION_DURATION_MINUTES=345
fi

# Cleanup handler on exit or signal
cleanup() {
    echo ""
    echo "=================================================="
    echo "🛑 Shutting Down Ubuntu GNOME Cloud PC Session"
    echo "=================================================="

    # Stop preview monitor if running
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
DNS_NAME="${TAILSCALE_HOSTNAME:-ubuntu-gnome}"

# 2. Configure Cloud Credentials & Global Toolchains
sudo chmod -R a+rX /opt/hostedtoolcache 2>/dev/null || true
sudo chmod 755 /home/runner 2>/dev/null || true
for N_DIR in /opt/hostedtoolcache/node/*/x64/bin; do
    [ -d "${N_DIR}" ] && sudo ln -sf "${N_DIR}"/* /usr/local/bin/ 2>/dev/null || true
done
for P_DIR in /opt/hostedtoolcache/Python/*/x64/bin; do
    [ -d "${P_DIR}" ] && sudo ln -sf "${P_DIR}"/* /usr/local/bin/ 2>/dev/null || true
done

# Ensure Bun is in /usr/local/bin
sudo rm -f /usr/local/bin/bun
for BUN_PATH in "${HOME}/.bun/bin/bun" "/home/runner/.bun/bin/bun" "/root/.bun/bin/bun"; do
    if [ -f "${BUN_PATH}" ]; then
        sudo cp -f "${BUN_PATH}" /usr/local/bin/bun || true
        sudo chmod 755 /usr/local/bin/bun || true
        sudo chown root:root /usr/local/bin/bun || true
        break
    fi
done

# Ensure uv & uvx are in /usr/local/bin
for UV_PATH in /usr/local/bin/uv "${HOME}/.local/bin/uv" "/home/runner/.local/bin/uv" "${HOME}/.cargo/bin/uv"; do
    if [ -f "${UV_PATH}" ] && [ ! -x /usr/local/bin/uv ]; then
        sudo cp -f "${UV_PATH}" /usr/local/bin/uv || true
        sudo chmod 755 /usr/local/bin/uv || true
        sudo chown root:root /usr/local/bin/uv || true
        break
    fi
done
for UVX_PATH in /usr/local/bin/uvx "${HOME}/.local/bin/uvx" "/home/runner/.local/bin/uvx" "${HOME}/.cargo/bin/uvx"; do
    if [ -f "${UVX_PATH}" ] && [ ! -x /usr/local/bin/uvx ]; then
        sudo cp -f "${UVX_PATH}" /usr/local/bin/uvx || true
        sudo chmod 755 /usr/local/bin/uvx || true
        sudo chown root:root /usr/local/bin/uvx || true
        break
    fi
done

# Ensure Antigravity CLI is in /usr/local/bin
for AGY_PATH in "${HOME}/.local/bin/agy" "/root/.local/bin/agy" "/home/runner/.local/bin/agy"; do
    if [ -f "${AGY_PATH}" ] && [ ! -f "/usr/local/bin/agy" ]; then
        sudo cp -f "${AGY_PATH}" /usr/local/bin/agy || true
        sudo chmod 755 /usr/local/bin/agy || true
        break
    fi
done
[ -f "/usr/local/bin/agy" ] && sudo chmod 755 /usr/local/bin/agy 2>/dev/null || true

# Ensure OpenCode CLI wrapper is in /usr/local/bin
if ! command -v opencode >/dev/null 2>&1; then
    for OC_PATH in "${HOME}/.local/bin/opencode" "/root/.local/bin/opencode" "/home/runner/.local/bin/opencode"; do
        if [ -f "${OC_PATH}" ]; then
            sudo cp -f "${OC_PATH}" /usr/local/bin/opencode || true
            sudo chmod 755 /usr/local/bin/opencode || true
            break
        fi
    done
fi
sudo ln -sf /usr/local/bin/opencode /usr/local/bin/oc 2>/dev/null || true

# Ensure DeepSeek Harness CLI is in /usr/local/bin
if [ -f "/opt/deepseek-harness/dist/cli.js" ]; then
    sudo tee /usr/local/bin/dsh >/dev/null << 'EOF'
#!/usr/bin/env bash
exec node /opt/deepseek-harness/dist/cli.js "$@"
EOF
    sudo chmod 755 /usr/local/bin/dsh
fi

# Ensure 3 permanent named tmux sessions exist under 'nava'
for SESS in terminal-1 terminal-2 terminal-3; do
    if ! sudo -u "${TARGET_USER}" tmux has-session -t "${SESS}" 2>/dev/null; then
        sudo -u "${TARGET_USER}" tmux new-session -d -s "${SESS}" -c "${WORKSPACE_DIR}" 2>/dev/null || true
    fi
done

# Ensure user directory ownership
sudo chown -R "${TARGET_USER}:${TARGET_USER}" "/home/${TARGET_USER}" 2>/dev/null || true

# 3. Print Connection Banner
echo ""
echo "================================================================================"
echo "🖥️  UBUNTU GNOME CLOUD PC IS ONLINE & READY"
echo "================================================================================"
echo "Tailscale IP:      ${HOST_IP}"
echo "Tailscale Host:    ${DNS_NAME}"
echo "Desktop GUI:       GNOME Shell (XRDP port 3389)"
echo "SSH Access:        Port 22"
echo "User:              ${TARGET_USER}"
echo "Password:          ${TARGET_PASS}"
echo "Persistent Path:   ${WORKSPACE_DIR}"
echo "Google Drive:      gdrive:cloud-dev/ubuntu-gnome-workspace"
echo "Safe Budget:       ${SESSION_DURATION_MINUTES} minutes (~$((SESSION_DURATION_MINUTES / 60))h $((SESSION_DURATION_MINUTES % 60))m)"
echo "--------------------------------------------------------------------------------"
echo "CONNECT VIA GUI (XRDP / Remote Desktop):"
echo "  Address:         ${HOST_IP}:3389  (or ${DNS_NAME}:3389)"
echo "  Username:        ${TARGET_USER}"
echo "  Password:        ${TARGET_PASS}"
echo "--------------------------------------------------------------------------------"
echo "CONNECT VIA SSH:"
echo "  ssh ${TARGET_USER}@${HOST_IP}"
echo "  ssh ${TARGET_USER}@${DNS_NAME}"
echo "--------------------------------------------------------------------------------"
echo "PERMANENT TMUX TERMINAL SHORTCUTS:"
echo "  t1               -> Attach to terminal-1"
echo "  t2               -> Attach to terminal-2"
echo "  t3               -> Attach to terminal-3"
echo "  tls              -> List all active tmux sessions"
echo "  ws               -> Navigate to persistent workspace (~/workspace)"
echo "--------------------------------------------------------------------------------"
echo "AI CODING ASSISTANTS & RUNTIMES:"
echo "  agy              -> Google Antigravity CLI"
echo "  opencode (oc)    -> OpenCode AI Assistant"
echo "  dsh              -> DeepSeek Harness CLI"
echo "  node / npm / bun -> JavaScript & TypeScript Runtime"
echo "  python3 / uv     -> Python 3 Runtime & Astral uv package manager"
echo "  php / composer   -> PHP 8.3 & Composer package manager"
echo "  wrangler / vercel-> Cloudflare & Vercel deployment CLIs"
echo "================================================================================"
echo ""

# 4. Generate GitHub Step Summary
if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
    {
        echo "# 🖥️ Ubuntu GNOME Cloud PC is Active"
        echo ""
        echo "### 🌐 Connection Credentials"
        echo "| Property | Value |"
        echo "| :--- | :--- |"
        echo "| **Tailscale IP** | \`${HOST_IP}\` |"
        echo "| **Tailscale Hostname** | \`${DNS_NAME}\` |"
        echo "| **Desktop GUI (XRDP)** | \`${HOST_IP}:3389\` (GNOME Shell) |"
        echo "| **SSH Address** | \`ssh ${TARGET_USER}@${HOST_IP}\` |"
        echo "| **Username** | \`${TARGET_USER}\` |"
        echo "| **Password** | \`${TARGET_PASS}\` (sudo enabled) |"
        echo "| **Workspace** | \`${WORKSPACE_DIR}\` |"
        echo "| **Remote Storage** | \`gdrive:cloud-dev/ubuntu-gnome-workspace\` |"
        echo "| **Safe Session Budget** | ${SESSION_DURATION_MINUTES} minutes |"
        echo ""
        echo "### 🖥️ Persistent Named Tmux Terminals"
        echo "- **Terminal 1:** \`t1\` (tmux attach -t terminal-1)"
        echo "- **Terminal 2:** \`t2\` (tmux attach -t terminal-2)"
        echo "- **Terminal 3:** \`t3\` (tmux attach -t terminal-3)"
        echo "- **List Sessions:** \`tls\`"
        echo "- **Quick Workspace Jump:** \`ws\`"
        echo ""
        echo "### 🤖 AI Coding Assistants & Tools"
        echo "- **Google Antigravity CLI:** \`agy\`"
        echo "- **OpenCode CLI:** \`opencode\` (alias \`oc\`)"
        echo "- **DeepSeek Harness:** \`dsh\`"
        echo "- **Web Toolchain:** Node.js, npm, pnpm, yarn, bun, Vite, Next.js, React, Vue, Svelte, Tailwind"
        echo "- **Python Toolchain:** Python 3, Astral uv, pip, FastAPI, Django, Flask"
        echo "- **PHP Toolchain:** PHP 8.3, Composer"
        echo "- **Cloud CLIs:** Cloudflare Wrangler, Vercel CLI, Firebase, Supabase, Netlify"
        echo ""
        echo "### 💾 Google Drive Persistence"
        echo "- Auto-syncs every 5 minutes in background."
        echo "- Safe graceful shutdown will automatically run final backup before GitHub runner timeout."
    } >> "${GITHUB_STEP_SUMMARY}"
fi

# 5. Session Keep-Alive Loop (Graceful shutdown before 6-hour runner limit)
TOTAL_SECONDS=$((SESSION_DURATION_MINUTES * 60))
START_TIME=$(date +%s)
END_TIME=$((START_TIME + TOTAL_SECONDS))
SLEEP_INTERVAL=300 # 5-minute heartbeat

echo "Keep-alive loop running for ${SESSION_DURATION_MINUTES} minutes..."

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    REMAINING=$((END_TIME - CURRENT_TIME))

    if [ "${REMAINING}" -le 0 ]; then
        echo ""
        echo "⏰ Safe session budget of ${SESSION_DURATION_MINUTES} minutes reached."
        echo "Beginning graceful session shutdown and final Google Drive backup..."
        break
    fi

    ELAPSED_MIN=$((ELAPSED / 60))
    REMAINING_MIN=$((REMAINING / 60))

    # Health check for XRDP and SSH
    XRDP_STATUS="OK"
    if ! ss -tln | grep -q ":3389 "; then
        XRDP_STATUS="DOWN (Restarting)"
        sudo systemctl restart xrdp 2>/dev/null || true
    fi

    SSH_STATUS="OK"
    if ! ss -tln | grep -q ":22 "; then
        SSH_STATUS="DOWN (Restarting)"
        sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd 2>/dev/null || true
    fi

    echo "[$(date -u +"%Y-%m-%d %H:%M:%SZ")] ❤️ Heartbeat: Elapsed: ${ELAPSED_MIN}m | Remaining: ${REMAINING_MIN}m | XRDP: ${XRDP_STATUS} | SSH: ${SSH_STATUS}"

    if [ "${REMAINING}" -lt "${SLEEP_INTERVAL}" ]; then
        sleep "${REMAINING}"
    else
        sleep "${SLEEP_INTERVAL}"
    fi
done

echo "Ubuntu GNOME Cloud PC session completed successfully."
exit 0
