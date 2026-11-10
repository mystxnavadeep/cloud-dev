#!/usr/bin/env bash
# ==============================================================================
# restore-ubuntu-workspace.sh: Restore persistent workspace & configs for 'nava'
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

TARGET_USER="${TARGET_USER:-nava}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/home/${TARGET_USER}/workspace}"
REMOTE_SUBDIR="${REMOTE_SUBDIR:-cloud-dev/ubuntu-workspace}"
FILTERS_FILE="${FILTERS_FILE:-$(dirname "$0")/rclone-filters.txt}"

echo "=================================================="
echo "🔄 Restoring Ubuntu Workspace from Google Drive"
echo "=================================================="
echo "Target User:     ${TARGET_USER}"
echo "Local Workspace: ${WORKSPACE_DIR}"
echo "Remote Subdir:   ${REMOTE_SUBDIR}"

# 1. Install & configure rclone if needed
if ! command -v rclone &>/dev/null; then
    echo "Installing rclone..."
    curl -fsSL https://rclone.org/install.sh | sudo bash
fi

if [ -n "${RCLONE_CONFIG_B64:-}" ]; then
    mkdir -p "${HOME}/.config/rclone"
    sudo mkdir -p "/home/${TARGET_USER}/.config/rclone" "/root/.config/rclone"
    echo "${RCLONE_CONFIG_B64}" | base64 -d > "${HOME}/.config/rclone/rclone.conf"
    sudo cp "${HOME}/.config/rclone/rclone.conf" "/home/${TARGET_USER}/.config/rclone/rclone.conf"
    sudo cp "${HOME}/.config/rclone/rclone.conf" "/root/.config/rclone/rclone.conf"
    chmod 600 "${HOME}/.config/rclone/rclone.conf"
    sudo chmod 600 "/home/${TARGET_USER}/.config/rclone/rclone.conf" "/root/.config/rclone/rclone.conf"
    sudo chown -R "${TARGET_USER}:${TARGET_USER}" "/home/${TARGET_USER}/.config"
fi

if [ ! -f "${HOME}/.config/rclone/rclone.conf" ]; then
    echo "❌ Error: rclone configuration not found. Please provide 'RCLONE_CONFIG_B64' secret." >&2
    exit 1
fi

# Detect remote
REMOTE="gdrive:"
if ! rclone listremotes | grep -q "^gdrive:"; then
    DETECTED_REMOTE=$(rclone listremotes | head -n 1 || true)
    if [ -n "${DETECTED_REMOTE}" ]; then
        REMOTE="${DETECTED_REMOTE}"
    fi
fi

REMOTE_PATH="${REMOTE}${REMOTE_SUBDIR}"
echo "Using Google Drive Remote: ${REMOTE_PATH}"

# Test Google Drive connection
if ! rclone lsf "${REMOTE}" --max-depth 1 >/dev/null 2>&1; then
    echo "❌ Error: Failed to connect to Google Drive remote '${REMOTE}'. Verify credentials." >&2
    exit 1
fi
echo "✅ Google Drive connection verified."

sudo mkdir -p "${WORKSPACE_DIR}"

# 2. Check for existing remote backup
REMOTE_WORKSPACE_PATH="${REMOTE_PATH}/workspace"
REMOTE_CONFIG_PATH="${REMOTE_PATH}/config"

REMOTE_FILE_COUNT=$(rclone lsf "${REMOTE_WORKSPACE_PATH}" --recursive --files-only 2>/dev/null | wc -l || echo 0)

if [ "${REMOTE_FILE_COUNT}" -gt 0 ]; then
    echo "📦 Found existing workspace backup (${REMOTE_FILE_COUNT} files). Restoring to '${WORKSPACE_DIR}'..."
    sudo rclone copy "${REMOTE_WORKSPACE_PATH}" "${WORKSPACE_DIR}" \
        --filter-from "${FILTERS_FILE}" \
        --fast-list \
        --transfers 8 \
        --checkers 16 \
        --drive-chunk-size 32M \
        --retries 3 \
        --stats-one-line \
        --stats 5s

    # Restore safe user configuration if present
    CONFIG_COUNT=$(rclone lsf "${REMOTE_CONFIG_PATH}" --recursive --files-only 2>/dev/null | wc -l || echo 0)
    if [ "${CONFIG_COUNT}" -gt 0 ]; then
        echo "🔧 Restoring safe user configurations from '${REMOTE_CONFIG_PATH}'..."
        sudo rclone copy "${REMOTE_CONFIG_PATH}" "/home/${TARGET_USER}" \
            --filter-from "${FILTERS_FILE}" \
            --fast-list \
            --retries 3 || true
    fi

    LOCAL_FILE_COUNT=$(find "${WORKSPACE_DIR}" -type f 2>/dev/null | wc -l || echo 0)
    echo "✅ Workspace restored successfully (${LOCAL_FILE_COUNT} local files present)."
    echo "${LOCAL_FILE_COUNT}" > /tmp/.ubuntu_workspace_restored

    if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
        {
            echo "### 🔄 Ubuntu Workspace Restoration Summary"
            echo "- **Status:** ✅ Successfully Restored from Google Drive"
            echo "- **Remote Path:** \`${REMOTE_PATH}\`"
            echo "- **Local Path:** \`${WORKSPACE_DIR}\`"
            echo "- **Files Restored:** ${LOCAL_FILE_COUNT}"
        } >> "${GITHUB_STEP_SUMMARY}"
    fi
else
    echo "🌱 First run / clean state detected at '${REMOTE_PATH}'."
    echo "Initializing new development studio folders..."

    sudo mkdir -p \
        "${WORKSPACE_DIR}/projects" \
        "${WORKSPACE_DIR}/web" \
        "${WORKSPACE_DIR}/frontend" \
        "${WORKSPACE_DIR}/backend" \
        "${WORKSPACE_DIR}/apis" \
        "${WORKSPACE_DIR}/deployments" \
        "${WORKSPACE_DIR}/scripts" \
        "${WORKSPACE_DIR}/downloads" \
        "${WORKSPACE_DIR}/backups" \
        "${WORKSPACE_DIR}/tmp"

    # Create detailed WELCOME.md
    if [ ! -f "${WORKSPACE_DIR}/WELCOME.md" ]; then
        sudo tee "${WORKSPACE_DIR}/WELCOME.md" >/dev/null << 'EOF'
# Welcome to Your Ubuntu Cloud Web Development Studio! ☁️🖥️

Welcome **nava**! This is your persistent personal cloud workstation running on Ubuntu with full XFCE GUI, XRDP, OpenSSH, Tailscale, tmux, and modern Web Development Tools.

---

### 📂 Workspace Structure
- `~/workspace/projects` — General coding and software projects
- `~/workspace/web` — Web applications (HTML, CSS, JS, frameworks)
- `~/workspace/frontend` — React, Next.js, Vite, Vue, Svelte, Tailwind
- `~/workspace/backend` — Node.js, Express, Fastify, FastAPI, Django, PHP
- `~/workspace/apis` — REST & GraphQL APIs, microservices
- `~/workspace/deployments` — Cloudflare, Vercel, Docker configs
- `~/workspace/scripts` — Custom automation utilities
- `~/workspace/downloads` — Downloaded assets
- `~/workspace/backups` — Workspace archives

---

### 🖥️ Persistent Named Tmux Sessions
Your 3 permanently named terminals stay alive even if you disconnect SSH:
1. `terminal-1` -> Attach via `tmux attach -t terminal-1` (or alias `t1`)
2. `terminal-2` -> Attach via `tmux attach -t terminal-2` (or alias `t2`)
3. `terminal-3` -> Attach via `tmux attach -t terminal-3` (or alias `t3`)
- List sessions anytime with `tls`

---

### 🤖 Installed AI Coding Assistants
- **Google Antigravity CLI**: `agy`
- **OpenCode CLI**: `opencode` (or shortcut `oc`)
- **DeepSeek Harness**: `dsh`

---

### 🌐 Previewing Local Development Servers
- Start your development server listening on `0.0.0.0` (e.g. `npm run dev -- --host 0.0.0.0` or `vite --host`).
- Create an on-demand Cloudflare Quick Tunnel:
  ```bash
  preview tunnel 5173
  ```
- List active tunnels: `preview list`

---

### 💾 Automatic Google Drive Persistence
- **Auto-Sync**: Your files are automatically synchronized to Google Drive every 5 minutes.
- **Safety**: Modified/deleted files are archived in `gdrive:cloud-dev/ubuntu-workspace-trash/<timestamp>` so work is never lost.
- **Next Session**: All files, configs, and supported states will be restored automatically on your next run.
EOF
    fi

    rclone mkdir "${REMOTE_WORKSPACE_PATH}" || true
    echo "initial" > /tmp/.ubuntu_workspace_restored
    echo "✅ Clean workspace initialized."

    if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
        {
            echo "### 🔄 Ubuntu Workspace Restoration Summary"
            echo "- **Status:** 🌱 Clean Workspace Initialized"
            echo "- **Remote Path:** \`${REMOTE_PATH}\`"
            echo "- **Local Path:** \`${WORKSPACE_DIR}\`"
        } >> "${GITHUB_STEP_SUMMARY}"
    fi
fi

# 3. Ensure permissions and ownership for user 'nava'
sudo chown -R "${TARGET_USER}:${TARGET_USER}" "/home/${TARGET_USER}"
sudo chmod 755 "/home/${TARGET_USER}"
sudo chmod 700 "/home/${TARGET_USER}/.ssh" 2>/dev/null || true
if [ -f "/home/${TARGET_USER}/.ssh/authorized_keys" ]; then
    sudo chmod 600 "/home/${TARGET_USER}/.ssh/authorized_keys" || true
fi

# Ensure .dsh permissions (assertOwnerOnlyAccess strict requirement)
sudo mkdir -p "${WORKSPACE_DIR}/.dsh" "${WORKSPACE_DIR}/.agents" "/home/${TARGET_USER}/.dsh"
sudo chmod -R 700 "${WORKSPACE_DIR}/.dsh" "/home/${TARGET_USER}/.dsh" 2>/dev/null || true
sudo find "${WORKSPACE_DIR}/.dsh" "/home/${TARGET_USER}/.dsh" -type f -exec chmod 600 {} + 2>/dev/null || true
sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${WORKSPACE_DIR}/.dsh" "${WORKSPACE_DIR}/.agents" "/home/${TARGET_USER}/.dsh"

echo "=================================================="
echo "✅ Workspace & Configuration Restore Complete"
echo "=================================================="
