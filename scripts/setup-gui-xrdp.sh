#!/usr/bin/env bash
# ==============================================================================
# setup-gui-xrdp.sh: Install & configure XFCE desktop, XRDP, and OpenSSH server
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

TARGET_USER="${TARGET_USER:-nava}"

echo "=================================================="
echo "🖥️  Installing & Configuring Ubuntu GUI (XFCE) + XRDP + SSH"
echo "=================================================="

# Pre-seed debconf selections to prevent hangs on keyboard-configuration & tzdata
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

echo "keyboard-configuration keyboard-configuration/layout select English" | sudo debconf-set-selections 2>/dev/null || true
echo "keyboard-configuration keyboard-configuration/layoutvariant select US" | sudo debconf-set-selections 2>/dev/null || true
echo "keyboard-configuration keyboard-configuration/model select Generic 105-key PC (intl.)" | sudo debconf-set-selections 2>/dev/null || true
echo "tzdata tzdata/Areas select Etc" | sudo debconf-set-selections 2>/dev/null || true
echo "tzdata tzdata/Zones select UTC" | sudo debconf-set-selections 2>/dev/null || true

# 1. Install lightweight XFCE, XRDP, and OpenSSH Server
sudo apt-get remove --purge -y needrestart 2>/dev/null || true
sudo rm -rf /etc/needrestart 2>/dev/null || true

sudo apt-get update -qq -o Acquire::http::Timeout="15" -o Acquire::Retries="3"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    -o Acquire::http::Timeout="15" -o Acquire::Retries="3" \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    --no-install-recommends \
    xfce4 \
    xfce4-terminal \
    xorgxrdp \
    xrdp \
    dbus-x11 \
    x11-xserver-utils \
    openssh-server \
    polkitd

# 2. Add xrdp user to ssl-cert group
sudo adduser xrdp ssl-cert 2>/dev/null || true

# 3. Configure XRDP window manager session startup (prevent black screen)
echo "Configuring XRDP session startup to prevent black screen issues..."

# 3a. User-level session file (.xsession)
XSESSION_FILE="/home/${TARGET_USER}/.xsession"
sudo tee "${XSESSION_FILE}" >/dev/null << 'EOF'
#!/usr/bin/env bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec startxfce4
EOF
sudo chmod +x "${XSESSION_FILE}"
sudo chown "${TARGET_USER}:${TARGET_USER}" "${XSESSION_FILE}"

# 3b. System-level XRDP startwm.sh patch
STARTWM="/etc/xrdp/startwm.sh"
if [ -f "${STARTWM}" ]; then
    if ! grep -q "unset DBUS_SESSION_BUS_ADDRESS" "${STARTWM}"; then
        sudo sed -i '1a unset DBUS_SESSION_BUS_ADDRESS\nunset XDG_RUNTIME_DIR' "${STARTWM}"
    fi
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

echo "=================================================="
echo "✅ GUI (XFCE) + XRDP + SSH Configured Successfully"
echo "=================================================="
