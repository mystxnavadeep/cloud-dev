#!/usr/bin/env bash
# ==============================================================================
# sync-workspace.sh: Synchronize workspace to Google Drive via rclone
# Supports:
#   --daemon [interval]  Run continuously in background (default 300s = 5 minutes)
#   --once               Run a single safe sync iteration
#   --final              Run final backup prior to workflow termination
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
        flock -u 200 || true
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
            flock -u 200 || true
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
        flock -u 200 || true
        return 0
    else
        local exit_code=$?
        echo "[$timestamp] ⚠️ Warning: ${sync_type^} sync encountered an issue (exit code: ${exit_code}). Will retry next cycle." >&2
        flock -u 200 || true
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

    # Handle clean termination of background daemon
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

    # Stop background daemon cleanly if running
    if [ -f "${PID_FILE}" ]; then
        DAEMON_PID=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [ -n "${DAEMON_PID}" ] && kill -0 "${DAEMON_PID}" 2>/dev/null; then
            echo "Stopping background sync daemon (PID: ${DAEMON_PID})..."
            kill -TERM "${DAEMON_PID}" 2>/dev/null || true
            sleep 1
            rm -f "${PID_FILE}"
        fi
    fi

    # Wait for any in-flight sync to complete (up to 60 seconds)
    exec 200>"${LOCK_FILE}"
    echo "Acquiring sync lock for final backup..."
    flock -w 60 200 || echo "Proceeding with final backup..."

    # Perform thorough final sync
    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")

    if perform_sync "FINAL"; then
        echo "🎉 Final workspace backup completed successfully at ${timestamp}!"
        if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
            {
                echo "### 💾 Final Google Drive Backup"
                echo "- **Status:** ✅ Successfully Uploaded"
                echo "- **Timestamp:** ${timestamp}"
                echo "- **Remote Path:** \`${REMOTE_PATH}\`"
                echo "- **Local Path:** \`${WORKSPACE_DIR}\`"
            } >> "${GITHUB_STEP_SUMMARY}"
        fi
        exit 0
    else
        echo "❌ Error: Final workspace backup failed!" >&2
        if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
            {
                echo "### 💾 Final Google Drive Backup"
                echo "- **Status:** ❌ Failed"
                echo "- **Timestamp:** ${timestamp}"
                echo "- **Remote Path:** \`${REMOTE_PATH}\`"
            } >> "${GITHUB_STEP_SUMMARY}"
        fi
        exit 1
    fi
}

# Mode parsing
MODE="${1:---once}"
case "$MODE" in
    --daemon)
        INTERVAL="${2:-300}"
        run_daemon "${INTERVAL}"
        ;;
    --final)
        run_final
        ;;
    --once)
        perform_sync "single"
        ;;
    *)
        echo "Usage: $0 [--daemon [interval] | --final | --once]"
        exit 1
        ;;
esac
