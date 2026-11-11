#!/usr/bin/env bash
# ==============================================================================
# setup-gui-xrdp.sh: Install & configure XFCE desktop, XRDP, and OpenSSH server
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${TARGET_USER:-nava}"

echo "=================================================="
echo "🖥️  Installing & Configuring Ubuntu GUI (XFCE) + XRDP + SSH"
echo "=================================================="

# Apply network, DNS, mirror and debconf optimizations
if [ -f "${SCRIPT_DIR}/optimize-ubuntu-system.sh" ]; then
    "${SCRIPT_DIR}/optimize-ubuntu-system.sh" || true
fi

# 1. Install lightweight XFCE core, XRDP, and OpenSSH Server
sudo apt-get update -qq -o Acquire::http::Timeout="15" -o Acquire::Retries="5"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    -o Acquire::http::Timeout="15" -o Acquire::Retries="5" \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    xfce4-session \
    xfconf \
    xfwm4 \
    xfdesktop4 \
    xfce4-panel \
    xfce4-settings \
    xfce4-terminal \
    xfce4-appfinder \
    thunar \
    xinit \
    xorgxrdp \
    xrdp \
    dbus-x11 \
    dbus-user-session \
    x11-xserver-utils \
    openssh-server \
    polkitd

# 2. Add users to ssl-cert group
sudo adduser xrdp ssl-cert 2>/dev/null || true
sudo adduser "${TARGET_USER}" ssl-cert 2>/dev/null || true

# 3. Configure XRDP window manager session startup (prevent failsafe & black screen issues)
echo "Configuring XRDP session startup with D-Bus support..."

# 3a. User-level session files (.xsession & .xsessionrc)
XSESSION_FILE="/home/${TARGET_USER}/.xsession"
sudo tee "${XSESSION_FILE}" >/dev/null << 'EOF'
#!/usr/bin/env bash
export XDG_CURRENT_DESKTOP="XFCE"
export XDG_MENU_PREFIX="xfce-"
export XDG_CONFIG_DIRS="/etc/xdg"
export XDG_DATA_DIRS="/usr/local/share:/usr/share"
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec dbus-launch --exit-with-session startxfce4
EOF
sudo chmod +x "${XSESSION_FILE}"
sudo cp -p "${XSESSION_FILE}" "/home/${TARGET_USER}/.xsessionrc"

# Create initial XFCE config directories and enforce strict user ownership
sudo -u "${TARGET_USER}" mkdir -p "/home/${TARGET_USER}/.config/xfce4" "/home/${TARGET_USER}/.cache"
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

export XDG_CURRENT_DESKTOP="XFCE"
export XDG_MENU_PREFIX="xfce-"
export XDG_CONFIG_DIRS="/etc/xdg"
export XDG_DATA_DIRS="/usr/local/share:/usr/share"
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

if [ -f ~/.xsession ]; then
    exec /bin/bash ~/.xsession
fi

exec dbus-launch --exit-with-session startxfce4
EOF
sudo chmod +x "${STARTWM}"

# 3c. XRDP sesman config (keep sessions alive on disconnect)
SESMAN_INI="/etc/xrdp/sesman.ini"
if [ -f "${SESMAN_INI}" ]; then
    sudo sed -i 's/^KillDisconnected=true/KillDisconnected=false/' "${SESMAN_INI}" 2>/dev/null || true
fi

# 3c. Xwrapper config (allow anybody to run X)
sudo mkdir -p /etc/X11
sudo tee /etc/X11/Xwrapper.config >/dev/null << 'EOF'
allowed_users=anybody
needs_root_rights=no
EOF

# 4. Configure Polkit to avoid authentication prompts for color management & power
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
sudo systemctl daemon-reload 2>/dev/null || true

timeout 5s sudo systemctl restart ssh.socket 2>/dev/null || \
timeout 5s sudo systemctl restart ssh 2>/dev/null || \
timeout 5s sudo service ssh restart 2>/dev/null || \
sudo /usr/sbin/sshd 2>/dev/null || true

timeout 5s sudo systemctl restart xrdp 2>/dev/null || \
timeout 5s sudo service xrdp restart 2>/dev/null || \
(sudo xrdp-sesman 2>/dev/null; sudo xrdp 2>/dev/null) || true

# 7. Verify listening ports
sleep 2
echo "Verifying services:"
if ss -tln | grep -q ":22 "; then
    echo "✅ OpenSSH Server is listening on port 22."
else
    echo "⚠️ Warning: OpenSSH Server may not be listening on port 22."
fi

if ss -tln | grep -q ":3389 "; then
    echo "✅ XRDP Server is listening on port 3389."
else
    echo "⚠️ Warning: XRDP Server may not be listening on port 3389."
fi

# 8. Verify XFCE desktop & D-Bus components
echo "Verifying XFCE desktop & D-Bus components..."
if command -v xfce4-session &>/dev/null; then
    echo "✅ xfce4-session available: $(command -v xfce4-session)"
else
    echo "❌ Error: xfce4-session is not found!" >&2
    exit 1
fi

if command -v dbus-launch &>/dev/null; then
    echo "✅ dbus-launch available: $(command -v dbus-launch)"
else
    echo "❌ Error: dbus-launch is not found!" >&2
    exit 1
fi

if command -v xfconf-query &>/dev/null; then
    echo "✅ xfconf-query available: $(command -v xfconf-query)"
fi

echo "=================================================="
echo "✅ GUI (XFCE) + XRDP + SSH Configured Successfully"
echo "=================================================="
