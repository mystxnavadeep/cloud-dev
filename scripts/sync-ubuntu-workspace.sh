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
        flock -u 200 || true
        return 1
    fi

    # 3. Safety Check: Never overwrite remote with an unexpectedly empty workspace
    local local_files
    local_files=$(find "${WORKSPACE_DIR}" -type f 2>/dev/null | wc -l || echo 0)
    if [ "${local_files}" -eq 0 ]; then
        local remote_files
        remote_files=$(rclone lsf "${REMOTE_WORKSPACE_PATH}" --recursive --files-only 2>/dev/null | wc -l || echo 0)
        if [ "${remote_files}" -gt 0 ]; then
            echo "[$timestamp] ❌ Refusing to sync empty local workspace over non-empty remote backup (${remote_files} files). Aborting sync." >&2
            flock -u 200 || true
            return 1
        fi
    fi

    echo "[$timestamp] ⏳ Starting ${sync_type} sync to ${REMOTE_PATH} (${local_files} local files)..."

    # 4. Safe sync with trash backup directory to preserve modified/deleted files
    local trash_dir="${REMOTE}cloud-dev/ubuntu-workspace-trash/$(date +%Y%m%d_%H%M%S)"

    # Sync workspace
    rclone sync "${WORKSPACE_DIR}" "${REMOTE_WORKSPACE_PATH}" \
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
    rm -rf "${config_stage}"
    mkdir -p "${config_stage}"

    # Stage safe config files from /home/nava
    for ITEM in .gitconfig .bashrc .bash_aliases .bash_history .zshrc .zsh_history .tmux.conf; do
        if [ -f "/home/${TARGET_USER}/${ITEM}" ]; then
            cp -p "/home/${TARGET_USER}/${ITEM}" "${config_stage}/" 2>/dev/null || true
        fi
    done

    # Stage safe config directories (excluding private keys / secrets)
    if [ -d "/home/${TARGET_USER}/.ssh" ]; then
        mkdir -p "${config_stage}/.ssh"
        if [ -f "/home/${TARGET_USER}/.ssh/authorized_keys" ]; then
            cp -p "/home/${TARGET_USER}/.ssh/authorized_keys" "${config_stage}/.ssh/" 2>/dev/null || true
        fi
        if [ -f "/home/${TARGET_USER}/.ssh/config" ]; then
            cp -p "/home/${TARGET_USER}/.ssh/config" "${config_stage}/.ssh/" 2>/dev/null || true
        fi
    fi

    for DIR_ITEM in .gemini .opencode .dsh .agents; do
        if [ -d "/home/${TARGET_USER}/${DIR_ITEM}" ]; then
            cp -r "/home/${TARGET_USER}/${DIR_ITEM}" "${config_stage}/" 2>/dev/null || true
        fi
    done

    # Sync config stage to remote
    rclone sync "${config_stage}" "${REMOTE_CONFIG_PATH}" \
        --filter-from "${FILTERS_FILE}" \
        --backup-dir "${trash_dir}/config" \
        --fast-list \
        --transfers 4 \
        --checkers 8 \
        --retries 3 || true

    rm -rf "${config_stage}"

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
    rclone copyto "${manifest}" "${REMOTE_PATH}/manifest.json" 2>/dev/null || true

    echo "[$timestamp] ✅ ${sync_type^} sync completed successfully."
    flock -u 200 || true
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

case "${1:-}" in
    --daemon)
        run_daemon "${2:-300}"
        ;;
    --once)
        perform_sync "single"
        ;;
    --final)
        perform_sync "final"
        ;;
    *)
        echo "Usage: $0 {--daemon [interval_seconds] | --once | --final}"
        exit 1
        ;;
esac
