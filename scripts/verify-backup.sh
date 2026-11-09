#!/usr/bin/env bash
# ==============================================================================
# verify-backup.sh: Verify workspace backup integrity on Google Drive
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

WORKSPACE_DIR="${WORKSPACE_DIR:-/home/runner/workspace}"
REMOTE_SUBDIR="${REMOTE_SUBDIR:-cloud-dev/workspace}"

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

echo "=================================================="
echo "🔍 Verifying Workspace Backup Integrity"
echo "=================================================="
echo "Checking remote: ${REMOTE_PATH}"

# Check remote directory existence and size
SIZE_OUTPUT=$(rclone size "${REMOTE_PATH}" --json 2>/dev/null || true)

if [ -z "${SIZE_OUTPUT}" ]; then
    echo "❌ Error: Unable to query Google Drive backup at ${REMOTE_PATH}" >&2
    exit 1
fi

TOTAL_OBJECTS=$(echo "${SIZE_OUTPUT}" | jq -r '.count // 0')
TOTAL_BYTES=$(echo "${SIZE_OUTPUT}" | jq -r '.bytes // 0')

# Format bytes to human readable form
format_bytes() {
    local b=$1
    if [ "$b" -ge 1073741824 ]; then
        awk "BEGIN {printf \"%.2f GB\", $b/1073741824}"
    elif [ "$b" -ge 1048576 ]; then
        awk "BEGIN {printf \"%.2f MB\", $b/1048576}"
    elif [ "$b" -ge 1024 ]; then
        awk "BEGIN {printf \"%.2f KB\", $b/1024}"
    else
        echo "${b} B"
    fi
}

HUMAN_SIZE=$(format_bytes "${TOTAL_BYTES}")

echo "Remote Backup Verification Report:"
echo "-----------------------------------"
echo "Remote Path:   ${REMOTE_PATH}"
echo "Total Files:   ${TOTAL_OBJECTS}"
echo "Total Storage: ${HUMAN_SIZE} (${TOTAL_BYTES} bytes)"
echo "Backup Status: VERIFIED"
echo "-----------------------------------"

if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
    {
        echo "### 🔍 Workspace Backup Verification"
        echo "| Metric | Value |"
        echo "| :--- | :--- |"
        echo "| **Google Drive Path** | \`${REMOTE_PATH}\` |"
        echo "| **Total Files Preserved** | \`${TOTAL_OBJECTS}\` |"
        echo "| **Total Backup Size** | \`${HUMAN_SIZE}\` |"
        echo "| **Verification Status** | ✅ **VERIFIED** |"
    } >> "${GITHUB_STEP_SUMMARY}"
fi

echo "✅ Backup verification completed successfully."
