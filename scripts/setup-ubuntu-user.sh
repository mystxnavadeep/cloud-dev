#!/usr/bin/env bash
# ==============================================================================
# setup-ubuntu-user.sh: Configure persistent Linux user 'nava' and tmux sessions
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

TARGET_USER="${TARGET_USER:-nava}"
TARGET_PASS="${TARGET_PASS:-nava}"
WORKSPACE_DIR="${WORKSPACE_DIR:-/home/${TARGET_USER}/workspace}"

echo "=================================================="
echo "👤 Configuring Persistent Linux User: ${TARGET_USER}"
echo "=================================================="

# 1. Create target user if not present
if id "${TARGET_USER}" &>/dev/null; then
    echo "User '${TARGET_USER}' already exists."
else
    echo "Creating user '${TARGET_USER}'..."
    sudo useradd -m -s /bin/bash "${TARGET_USER}"
fi

# 2. Set user password
echo "${TARGET_USER}:${TARGET_PASS}" | sudo chpasswd
echo "Password configured for '${TARGET_USER}'."

# 3. Add to required groups
sudo groupadd -f ssl-cert || true
for GRP in sudo adm dialout cdrom audio video plugdev users ssl-cert; do
    if getent group "${GRP}" >/dev/null 2>&1; then
        sudo usermod -aG "${GRP}" "${TARGET_USER}" || true
    fi
done

# 4. Grant passwordless sudo access
echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/99-${TARGET_USER}" >/dev/null
sudo chmod 0440 "/etc/sudoers.d/99-${TARGET_USER}"

# 5. Create workspace and key directory structure
sudo mkdir -p \
    "${WORKSPACE_DIR}/projects" \
    "${WORKSPACE_DIR}/web" \
    "${WORKSPACE_DIR}/frontend" \
    "${WORKSPACE_DIR}/backend" \
    "${WORKSPACE_DIR}/apis" \
    "${WORKSPACE_DIR}/deployments" \
    "${WORKSPACE_DIR}/scripts" \
    "${WORKSPACE_DIR}/downloads" \
    "${WORKSPACE_DIR}/backups" \
    "${WORKSPACE_DIR}/tmp" \
    "/home/${TARGET_USER}/bin" \
    "/home/${TARGET_USER}/.local/bin" \
    "/home/${TARGET_USER}/.ssh" \
    "/home/${TARGET_USER}/.config" \
    "/home/${TARGET_USER}/.dsh" \
    "/home/${TARGET_USER}/.agents"

# 6. Configure shell environment and convenient aliases
BASHRC="/home/${TARGET_USER}/.bashrc"
if [ ! -f "${BASHRC}" ]; then
    sudo cp /etc/skel/.bashrc "${BASHRC}" || true
fi

# Append custom environment and aliases to .bashrc if not already present
if ! grep -q "# Ubuntu Cloud Web Development Studio Aliases" "${BASHRC}" 2>/dev/null; then
    sudo tee -a "${BASHRC}" >/dev/null << 'EOF'

# ==============================================================================
# Ubuntu Cloud Web Development Studio Aliases & Environment
# ==============================================================================
export PATH="${HOME}/bin:${HOME}/.local/bin:${HOME}/.cargo/bin:${HOME}/.bun/bin:/usr/local/bin:${PATH}"
export WORKSPACE="${HOME}/workspace"
export DSH_HOME="${HOME}/workspace/.dsh"
export DSH_AGENTS_HOME="${HOME}/workspace/.agents"

# Three Permanent Tmux Session Aliases
alias t1='tmux attach -t terminal-1 2>/dev/null || tmux new-session -s terminal-1 -c ~/workspace'
alias t2='tmux attach -t terminal-2 2>/dev/null || tmux new-session -s terminal-2 -c ~/workspace'
alias t3='tmux attach -t terminal-3 2>/dev/null || tmux new-session -s terminal-3 -c ~/workspace'
alias tls='tmux list-sessions'

# AI Coding Assistant Aliases
alias oc='opencode'
alias agy='agy'
alias dsh='dsh'

# Web Preview & Dev Utilities
alias preview='preview'
alias ws='cd ~/workspace'
alias projects='cd ~/workspace/projects'
alias web='cd ~/workspace/web'
alias ll='ls -la'
EOF
fi

# Configure tmux default configuration
TMUX_CONF="/home/${TARGET_USER}/.tmux.conf"
if [ ! -f "${TMUX_CONF}" ]; then
    sudo tee "${TMUX_CONF}" >/dev/null << 'EOF'
# Optimized tmux configuration for Ubuntu Cloud Dev Studio
set -g default-terminal "screen-256color"
set -g history-limit 50000
set -g mouse on
set -s escape-time 0
set -g set-remain-on-exit off

# Status bar styling
set -g status-style bg=colour235,fg=colour136
set -g status-left-length 30
set -g status-left "#[fg=colour76]☁️ [#S] "
set -g status-right "#[fg=colour136]%Y-%m-%d #[fg=colour250]%H:%M #[fg=colour76]#(whoami)@#H"

# Window numbering from 1
set -g base-index 1
setw -g pane-base-index 1
EOF
fi

# 7. Configure SSH directory and permissions
sudo chmod 700 "/home/${TARGET_USER}/.ssh"
if [ -f "/home/${TARGET_USER}/.ssh/authorized_keys" ]; then
    sudo chmod 600 "/home/${TARGET_USER}/.ssh/authorized_keys"
fi

# 8. Set correct ownership
sudo chown -R "${TARGET_USER}:${TARGET_USER}" "/home/${TARGET_USER}"

# 9. Pre-create the Three Named Tmux Sessions under target user
echo "Creating/verifying three permanent tmux sessions (terminal-1, terminal-2, terminal-3)..."
for SESS in terminal-1 terminal-2 terminal-3; do
    if sudo -u "${TARGET_USER}" tmux has-session -t "${SESS}" 2>/dev/null; then
        echo "✅ tmux session '${SESS}' already active."
    else
        sudo -u "${TARGET_USER}" tmux new-session -d -s "${SESS}" -c "${WORKSPACE_DIR}"
        echo "✅ Initialized tmux session '${SESS}' in '${WORKSPACE_DIR}'."
    fi
done

echo "=================================================="
echo "✅ User '${TARGET_USER}' & tmux Sessions Configured Successfully"
echo "=================================================="
