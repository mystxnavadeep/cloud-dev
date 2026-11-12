#!/usr/bin/env bash
# ==============================================================================
# verify-ubuntu-gnome.sh: Rigorous Runtime Verification of Ubuntu GNOME Cloud PC
# Verifies CLI tools, GNOME desktop components, D-Bus, XRDP, SSH, and Tmux sessions
# using the actual target user ('nava') environment.
# ==============================================================================

set -eo pipefail
set +x

TARGET_USER="${TARGET_USER:-nava}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/home/${TARGET_USER}/workspace}"

echo "=================================================="
echo "🧪 Running Rigorous GNOME Verification as User: ${TARGET_USER}"
echo "=================================================="

FAILED_CHECKS=0

check_cmd() {
    local cmd_name="$1"
    local desc="$2"
    if sudo -u "${TARGET_USER}" -i bash -c "command -v ${cmd_name} >/dev/null 2>&1"; then
        local version_info
        version_info=$(sudo -u "${TARGET_USER}" -i bash -c "${cmd_name} --version 2>&1 | head -n 1" || echo "available")
        echo "✅ ${desc} (${cmd_name}): ${version_info}"
    else
        echo "❌ FAILED: ${desc} (${cmd_name}) NOT found in user '${TARGET_USER}' PATH!" >&2
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

check_wrapper() {
    local cmd_name="$1"
    local desc="$2"
    if sudo -u "${TARGET_USER}" -i bash -c "command -v ${cmd_name} >/dev/null 2>&1"; then
        echo "✅ ${desc} (${cmd_name}): available in PATH"
    else
        echo "❌ FAILED: ${desc} (${cmd_name}) NOT found in user '${TARGET_USER}' PATH!" >&2
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
}

echo "--- 1. Verifying Core Runtime & CLI Toolchains ---"
check_cmd "node" "Node.js Runtime"
check_cmd "npm" "Node Package Manager"
check_cmd "pnpm" "pnpm Package Manager"
check_cmd "yarn" "Yarn Package Manager"
check_cmd "bun" "Bun JavaScript Runtime"
check_cmd "python3" "Python 3 Runtime"
check_cmd "uv" "uv Python Tool"
check_cmd "tmux" "tmux Terminal Multiplexer"
check_cmd "git" "Git Version Control"

echo ""
echo "--- 2. Verifying Cloud & Coding Agent CLIs ---"
check_cmd "wrangler" "Cloudflare Wrangler CLI"
check_cmd "vercel" "Vercel CLI"
check_cmd "opencode" "OpenCode CLI"
check_wrapper "oc" "OpenCode CLI Alias/Wrapper"
check_cmd "agy" "Google Antigravity CLI"
check_cmd "dsh" "DeepSeek Harness CLI"

echo ""
echo "--- 3. Verifying Three Permanent Tmux Terminals & Wrappers ---"
check_wrapper "t1" "Terminal-1 Attach Wrapper"
check_wrapper "t2" "Terminal-2 Attach Wrapper"
check_wrapper "t3" "Terminal-3 Attach Wrapper"
check_wrapper "tls" "Tmux List-Sessions Wrapper"

# Verify actual active tmux sessions under user 'nava'
for SESS in terminal-1 terminal-2 terminal-3; do
    if sudo -u "${TARGET_USER}" tmux has-session -t "${SESS}" 2>/dev/null; then
        echo "✅ Tmux session '${SESS}' is ACTIVE under '${TARGET_USER}'"
    else
        echo "❌ FAILED: Tmux session '${SESS}' is NOT active under '${TARGET_USER}'!" >&2
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
done

echo ""
echo "--- 4. Verifying GNOME Desktop, D-Bus, and XRDP Components ---"
if command -v gnome-shell &>/dev/null; then
    echo "✅ gnome-shell: $(gnome-shell --version | head -n 1)"
else
    echo "❌ FAILED: gnome-shell is NOT installed!" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

if command -v gnome-session &>/dev/null; then
    echo "✅ gnome-session: $(gnome-session --version | head -n 1)"
else
    echo "❌ FAILED: gnome-session is NOT installed!" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

if command -v gnome-terminal &>/dev/null; then
    echo "✅ gnome-terminal: $(gnome-terminal --version | head -n 1)"
else
    echo "❌ FAILED: gnome-terminal is NOT installed!" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

if command -v nautilus &>/dev/null; then
    echo "✅ nautilus: $(nautilus --version | head -n 1)"
else
    echo "❌ FAILED: nautilus is NOT installed!" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

if command -v gnome-control-center &>/dev/null; then
    echo "✅ gnome-control-center: $(gnome-control-center --version | head -n 1)"
else
    echo "❌ FAILED: gnome-control-center is NOT installed!" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

if command -v dconf &>/dev/null; then
    echo "✅ dconf: $(dconf --version | head -n 1)"
else
    echo "❌ FAILED: dconf is NOT installed!" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

if command -v dbus-run-session &>/dev/null || command -v dbus-launch &>/dev/null; then
    echo "✅ dbus session launcher is available."
else
    echo "❌ FAILED: dbus-run-session or dbus-launch NOT found!" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

if command -v xrdp &>/dev/null; then
    echo "✅ xrdp: $(xrdp --version | head -n 1)"
else
    echo "❌ FAILED: xrdp is NOT installed!" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# Verify XRDP and SSH listening ports
if ss -tln | grep -q ":22 "; then
    echo "✅ OpenSSH Server is listening on port 22."
else
    echo "❌ FAILED: OpenSSH Server is not listening on port 22!" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

if ss -tln | grep -q ":3389 "; then
    echo "✅ XRDP Server is listening on port 3389."
else
    echo "❌ FAILED: XRDP Server is not listening on port 3389!" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

echo ""
echo "--- 5. Verifying Workspace Subdirectories ---"
for SUBDIR in projects frontend backend web apis deployments scripts downloads backups tmp; do
    if [ -d "${WORKSPACE_DIR}/${SUBDIR}" ]; then
        echo "✅ Directory present: ${WORKSPACE_DIR}/${SUBDIR}"
    else
        echo "❌ FAILED: Missing required workspace directory: ${WORKSPACE_DIR}/${SUBDIR}" >&2
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
done

echo ""
echo "--- 6. Verifying Home Directory File Permissions & Session Scripts ---"
ROOT_OWNED=$(sudo find "/home/${TARGET_USER}" -maxdepth 3 -user root 2>/dev/null | wc -l || echo 0)
if [ "${ROOT_OWNED}" -gt 0 ]; then
    echo "⚠️ Warning: Found ${ROOT_OWNED} root-owned files in /home/${TARGET_USER}. Repairing ownership..."
    sudo chown -R "${TARGET_USER}:${TARGET_USER}" "/home/${TARGET_USER}"
    echo "✅ Repaired ownership of all files to ${TARGET_USER}:${TARGET_USER}."
else
    echo "✅ All files in /home/${TARGET_USER} are cleanly owned by ${TARGET_USER}:${TARGET_USER}."
fi

# Verify .xsession and startwm.sh
if [ -f "/home/${TARGET_USER}/.xsession" ] && [ -x "/home/${TARGET_USER}/.xsession" ]; then
    echo "✅ /home/${TARGET_USER}/.xsession is present and executable."
else
    echo "❌ FAILED: /home/${TARGET_USER}/.xsession is missing or not executable!" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

if [ -f "/etc/xrdp/startwm.sh" ] && [ -x "/etc/xrdp/startwm.sh" ]; then
    echo "✅ /etc/xrdp/startwm.sh is present and executable."
else
    echo "❌ FAILED: /etc/xrdp/startwm.sh is missing or not executable!" >&2
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

echo ""
echo "=================================================="
if [ "${FAILED_CHECKS}" -eq 0 ]; then
    echo "🎉 ALL RUNTIME & GNOME VERIFICATION CHECKS PASSED (0 failures)!"
    echo "=================================================="
    if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
        {
            echo "### 🧪 Ubuntu GNOME Environment Verification"
            echo "✅ **All Verification Checks Passed:** 0 failures."
            echo "- **User Environment:** \`${TARGET_USER}\`"
            echo "- **GNOME Components:** \`gnome-shell\`, \`gnome-session\`, \`gnome-terminal\`, \`nautilus\`, \`gnome-control-center\`, \`dconf\`"
            echo "- **CLIs Verified:** \`agy\`, \`opencode\`, \`oc\`, \`wrangler\`, \`vercel\`, \`dsh\`, \`node\`, \`npm\`, \`bun\`, \`python3\`, \`uv\`, \`tmux\`"
            echo "- **Tmux Sessions:** \`terminal-1\`, \`terminal-2\`, \`terminal-3\` (Wrappers: \`t1\`, \`t2\`, \`t3\`, \`tls\` active)"
            echo "- **Network & Ports:** XRDP (port 3389) + SSH (port 22) active"
        } >> "${GITHUB_STEP_SUMMARY}"
    fi
    exit 0
else
    echo "❌ CRITICAL: ${FAILED_CHECKS} verification check(s) FAILED!" >&2
    echo "=================================================="
    exit 1
fi
