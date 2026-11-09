#!/usr/bin/env bash
# ==============================================================================
# restore-workspace.sh: Restore workspace from Google Drive via rclone
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

WORKSPACE_DIR="${WORKSPACE_DIR:-/home/runner/workspace}"
REMOTE_SUBDIR="${REMOTE_SUBDIR:-cloud-dev/workspace}"
FILTERS_FILE="${FILTERS_FILE:-$(dirname "$0")/rclone-filters.txt}"

echo "=================================================="
echo "🔄 Initializing Workspace Restoration"
echo "=================================================="
echo "Target Workspace Directory: ${WORKSPACE_DIR}"

mkdir -p "${WORKSPACE_DIR}"

# 1. Verify rclone installation
if ! command -v rclone &>/dev/null; then
    echo "❌ Error: rclone is not installed." >&2
    exit 1
fi

# 2. Detect configured remote
REMOTE="${RCLONE_REMOTE_NAME:-}"
if [ -z "${REMOTE}" ]; then
    REMOTE=$(rclone listremotes | head -n 1)
fi

if [ -z "${REMOTE}" ]; then
    echo "❌ Error: No rclone remote configured. Check RCLONE_CONFIG_B64 secret." >&2
    exit 1
fi

echo "✅ Detected rclone remote: ${REMOTE}"
REMOTE_PATH="${REMOTE}${REMOTE_SUBDIR}"
echo "Remote Target Path: ${REMOTE_PATH}"

# 3. Test remote connectivity without leaking credentials
echo "Checking remote connectivity..."
if ! rclone about "${REMOTE}" >/dev/null 2>&1; then
    echo "⚠️ Warning: 'rclone about' check was not available or restricted, continuing with file listing..."
fi

# 4. Check if backup exists on Google Drive (Requirement: Handle first run)
echo "Inspecting remote path for existing workspace backup..."
EXISTING_FILES=0
if rclone lsf "${REMOTE_PATH}" --max-depth 1 2>/dev/null | grep -q .; then
    EXISTING_FILES=1
fi

if [ "${EXISTING_FILES}" -eq 1 ]; then
    echo "📦 Existing backup found on Google Drive! Restoring files..."
    
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

    RESTORE_COUNT=$(find "${WORKSPACE_DIR}" -type f | wc -l)
    echo "✅ Workspace restored successfully (${RESTORE_COUNT} files restored)."
    
    if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
        {
            echo "### 🔄 Workspace Restoration Summary"
            echo "- **Status:** ✅ Successfully Restored from Google Drive"
            echo "- **Remote Path:** \`${REMOTE_PATH}\`"
            echo "- **Local Path:** \`${WORKSPACE_DIR}\`"
            echo "- **Files Restored:** ${RESTORE_COUNT}"
        } >> "${GITHUB_STEP_SUMMARY}"
    fi
else
    echo "🌱 First run detected: No existing backup found at '${REMOTE_PATH}'."
    echo "Initializing a clean workspace with starter documentation and templates..."

    # Create initial welcome file
    if [ ! -f "${WORKSPACE_DIR}/WELCOME.md" ]; then
        cat << 'EOF' > "${WORKSPACE_DIR}/WELCOME.md"
# Welcome to Your Cloud Development Workspace!

This cloud development environment is powered by **DeepSeek Harness** on GitHub Actions with continuous **Google Drive** persistence and private **Tailscale** access.

### 🌐 Accessing Services via Tailscale
- **DeepSeek Harness Web UI:** `http://<TAILSCALE_IP>:3080/?token=...`
- **Website Previews:** `http://<TAILSCALE_IP>:<PORT>`
  - React/Vite: `npm run dev -- --host 0.0.0.0` (Port 5173)
  - Next.js: `npx next dev -H 0.0.0.0 -p 3000` (Port 3000)
  - Python FastAPI: `uvicorn main:app --host 0.0.0.0 --port 8000` (Port 8000)
  - Python Flask: `flask run --host=0.0.0.0 --port=5000` (Port 5000)

### 📁 Example Projects
Starter templates are ready in `/home/runner/workspace/examples`:
- `examples/react-vite-app`: React + Vite + Tailwind CSS + Lucide
- `examples/python-fastapi`: FastAPI Python API

### 💾 Persistence
Everything in this workspace is automatically synchronized to your Google Drive every 5 minutes and upon session completion.
EOF
    fi

    # Initialize starter templates
    "$(dirname "$0")/init-templates.sh" || true

    echo "✅ Clean workspace initialized with starter templates."

    if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
        {
            echo "### 🔄 Workspace Restoration Summary"
            echo "- **Status:** 🌱 First run (Clean Workspace Initialized)"
            echo "- **Remote Path:** \`${REMOTE_PATH}\`"
            echo "- **Local Path:** \`${WORKSPACE_DIR}\`"
        } >> "${GITHUB_STEP_SUMMARY}"
    fi
fi

# Ensure DSH directories exist and permissions are correct
mkdir -p "${WORKSPACE_DIR}/.dsh" "${WORKSPACE_DIR}/.agents"
chmod -R u+rwX "${WORKSPACE_DIR}"

echo "Workspace preparation complete."
