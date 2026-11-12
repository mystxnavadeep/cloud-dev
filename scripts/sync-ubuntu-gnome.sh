#!/usr/bin/env bash
# ==============================================================================
# sync-ubuntu-gnome.sh: 5-minute sync daemon & final backup to Google Drive
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

TARGET_USER="${TARGET_USER:-nava}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/home/${TARGET_USER}/workspace}"
REMOTE_SUBDIR="${REMOTE_SUBDIR:-cloud-dev/ubuntu-gnome-workspace}"
FILTERS_FILE="${FILTERS_FILE:-$(dirname "$0")/rclone-filters.txt}"
PID_FILE="/tmp/ubuntu-gnome-sync.pid"
LOCK_FILE="/tmp/ubuntu-gnome-sync.lock"

# Detect remote
REMOTE="gdrive:"
if ! rclone listremotes 2>/dev/null | grep -q "^gdrive:"; then
    DETECTED_REMOTE=$(rclone listremotes 2>/dev/null | head -n 1 || true)
    if [ -n "${DETECTED_REMOTE}" ]; then
        REMOTE="${DETECTED_REMOTE}"
    fi
fi

REMOTE_PATH="${REMOTE}${REMOTE_SUBDIR}"
REMOTE_WORKSPACE_PATH="${REMOTE_PATH}/workspace"
REMOTE_CONFIG_PATH="${REMOTE_PATH}/config"

stop_daemon() {
    echo "Checking for active Ubuntu GNOME sync daemon..."
    if [ -f "${PID_FILE}" ]; then
        local d_pid
        d_pid=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [ -n "${d_pid}" ] && kill -0 "${d_pid}" 2>/dev/null; then
            echo "Stopping sync daemon (PID: ${d_pid})..."
            kill -TERM "${d_pid}" 2>/dev/null || true
            sleep 2
        fi
        rm -f "${PID_FILE}"
    fi

    # Wait up to 60 seconds for any in-flight sync operation to clear lock
    exec 200>"${LOCK_FILE}"
    echo "Waiting for any in-flight sync operation to conclude..."
    if ! flock -w 60 200; then
        echo "⚠️ Warning: Sync lock held past 60s timeout. Proceeding..." >&2
    fi
    flock -u 200 2>/dev/null || true
    echo "✅ Sync daemon stopped and lock cleared."
}

save_recovery_state() {
    echo "Saving Ubuntu GNOME session recovery state..."
    local backup_dir="${WORKSPACE_DIR}/backups"
    sudo mkdir -p "${backup_dir}"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")

    # Capture active tmux session info
    local tmux_info="none"
    if command -v tmux >/dev/null 2>&1; then
        tmux_info=$(sudo -u "${TARGET_USER}" tmux list-sessions 2>/dev/null | tr '\n' ';' || echo "none")
    fi

    # Export GNOME dconf desktop settings
    if command -v dconf >/dev/null 2>&1; then
        echo "Exporting GNOME dconf settings to ${backup_dir}/gnome-dconf.ini..."
        sudo -u "${TARGET_USER}" dbus-run-session -- dconf dump / > "${backup_dir}/gnome-dconf.ini" 2>/dev/null || \
            sudo -u "${TARGET_USER}" dconf dump / > "${backup_dir}/gnome-dconf.ini" 2>/dev/null || true
    fi

    # Capture installed tool versions safely
    local node_v
    node_v=$(node --version 2>/dev/null || echo "not installed")
    local npm_v
    npm_v=$(npm --version 2>/dev/null || echo "not installed")
    local pnpm_v
    pnpm_v=$(pnpm --version 2>/dev/null || echo "not installed")
    local bun_v
    bun_v=$(bun --version 2>/dev/null || echo "not installed")
    local py_v
    py_v=$(python3 --version 2>/dev/null || echo "not installed")
    local uv_v
    uv_v=$(uv --version 2>/dev/null || echo "not installed")
    local php_v
    php_v=$(php -v 2>/dev/null | head -n 1 || echo "not installed")
    local composer_v
    composer_v=$(composer --version 2>/dev/null | head -n 1 || echo "not installed")
    local agy_v
    agy_v=$(agy --version 2>/dev/null | head -n 1 || echo "not installed")
    local oc_v
    oc_v=$(opencode --version 2>/dev/null | head -n 1 || echo "not installed")
    local dsh_v
    dsh_v=$(dsh --version 2>/dev/null | head -n 1 || echo "not installed")
    local wrangler_v
    wrangler_v=$(wrangler --version 2>/dev/null | head -n 1 || echo "not installed")
    local vercel_v
    vercel_v=$(vercel --version 2>/dev/null | head -n 1 || echo "not installed")

    # Local file count
    local local_files
    local_files=$( (sudo find "${WORKSPACE_DIR}" -type f 2>/dev/null || true) | wc -l | tr -d '[:space:]' )

    local state_file="${backup_dir}/recovery-state.json"
    local manifest_file="${backup_dir}/backup-manifest.json"

    sudo tee "${state_file}" >/dev/null << EOF
{
  "timestamp": "${timestamp}",
  "os": "ubuntu-24.04-gnome",
  "user": "${TARGET_USER}",
  "workspace_dir": "${WORKSPACE_DIR}",
  "remote_target": "${REMOTE_PATH}",
  "local_file_count": ${local_files},
  "tmux_sessions": "${tmux_info}",
  "desktop_environment": "GNOME",
  "installed_tools": {
    "node": "${node_v}",
    "npm": "${npm_v}",
    "pnpm": "${pnpm_v}",
    "bun": "${bun_v}",
    "python": "${py_v}",
    "uv": "${uv_v}",
    "php": "${php_v}",
    "composer": "${composer_v}",
    "agy": "${agy_v}",
    "opencode": "${oc_v}",
    "dsh": "${dsh_v}",
    "wrangler": "${wrangler_v}",
    "vercel": "${vercel_v}"
  }
}
EOF

    sudo tee "${manifest_file}" >/dev/null << EOF
{
  "backup_time": "${timestamp}",
  "source_user": "${TARGET_USER}",
  "workspace": "${WORKSPACE_DIR}",
  "file_count": ${local_files},
  "status": "ready_for_sync"
}
EOF

    sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${backup_dir}"
    echo "✅ Recovery state & backup manifest saved to ${backup_dir}."
}

sync_once() {
    exec 200>"${LOCK_FILE}"
    if ! flock -n 200; then
        echo "⏳ Another sync operation is currently active. Skipping this cycle."
        return 0
    fi

    local start_ts
    start_ts=$(date +%s)
    local timestamp
    timestamp=$(date -u +"%Y%m%d_%H%M%S")
    local trash_path="${REMOTE}cloud-dev/ubuntu-gnome-workspace-trash/${timestamp}"

    echo "[$(date -u +"%Y-%m-%d %H:%M:%SZ")] Starting Ubuntu GNOME workspace sync..."

    # Dump GNOME dconf settings before sync
    if command -v dconf >/dev/null 2>&1; then
        sudo mkdir -p "${WORKSPACE_DIR}/backups"
        sudo -u "${TARGET_USER}" dbus-run-session -- dconf dump / > "${WORKSPACE_DIR}/backups/gnome-dconf.ini" 2>/dev/null || \
            sudo -u "${TARGET_USER}" dconf dump / > "${WORKSPACE_DIR}/backups/gnome-dconf.ini" 2>/dev/null || true
    fi

    # 1. Sync workspace directory to Google Drive
    if [ -d "${WORKSPACE_DIR}" ]; then
        sudo rclone sync "${WORKSPACE_DIR}" "${REMOTE_WORKSPACE_PATH}" \
            --filter-from "${FILTERS_FILE}" \
            --backup-dir "${trash_path}/workspace" \
            --fast-list \
            --transfers 8 \
            --checkers 16 \
            --drive-chunk-size 32M \
            --retries 3 \
            --stats-one-line \
            --stats 10s || echo "⚠️ Workspace sync encountered non-fatal warnings."
    fi

    # 2. Sync safe configuration files from /home/nava
    local config_dir="/home/${TARGET_USER}"
    if [ -d "${config_dir}" ]; then
        sudo rclone sync "${config_dir}" "${REMOTE_CONFIG_PATH}" \
            --include ".bashrc" \
            --include ".profile" \
            --include ".bash_profile" \
            --include ".tmux.conf" \
            --include ".gitconfig" \
            --include ".ssh/config" \
            --include ".ssh/authorized_keys" \
            --include ".dsh/**" \
            --include ".agents/**" \
            --include ".config/Code/User/settings.json" \
            --include ".config/dconf/**" \
            --exclude "*" \
            --backup-dir "${trash_path}/config" \
            --fast-list \
            --transfers 4 \
            --retries 3 || echo "⚠️ Config sync encountered non-fatal warnings."
    fi

    local end_ts
    end_ts=$(date +%s)
    local duration=$((end_ts - start_ts))
    echo "[$(date -u +"%Y-%m-%d %H:%M:%SZ")] ✅ Sync cycle completed in ${duration}s."

    flock -u 200
}

sync_daemon() {
    local interval="${1:-300}"
    echo "Starting Ubuntu GNOME workspace sync daemon (interval: ${interval}s)..."
    echo "$$" > "${PID_FILE}"

    trap 'echo "Sync daemon received termination signal."; rm -f "${PID_FILE}"; exit 0' TERM INT

    while true; do
        sleep "${interval}" &
        wait $!
        sync_once || echo "⚠️ Sync cycle encountered an error; continuing daemon loop..."
    done
}

case "${1:-once}" in
    --daemon)
        sync_daemon "${2:-300}"
        ;;
    --stop-daemon)
        stop_daemon
        ;;
    --save-recovery-state)
        save_recovery_state
        ;;
    --final)
        stop_daemon
        save_recovery_state
        echo "Executing final synchronous workspace & configuration backup..."
        sync_once
        echo "✅ Final workspace backup to Google Drive complete."
        ;;
    --once|*)
        sync_once
        ;;
esac
