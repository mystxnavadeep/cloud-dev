#!/usr/bin/env bash
# ==============================================================================
# sync-workspace.sh: Synchronize workspace to Google Drive via rclone
# Supports:
#   --daemon [interval]  Run continuously in background (default 300s = 5m)
#   --once               Run a single sync iteration
#   --final              Run final backup prior to workflow termination
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

WORKSPACE_DIR="${WORKSPACE_DIR:-/home/runner/workspace}"
REMOTE_SUBDIR="${REMOTE_SUBDIR:-cloud-dev/workspace}"
FILTERS_FILE="${FILTERS_FILE:-$(dirname "$0")/rclone-filters.txt}"
PID_FILE="/tmp/sync-workspace.pid"

# Detect remote
REMOTE="${RCLONE_REMOTE_NAME:-}"
if [ -z "${REMOTE}" ]; then
    REMOTE=$(rclone listremotes | head -n 1)
fi

if [ -z "${REMOTE}" ]; then
    echo "❌ Error: No rclone remote configured." >&2
    exit 1
fi

REMOTE_PATH="${REMOTE}${REMOTE_SUBDIR}"

perform_sync() {
    local sync_type="${1:-routine}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%SZ")

    echo "[$timestamp] ⏳ Starting ${sync_type} sync to ${REMOTE_PATH}..."

    # Use rclone sync to mirror workspace to Google Drive
    if rclone sync "${WORKSPACE_DIR}" "${REMOTE_PATH}" \
        --filter-from "${FILTERS_FILE}" \
        --fast-list \
        --transfers 4 \
        --checkers 8 \
        --drive-chunk-size 32M \
        --retries 3 \
        --stats-one-line \
        --stats 10s; then
        echo "[$timestamp] ✅ ${sync_type^} sync completed successfully."
        return 0
    else
        local exit_code=$?
        echo "[$timestamp] ⚠️ Warning: ${sync_type^} sync encountered error (code: ${exit_code}). Retrying next interval..." >&2
        return "${exit_code}"
    fi
}

run_daemon() {
    local interval="${1:-300}"
    echo "=================================================="
    echo "🚀 Starting Background Sync Daemon"
    echo "=================================================="
    echo "Sync Interval: ${interval} seconds (5 minutes)"
    echo "Source: ${WORKSPACE_DIR}"
    echo "Destination: ${REMOTE_PATH}"
    echo "$$" > "${PID_FILE}"

    trap 'echo "🛑 Background sync daemon received stop signal. Exiting..."; rm -f "${PID_FILE}"; exit 0' SIGTERM SIGINT

    while true; do
        sleep "${interval}" &
        wait $!
        perform_sync "periodic (5-min)" || true
    done
}

run_final() {
    echo "=================================================="
    echo "💾 Performing Final Workspace Backup"
    echo "=================================================="

    # Stop background daemon if running
    if [ -f "${PID_FILE}" ]; then
        DAEMON_PID=$(cat "${PID_FILE}" 2>/dev/null || true)
        if [ -n "${DAEMON_PID}" ] && kill -0 "${DAEMON_PID}" 2>/dev/null; then
            echo "Stopping background sync daemon (PID: ${DAEMON_PID})..."
            kill "${DAEMON_PID}" 2>/dev/null || true
            rm -f "${PID_FILE}"
        fi
    fi

    # Perform final thorough sync with multiple retries
    if perform_sync "FINAL"; then
        echo "🎉 Final backup successfully synchronized to Google Drive!"
        if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
            {
                echo "### 💾 Final Backup Status"
                echo "- **Status:** ✅ Completed successfully"
                echo "- **Timestamp:** $(date -u +"%Y-%m-%d %H:%M:%SZ")"
                echo "- **Destination:** \`${REMOTE_PATH}\`"
            } >> "${GITHUB_STEP_SUMMARY}"
        fi
        exit 0
    else
        echo "❌ Final backup failed!" >&2
        if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
            {
                echo "### 💾 Final Backup Status"
                echo "- **Status:** ❌ Failed"
                echo "- **Timestamp:** $(date -u +"%Y-%m-%d %H:%M:%SZ")"
                echo "- **Destination:** \`${REMOTE_PATH}\`"
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
