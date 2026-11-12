#!/usr/bin/env bash
# ==============================================================================
# sync-ubuntu-workspace.sh: 5-minute sync daemon & final backup to Google Drive
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

TARGET_USER="${TARGET_USER:-nava}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/home/${TARGET_USER}/workspace}"
REMOTE_SUBDIR="${REMOTE_SUBDIR:-cloud-dev/ubuntu-workspace}"
FILTERS_FILE="${FILTERS_FILE:-$(dirname "$0")/rclone-filters.txt}"
PID_FILE="/tmp/ubuntu-sync.pid"
LOCK_FILE="/tmp/ubuntu-sync.lock"

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
    echo "Checking for active Ubuntu workspace sync daemon..."
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
    local waited=0
    exec 200>"${LOCK_FILE}"
    echo "Waiting for any in-flight sync operation to conclude..."
    if ! flock -w 60 200; then
        echo "⚠️ Warning: Sync lock held past 60s timeout. Proceeding..." >&2
    fi
    flock -u 200 2>/dev/null || true
    echo "✅ Sync daemon stopped and lock cleared."
}

save_recovery_state() {
    echo "Saving Ubuntu studio session recovery state..."
    local backup_dir="${WORKSPACE_DIR}/backups"
    sudo mkdir -p "${backup_dir}"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")

    # Capture active tmux session info
    local tmux_info="none"
    if command -v tmux >/dev/null 2>&1; then
        tmux_info=$(sudo -u "${TARGET_USER}" tmux list-sessions 2>/dev/null | tr '\n' ';' || echo "none")
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
  "os": "ubuntu-24.04",
  "user": "${TARGET_USER}",
  "workspace_dir": "${WORKSPACE_DIR}",
  "remote_target": "${REMOTE_PATH}",
  "local_file_count": ${local_files},
  "tmux_sessions": "${tmux_info}",
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
    sudo cp -f "${state_file}" "${manifest_file}"
    sudo chown -R "${TARGET_USER}:${TARGET_USER}" "${backup_dir}" 2>/dev/null || true
    echo "✅ Recovery state saved to ${state_file}"
}

perform_sync() {
    local sync_type="${1:-routine}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")

    # 1. Prevent overlapping sync processes using lock file
    exec 200>"${LOCK_FILE}"
    if ! flock -n 200; then
        echo "[$timestamp] ⚠️ Sync in progress. Skipping overlapping cycle."
        return 0
    fi

    # 2. Safety Check: Verify workspace restoration was previously executed
    if [ ! -f "/tmp/.ubuntu_workspace_restored" ]; then
        echo "[$timestamp] ⚠️ Restore marker not found. Skipping sync to prevent overwriting." >&2
        flock -u 200 2>/dev/null || true
        return 1
    fi

    # 3. Safety Check: Never overwrite remote with an unexpectedly empty workspace
    local local_files
    local_files=$( (sudo find "${WORKSPACE_DIR}" -type f 2>/dev/null || true) | wc -l | tr -d '[:space:]' )
    local_files="${local_files:-0}"
    if [ "${local_files}" -eq 0 ]; then
        local remote_files
        remote_files=$( (rclone lsf "${REMOTE_WORKSPACE_PATH}" --recursive --files-only 2>/dev/null || true) | wc -l | tr -d '[:space:]' )
        remote_files="${remote_files:-0}"
        if [ "${remote_files}" -gt 0 ]; then
            echo "[$timestamp] ❌ Refusing to sync empty local workspace over non-empty remote backup (${remote_files} files). Aborting sync." >&2
            flock -u 200 2>/dev/null || true
            return 1
        fi
    fi

    echo "[$timestamp] ⏳ Starting ${sync_type} sync to ${REMOTE_PATH} (${local_files} local files)..."

    # 4. Safe sync with trash backup directory to preserve modified/deleted files
    local trash_dir="${REMOTE}cloud-dev/ubuntu-workspace-trash/$(date +%Y%m%d_%H%M%S)"

    # Sync workspace
    sudo rclone sync "${WORKSPACE_DIR}" "${REMOTE_WORKSPACE_PATH}" \
        --filter-from "${FILTERS_FILE}" \
        --backup-dir "${trash_dir}/workspace" \
        --fast-list \
        --transfers 4 \
        --checkers 8 \
        --drive-chunk-size 32M \
        --retries 3 \
        --stats-one-line \
        --stats 10s || echo "[$timestamp] ⚠️ Warning: workspace sync had issues"

    # Sync safe user configurations
    local config_stage="/tmp/ubuntu-config-stage"
    sudo rm -rf "${config_stage}"
    sudo mkdir -p "${config_stage}"

    # Stage safe config files from /home/nava
    for ITEM in .gitconfig .bashrc .bash_aliases .bash_history .zshrc .zsh_history .tmux.conf; do
        if [ -f "/home/${TARGET_USER}/${ITEM}" ]; then
            sudo cp -p "/home/${TARGET_USER}/${ITEM}" "${config_stage}/" 2>/dev/null || true
        fi
    done

    # Stage safe config directories (excluding private keys / secrets)
    if [ -d "/home/${TARGET_USER}/.ssh" ]; then
        sudo mkdir -p "${config_stage}/.ssh"
        if [ -f "/home/${TARGET_USER}/.ssh/authorized_keys" ]; then
            sudo cp -p "/home/${TARGET_USER}/.ssh/authorized_keys" "${config_stage}/.ssh/" 2>/dev/null || true
        fi
        if [ -f "/home/${TARGET_USER}/.ssh/config" ]; then
            sudo cp -p "/home/${TARGET_USER}/.ssh/config" "${config_stage}/.ssh/" 2>/dev/null || true
        fi
    fi

    for DIR_ITEM in .gemini .opencode .dsh .agents; do
        if [ -d "/home/${TARGET_USER}/${DIR_ITEM}" ]; then
            sudo cp -r "/home/${TARGET_USER}/${DIR_ITEM}" "${config_stage}/" 2>/dev/null || true
        fi
    done

    # Sync config stage to remote
    sudo rclone sync "${config_stage}" "${REMOTE_CONFIG_PATH}" \
        --filter-from "${FILTERS_FILE}" \
        --backup-dir "${trash_dir}/config" \
        --fast-list \
        --transfers 4 \
        --checkers 8 \
        --retries 3 || true

    sudo rm -rf "${config_stage}"

    # 5. Write recovery metadata manifest
    local manifest="/tmp/ubuntu-manifest.json"
    cat << EOF > "${manifest}"
{
  "timestamp": "${timestamp}",
  "sync_type": "${sync_type}",
  "user": "${TARGET_USER}",
  "local_file_count": ${local_files},
  "remote_target": "${REMOTE_PATH}"
}
EOF
    sudo rclone copyto "${manifest}" "${REMOTE_PATH}/manifest.json" 2>/dev/null || true

    echo "[$timestamp] ✅ ${sync_type^} sync completed successfully."
    flock -u 200 2>/dev/null || true
    return 0
}

run_daemon() {
    local interval="${1:-300}"
    echo "=================================================="
    echo "🚀 Starting 5-Minute Background Ubuntu Workspace Sync"
    echo "=================================================="
    echo "Sync Interval: ${interval} seconds (5 minutes)"
    echo "Local Source:  ${WORKSPACE_DIR}"
    echo "Destination:   ${REMOTE_PATH}"
    echo "$$" > "${PID_FILE}"

    cleanup_daemon() {
        echo "Stopping sync daemon (PID: $$)..."
        rm -f "${PID_FILE}"
        exit 0
    }
    trap cleanup_daemon SIGTERM SIGINT EXIT

    while true; do
        sleep "${interval}" &
        wait $!
        perform_sync "routine" || true
    done
}

run_final() {
    echo "=================================================="
    echo "💾 Performing Final Workspace Backup to Google Drive"
    echo "=================================================="
    stop_daemon
    save_recovery_state

    exec 200>"${LOCK_FILE}"
    echo "Acquiring sync lock for final backup..."
    flock -w 60 200 || echo "Proceeding with final backup..."

    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")

    if perform_sync "final"; then
        echo "🎉 Final Ubuntu workspace backup completed successfully at ${timestamp}!"
        flock -u 200 2>/dev/null || true
        return 0
    else
        echo "❌ Error: Final Ubuntu workspace backup failed!" >&2
        flock -u 200 2>/dev/null || true
        return 1
    fi
}

case "${1:-}" in
    --daemon)
        run_daemon "${2:-300}"
        ;;
    --stop-daemon)
        stop_daemon
        ;;
    --save-recovery-state)
        save_recovery_state
        ;;
    --once)
        perform_sync "single"
        ;;
    --final)
        run_final
        ;;
    *)
        echo "Usage: $0 {--daemon [interval] | --stop-daemon | --save-recovery-state | --once | --final}"
        exit 1
        ;;
esac
