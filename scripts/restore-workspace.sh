#!/usr/bin/env bash
# ==============================================================================
# restore-workspace.sh: Restore workspace from Google Drive via rclone
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

# Resolve local workspace directory
GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-/home/runner}"
WORKSPACE_DIR="${WORKSPACE_DIR:-${GITHUB_WORKSPACE}/workspace}"
REMOTE_SUBDIR="${REMOTE_SUBDIR:-cloud-dev/workspace}"
FILTERS_FILE="${FILTERS_FILE:-$(dirname "$0")/rclone-filters.txt}"

echo "=================================================="
echo "🔄 Initializing Workspace Restoration"
echo "=================================================="
echo "Local Workspace Directory: ${WORKSPACE_DIR}"

mkdir -p "${WORKSPACE_DIR}"

# Ensure symlink from /home/runner/workspace to local workspace if running on runner
if [ -d "/home/runner" ] && [ "${WORKSPACE_DIR}" != "/home/runner/workspace" ]; then
    ln -sfn "${WORKSPACE_DIR}" /home/runner/workspace 2>/dev/null || true
fi

# 1. Verify rclone installation
if ! command -v rclone &>/dev/null; then
    echo "rclone is not installed. Installing rclone..."
    curl -fsSL https://rclone.org/install.sh | sudo bash
fi

# 2. Configure Google Drive credentials if RCLONE_CONFIG_B64 is provided
if [ -n "${RCLONE_CONFIG_B64:-}" ]; then
    mkdir -p "${HOME}/.config/rclone"
    echo "${RCLONE_CONFIG_B64}" | base64 -d > "${HOME}/.config/rclone/rclone.conf"
    chmod 600 "${HOME}/.config/rclone/rclone.conf"
fi

if [ ! -f "${HOME}/.config/rclone/rclone.conf" ]; then
    echo "❌ Error: rclone configuration file not found at ${HOME}/.config/rclone/rclone.conf!" >&2
    echo "Please configure the 'RCLONE_CONFIG_B64' GitHub Secret." >&2
    exit 1
fi

chmod 600 "${HOME}/.config/rclone/rclone.conf"

# 3. Detect and verify remote "gdrive:"
REMOTE="gdrive:"
if ! rclone listremotes | grep -q "^gdrive:"; then
    DETECTED_REMOTE=$(rclone listremotes | head -n 1)
    if [ -n "${DETECTED_REMOTE}" ]; then
        REMOTE="${DETECTED_REMOTE}"
    else
        echo "❌ Error: No remotes found in rclone configuration." >&2
        exit 1
    fi
fi

echo "✅ Using authenticated remote: ${REMOTE}"
REMOTE_PATH="${REMOTE}${REMOTE_SUBDIR}"
echo "Remote Target Path:        ${REMOTE_PATH}"

# 4. Verify Google Drive connectivity without exposing credentials
echo "Verifying Google Drive connectivity..."
if ! rclone lsf "${REMOTE}" --max-depth 1 >/dev/null 2>&1; then
    echo "❌ Error: Failed to connect to Google Drive remote '${REMOTE}'. Please verify your token." >&2
    exit 1
fi
echo "✅ Google Drive connection verified."

# 5. Check if remote workspace directory exists and has files
echo "Checking remote path '${REMOTE_PATH}' for existing backup..."
REMOTE_FILE_COUNT=$(rclone lsf "${REMOTE_PATH}" --recursive --files-only 2>/dev/null | wc -l || echo 0)

if [ "${REMOTE_FILE_COUNT}" -gt 0 ]; then
    echo "📦 Existing workspace backup found (${REMOTE_FILE_COUNT} files). Restoring into '${WORKSPACE_DIR}'..."
    
    # Restore with filters and robust retry flags
    rclone copy "${REMOTE_PATH}" "${WORKSPACE_DIR}" \
        --filter-from "${FILTERS_FILE}" \
        --fast-list \
        --transfers 8 \
        --checkers 16 \
        --drive-chunk-size 32M \
        --retries 3 \
        --stats-one-line \
        --stats 5s

    LOCAL_RESTORED_COUNT=$(find "${WORKSPACE_DIR}" -type f | wc -l)

    # Safety Check: Never overwrite restored files with an empty workspace
    if [ "${LOCAL_RESTORED_COUNT}" -eq 0 ]; then
        echo "❌ Error: Remote backup had ${REMOTE_FILE_COUNT} files, but local restore produced 0 files." >&2
        echo "Aborting to prevent accidental data loss." >&2
        exit 1
    fi

    echo "✅ Workspace restored successfully (${LOCAL_RESTORED_COUNT} files present)."
    echo "${LOCAL_RESTORED_COUNT}" > /tmp/.workspace_restored

    if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
        {
            echo "### 🔄 Workspace Restoration Summary"
            echo "- **Status:** ✅ Successfully Restored from Google Drive"
            echo "- **Remote Path:** \`${REMOTE_PATH}\`"
            echo "- **Local Path:** \`${WORKSPACE_DIR}\`"
            echo "- **Files Restored:** ${LOCAL_RESTORED_COUNT}"
        } >> "${GITHUB_STEP_SUMMARY}"
    fi
else
    echo "🌱 First run / empty directory detected: No existing files at '${REMOTE_PATH}'."
    echo "Initializing clean workspace..."

    # Ensure remote directory exists on Google Drive
    rclone mkdir "${REMOTE_PATH}" || true

    # Create initial welcome file if not present
    if [ ! -f "${WORKSPACE_DIR}/WELCOME.md" ]; then
        cat << 'EOF' > "${WORKSPACE_DIR}/WELCOME.md"
# Welcome to Your Cloud Development Workspace!

This persistent workspace is synced with your Google Drive at `gdrive:cloud-dev/workspace`.

### 💾 Persistence Features
- **Auto-Sync:** Changes in this directory are synchronized to Google Drive every 5 minutes.
- **Final Backup:** A full backup is performed automatically when the workflow completes or is stopped.
- **Persistence Across Sessions:** All project files, source code, and configurations in this workspace will be automatically restored on your next session.

### 🌐 Previewing Websites
- To preview websites, start your server with `--host 0.0.0.0` (e.g. `npm run dev -- --host 0.0.0.0`).
- Use the `preview` CLI command (`preview list` or `preview tunnel <port>`) to create a temporary preview tunnel on demand.
EOF
    fi

    # Initialize example templates if available
    if [ -f "$(dirname "$0")/init-templates.sh" ]; then
        "$(dirname "$0")/init-templates.sh" || true
    fi

    echo "initial" > /tmp/.workspace_restored
    echo "✅ Clean workspace initialized."

    if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
        {
            echo "### 🔄 Workspace Restoration Summary"
            echo "- **Status:** 🌱 First run (Initialized Clean Workspace)"
            echo "- **Remote Path:** \`${REMOTE_PATH}\`"
            echo "- **Local Path:** \`${WORKSPACE_DIR}\`"
        } >> "${GITHUB_STEP_SUMMARY}"
    fi
fi

# Ensure DSH directories exist and permissions are strictly owner-only (assertOwnerOnlyAccess requirement)
mkdir -p "${WORKSPACE_DIR}/.dsh" "${WORKSPACE_DIR}/.agents"
chmod -R u+rwX "${WORKSPACE_DIR}"
if [ -d "${WORKSPACE_DIR}/.dsh" ]; then
    chmod 700 "${WORKSPACE_DIR}/.dsh" || true
    find "${WORKSPACE_DIR}/.dsh" -type f -exec chmod 600 {} + || true
fi
if [ -d "${WORKSPACE_DIR}/.agents" ]; then
    chmod 700 "${WORKSPACE_DIR}/.agents" || true
fi

echo "Workspace restore complete."
