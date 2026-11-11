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

# Configure non-interactive debconf & force IPv4
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4 >/dev/null 2>&1 || true

# Purge needrestart to avoid restarting runner services (e.g. hosted-compute-agent)
sudo apt-get remove --purge -y needrestart 2>/dev/null || true
sudo rm -rf /etc/needrestart 2>/dev/null || true

# Clear any concurrent apt locks
sudo systemctl stop unattended-upgrades apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
sudo killall apt apt-get dpkg unattended-upgrade 2>/dev/null || true
sudo rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock* 2>/dev/null || true
sudo dpkg --configure -a 2>/dev/null || true

# 1. Install lightweight XFCE, XRDP, and OpenSSH Server
sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq -o Acquire::ForceIPv4=true -o Acquire::http::Timeout="15" -o Acquire::Retries="3"
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    -o Acquire::ForceIPv4=true \
    -o Acquire::http::Timeout="15" \
    -o Acquire::Retries="3" \
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

# 6. Start / Restart Services
echo "Starting OpenSSH and XRDP services..."
sudo service ssh restart || sudo systemctl restart ssh || true
sudo service xrdp restart || sudo systemctl restart xrdp || true

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
