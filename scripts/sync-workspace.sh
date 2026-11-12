#!/usr/bin/env bash
# ==============================================================================
# sync-workspace.sh: Synchronize workspace to Google Drive via rclone
# Supports:
#   --daemon [interval]    Run continuously in background (default 300s = 5 minutes)
#   --stop-daemon          Safely terminate background daemon and clear locks
#   --save-recovery-state  Save session recovery state and manifest
#   --once                 Run a single safe sync iteration
#   --final                Run final backup prior to workflow termination
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-/home/runner}"
WORKSPACE_DIR="${WORKSPACE_DIR:-${GITHUB_WORKSPACE}/workspace}"
REMOTE_SUBDIR="${REMOTE_SUBDIR:-cloud-dev/workspace}"
FILTERS_FILE="${FILTERS_FILE:-$(dirname "$0")/rclone-filters.txt}"
PID_FILE="/tmp/sync-workspace.pid"
LOCK_FILE="/tmp/sync-workspace.lock"

# Detect remote
REMOTE="gdrive:"
if ! rclone listremotes 2>/dev/null | grep -q "^gdrive:"; then
    DETECTED_REMOTE=$(rclone listremotes 2>/dev/null | head -n 1 || true)
    if [ -n "${DETECTED_REMOTE}" ]; then
        REMOTE="${DETECTED_REMOTE}"
    fi
fi

REMOTE_PATH="${REMOTE}${REMOTE_SUBDIR}"

stop_daemon() {
    echo "Checking for active workspace sync daemon..."
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
    echo "Saving workspace session recovery state..."
    local backup_dir="${WORKSPACE_DIR}/backups"
    mkdir -p "${backup_dir}"

    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")

    local local_files
    local_files=$(find "${WORKSPACE_DIR}" -type f 2>/dev/null | wc -l || echo 0)

    local manifest_file="${backup_dir}/recovery-state.json"
    cat << EOF > "${manifest_file}"
{
  "timestamp": "${timestamp}",
  "os": "ubuntu-latest",
  "workspace_dir": "${WORKSPACE_DIR}",
  "remote_target": "${REMOTE_PATH}",
  "local_file_count": ${local_files}
}
EOF
    cp -f "${manifest_file}" "${backup_dir}/backup-manifest.json" 2>/dev/null || true
    echo "✅ Recovery state saved to ${manifest_file}"
}

perform_sync() {
    local sync_type="${1:-routine}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")

    # 1. Prevent overlapping sync processes using file descriptor lock
    exec 200>"${LOCK_FILE}"
    if ! flock -n 200; then
        echo "[$timestamp] ⚠️ A sync is already in progress. Skipping overlapping iteration."
        return 0
    fi

    # 2. Safety Check: Verify workspace restoration was completed
    if [ ! -f "/tmp/.workspace_restored" ]; then
        echo "[$timestamp] ⚠️ Workspace restore marker not found. Aborting sync to prevent overwriting with uninitialized directory." >&2
        flock -u 200 2>/dev/null || true
        return 1
    fi

    # 3. Safety Check: Never overwrite remote with an unexpectedly empty workspace
    local local_files
    local_files=$(find "${WORKSPACE_DIR}" -type f 2>/dev/null | wc -l || echo 0)
    if [ "${local_files}" -eq 0 ]; then
        local remote_files
        remote_files=$(rclone lsf "${REMOTE_PATH}" --recursive --files-only 2>/dev/null | wc -l || echo 0)
        if [ "${remote_files}" -gt 0 ]; then
            echo "[$timestamp] ❌ Refusing to sync empty local workspace over non-empty remote backup (${remote_files} files on remote). Aborting sync." >&2
            flock -u 200 2>/dev/null || true
            return 1
        fi
    fi

    echo "[$timestamp] ⏳ Starting ${sync_type} sync to ${REMOTE_PATH} (${local_files} local files)..."

    # 4. Safe sync with trash backup directory to prevent accidental data loss
    local trash_dir="${REMOTE}cloud-dev/trash/$(date +%Y%m%d_%H%M%S)"

    if rclone sync "${WORKSPACE_DIR}" "${REMOTE_PATH}" \
        --filter-from "${FILTERS_FILE}" \
        --backup-dir "${trash_dir}" \
        --fast-list \
        --transfers 4 \
        --checkers 8 \
        --drive-chunk-size 32M \
        --retries 3 \
        --stats-one-line \
        --stats 10s; then
        echo "[$timestamp] ✅ ${sync_type^} sync completed successfully."
        flock -u 200 2>/dev/null || true
        return 0
    else
        local exit_code=$?
        echo "[$timestamp] ⚠️ Warning: ${sync_type^} sync encountered an issue (exit code: ${exit_code}). Will retry next cycle." >&2
        flock -u 200 2>/dev/null || true
        return "${exit_code}"
    fi
}

run_daemon() {
    local interval="${1:-300}"
    echo "=================================================="
    echo "🚀 Starting 5-Minute Background Workspace Sync"
    echo "=================================================="
    echo "Sync Interval: ${interval} seconds (5 minutes)"
    echo "Local Source:  ${WORKSPACE_DIR}"
    echo "Destination:   ${REMOTE_PATH}"
    echo "$$" > "${PID_FILE}"

    cleanup_daemon() {
        echo "🛑 Sync daemon stopping cleanly..."
        rm -f "${PID_FILE}"
        exit 0
    }
    trap cleanup_daemon SIGTERM SIGINT

    while true; do
        sleep "${interval}" &
        wait $!
        perform_sync "periodic (5-min)" || true
    done
}

run_final() {
    echo "=================================================="
    echo "💾 Performing Final Workspace Backup to Google Drive"
    echo "=================================================="
    stop_daemon
    save_recovery_state

    # Wait for any in-flight sync to complete (up to 60 seconds)
    exec 200>"${LOCK_FILE}"
    echo "Acquiring sync lock for final backup..."
    flock -w 60 200 || echo "Proceeding with final backup..."

    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")

    if perform_sync "FINAL"; then
        echo "🎉 Final workspace backup completed successfully at ${timestamp}!"
        flock -u 200 2>/dev/null || true
        if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
            {
                echo "### 💾 Final Google Drive Backup"
                echo "- **Status:** ✅ Successfully Uploaded"
                echo "- **Timestamp:** ${timestamp}"
                echo "- **Remote Path:** \`${REMOTE_PATH}\`"
                echo "- **Local Path:** \`${WORKSPACE_DIR}\`"
            } >> "${GITHUB_STEP_SUMMARY}"
        fi
        return 0
    else
        echo "❌ Error: Final workspace backup failed!" >&2
        flock -u 200 2>/dev/null || true
        if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
            {
                echo "### 💾 Final Google Drive Backup"
                echo "- **Status:** ❌ Failed"
                echo "- **Timestamp:** ${timestamp}"
                echo "- **Remote Path:** \`${REMOTE_PATH}\`"
            } >> "${GITHUB_STEP_SUMMARY}"
        fi
        return 1
    fi
}

MODE="${1:---once}"
case "$MODE" in
    --daemon)
        INTERVAL="${2:-300}"
        run_daemon "${INTERVAL}"
        ;;
    --stop-daemon)
        stop_daemon
        ;;
    --save-recovery-state)
        save_recovery_state
        ;;
    --final)
        run_final
        ;;
    --once)
        perform_sync "single"
        ;;
    *)
        echo "Usage: $0 [--daemon [interval] | --stop-daemon | --save-recovery-state | --final | --once]"
        exit 1
        ;;
esac
