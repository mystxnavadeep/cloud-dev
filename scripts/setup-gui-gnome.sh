#!/usr/bin/env bash
# ==============================================================================
# setup-gui-gnome.sh: Install & configure Ubuntu GNOME desktop, XRDP, and OpenSSH
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${TARGET_USER:-nava}"

echo "=================================================="
echo "🖥️  Installing & Configuring Ubuntu GNOME Desktop + XRDP + SSH"
echo "=================================================="

# Apply network, DNS, mirror and debconf optimizations
if [ -f "${SCRIPT_DIR}/optimize-ubuntu-system.sh" ]; then
    "${SCRIPT_DIR}/optimize-ubuntu-system.sh" || true
fi

# 1. Install focused GNOME desktop packages, XRDP, and OpenSSH Server
echo "Updating apt cache and installing GNOME desktop components..."
sudo apt-get update -qq -o Acquire::http::Timeout="15" -o Acquire::Retries="5"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    -o Acquire::http::Timeout="15" -o Acquire::Retries="5" \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    gnome-shell \
    gnome-session \
    gnome-session-bin \
    gnome-session-common \
    gnome-settings-daemon \
    gnome-control-center \
    gnome-terminal \
    nautilus \
    gnome-tweaks \
    gnome-keyring \
    dbus-x11 \
    dbus-user-session \
    dconf-cli \
    xorg \
    xorgxrdp \
    xrdp \
    x11-xserver-utils \
    openssh-server \
    polkitd \
    yaru-theme-gnome-shell \
    yaru-theme-gtk \
    yaru-theme-icon \
    adwaita-icon-theme \
    xdg-utils \
    at-spi2-core

# Optional: try installing gnome-software without recommended bloat
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    --no-install-recommends \
    gnome-software 2>/dev/null || true

# 2. Add users to ssl-cert group for certificate access
sudo adduser xrdp ssl-cert 2>/dev/null || true
sudo adduser "${TARGET_USER}" ssl-cert 2>/dev/null || true

# 3. Configure XRDP window manager session startup for GNOME
echo "Configuring XRDP session startup for GNOME Shell..."

# 3a. User-level session files (.xsession & .xsessionrc)
XSESSION_FILE="/home/${TARGET_USER}/.xsession"
sudo tee "${XSESSION_FILE}" >/dev/null << 'EOF'
#!/usr/bin/env bash
if [ -r /etc/profile ]; then
    . /etc/profile
fi
if [ -r ~/.profile ]; then
    . ~/.profile
fi

# Detect available session (Ubuntu GNOME vs standard GNOME)
if [ -f /usr/share/xsessions/ubuntu.desktop ]; then
    export XDG_CURRENT_DESKTOP="ubuntu:GNOME"
    export GNOME_SHELL_SESSION_MODE="ubuntu"
    SESSION="ubuntu"
else
    export XDG_CURRENT_DESKTOP="GNOME"
    export GNOME_SHELL_SESSION_MODE="gnome"
    SESSION="gnome"
fi

export XDG_DATA_DIRS="/usr/share/ubuntu:/usr/local/share:/usr/share"
export XDG_CONFIG_DIRS="/etc/xdg/xdg-ubuntu:/etc/xdg"
export DESKTOP_SESSION="${SESSION}"
export XDG_SESSION_TYPE="x11"
export GDMSESSION="${SESSION}"
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

exec dbus-run-session -- gnome-session --session="${SESSION}"
EOF
sudo chmod +x "${XSESSION_FILE}"
sudo cp -p "${XSESSION_FILE}" "/home/${TARGET_USER}/.xsessionrc"

# Create initial GNOME configuration directories and enforce user ownership
sudo -u "${TARGET_USER}" mkdir -p \
    "/home/${TARGET_USER}/.config/dconf" \
    "/home/${TARGET_USER}/.config/gnome-session" \
    "/home/${TARGET_USER}/.cache" \
    "/home/${TARGET_USER}/.local/share"
sudo chown -R "${TARGET_USER}:${TARGET_USER}" "/home/${TARGET_USER}"

# 3b. System-level XRDP startwm.sh configuration
STARTWM="/etc/xrdp/startwm.sh"
sudo tee "${STARTWM}" >/dev/null << 'EOF'
#!/usr/bin/env bash
if [ -r /etc/profile ]; then
    . /etc/profile
fi
if [ -r ~/.profile ]; then
    . ~/.profile
fi

if [ -f ~/.xsession ]; then
    exec /bin/bash ~/.xsession
fi

if [ -f /usr/share/xsessions/ubuntu.desktop ]; then
    export XDG_CURRENT_DESKTOP="ubuntu:GNOME"
    export GNOME_SHELL_SESSION_MODE="ubuntu"
    SESSION="ubuntu"
else
    export XDG_CURRENT_DESKTOP="GNOME"
    export GNOME_SHELL_SESSION_MODE="gnome"
    SESSION="gnome"
fi

export XDG_DATA_DIRS="/usr/share/ubuntu:/usr/local/share:/usr/share"
export XDG_CONFIG_DIRS="/etc/xdg/xdg-ubuntu:/etc/xdg"
export DESKTOP_SESSION="${SESSION}"
export XDG_SESSION_TYPE="x11"
export GDMSESSION="${SESSION}"
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

exec dbus-run-session -- gnome-session --session="${SESSION}"
EOF
sudo chmod +x "${STARTWM}"

# 3c. XRDP sesman config (keep sessions alive on disconnect)
SESMAN_INI="/etc/xrdp/sesman.ini"
if [ -f "${SESMAN_INI}" ]; then
    sudo sed -i 's/^KillDisconnected=true/KillDisconnected=false/' "${SESMAN_INI}" 2>/dev/null || true
fi

# 3d. Xwrapper config (allow anybody to run X)
sudo mkdir -p /etc/X11
sudo tee /etc/X11/Xwrapper.config >/dev/null << 'EOF'
allowed_users=anybody
needs_root_rights=no
EOF

# 4. Configure Polkit to prevent authentication popups on headless sessions
echo "Configuring Polkit authorization bypass rules..."
sudo mkdir -p /etc/polkit-1/localauthority/50-local.d
sudo tee /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla >/dev/null << 'EOF'
[Allow Colord all Users]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF

sudo tee /etc/polkit-1/localauthority/50-local.d/45-allow-networkmanager.pkla >/dev/null << 'EOF'
[Allow NetworkManager all Users]
Identity=unix-user:*
Action=org.freedesktop.NetworkManager.*
ResultAny=yes
ResultInactive=no
ResultActive=yes
EOF

sudo tee /etc/polkit-1/localauthority/50-local.d/45-allow-packagekit.pkla >/dev/null << 'EOF'
[Allow PackageKit all Users]
Identity=unix-user:*
Action=org.freedesktop.packagekit.*;org.debian.apt.*
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF

# Modern Polkit JavaScript rules for Ubuntu 24.04 (polkit 120+)
sudo mkdir -p /etc/polkit-1/rules.d
sudo tee /etc/polkit-1/rules.d/02-allow-headless.rules >/dev/null << 'EOF'
polkit.addRule(function(action, subject) {
    if ((action.id.indexOf("org.freedesktop.color-manager.") === 0 ||
         action.id.indexOf("org.freedesktop.NetworkManager.") === 0 ||
         action.id.indexOf("org.freedesktop.packagekit.") === 0 ||
         action.id.indexOf("org.debian.apt.") === 0 ||
         action.id.indexOf("org.freedesktop.login1.") === 0) &&
        (subject.isInGroup("sudo") || subject.user === "nava")) {
        return polkit.Result.YES;
    }
});
EOF
sudo chmod 644 /etc/polkit-1/rules.d/02-allow-headless.rules 2>/dev/null || true

# 5. Configure OpenSSH Server
echo "Configuring OpenSSH Server..."
sudo mkdir -p /etc/ssh/sshd_config.d
sudo tee /etc/ssh/sshd_config.d/99-cloud-dev.conf >/dev/null << 'EOF'
PasswordAuthentication yes
PermitRootLogin no
PubkeyAuthentication yes
KbdInteractiveAuthentication yes
X11Forwarding yes
X11DisplayOffset 10
ClientAliveInterval 60
ClientAliveCountMax 10
EOF

# Ensure SSH host keys exist
sudo ssh-keygen -A 2>/dev/null || true

# 6. Start / Restart Services (socket-activation safe)
echo "Starting OpenSSH and XRDP services..."
sudo mkdir -p /run/sshd /var/run/sshd
sudo sshd -t 2>/dev/null || true

if systemctl is-active ssh.socket >/dev/null 2>&1 || systemctl list-unit-files ssh.socket >/dev/null 2>&1; then
    sudo systemctl restart ssh.socket || sudo systemctl restart ssh || sudo systemctl restart sshd || true
else
    sudo systemctl restart ssh || sudo systemctl restart sshd || sudo service ssh restart 2>/dev/null || true
fi

sudo systemctl restart xrdp-sesman 2>/dev/null || true
sudo systemctl restart xrdp 2>/dev/null || sudo service xrdp restart 2>/dev/null || true

echo "=================================================="
echo "✅ Ubuntu GNOME Desktop, XRDP & OpenSSH Configured"
echo "=================================================="
