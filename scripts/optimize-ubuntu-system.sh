#!/usr/bin/env bash
# ==============================================================================
# optimize-ubuntu-system.sh: Network, DNS, Mirror, and APT Optimization
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

echo "=================================================="
echo "⚡ Optimizing Network, DNS & System Performance"
echo "=================================================="

# 1. Ensure local runner hostname resolves in /etc/hosts to prevent PAM/sudo/NSS latency
RUNNER_HOST="$(hostname 2>/dev/null || echo 'localhost')"
if ! grep -q "${RUNNER_HOST}" /etc/hosts 2>/dev/null; then
    echo "127.0.0.1 ${RUNNER_HOST}" | sudo tee -a /etc/hosts >/dev/null 2>&1 || true
    echo "✅ Bound hostname '${RUNNER_HOST}' in /etc/hosts."
fi

# 2. Configure robust DNS (Google & Cloudflare) to prevent azure.archive.ubuntu.com DNS failures
sudo tee /etc/resolv.conf >/dev/null << 'EOF'
nameserver 8.8.8.8
nameserver 1.1.1.1
nameserver 8.8.4.4
options timeout:2 attempts:3
EOF
echo "✅ Configured robust DNS nameservers (8.8.8.8, 1.1.1.1)."

# 3. Replace flaky azure.archive.ubuntu.com mirror with official main archive
sudo sed -i 's|azure.archive.ubuntu.com|archive.ubuntu.com|g' \
    /etc/apt/sources.list \
    /etc/apt/sources.list.d/*.sources \
    /etc/apt/sources.list.d/*.list \
    /etc/apt/apt-mirrors.txt 2>/dev/null || true
echo "✅ Switched APT mirrors to official archive.ubuntu.com."

# 4. Pre-seed debconf and keyboard configs so apt never prompts on stdin
sudo mkdir -p /etc/default
sudo tee /etc/default/keyboard >/dev/null << 'EOF'
XKBMODEL="pc105"
XKBLAYOUT="us"
XKBVARIANT=""
XKBOPTIONS=""
EOF
sudo ln -fs /usr/share/zoneinfo/UTC /etc/localtime 2>/dev/null || true
echo "Etc/UTC" | sudo tee /etc/timezone >/dev/null 2>&1 || true

export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none

echo "keyboard-configuration keyboard-configuration/layout select English" | sudo debconf-set-selections 2>/dev/null || true
echo "keyboard-configuration keyboard-configuration/layoutvariant select US" | sudo debconf-set-selections 2>/dev/null || true
echo "keyboard-configuration keyboard-configuration/model select Generic 105-key PC (intl.)" | sudo debconf-set-selections 2>/dev/null || true
echo "tzdata tzdata/Areas select Etc" | sudo debconf-set-selections 2>/dev/null || true
echo "tzdata tzdata/Zones select UTC" | sudo debconf-set-selections 2>/dev/null || true
echo "✅ Configured noninteractive keyboard and timezone."

# 5. Purge needrestart to prevent restarting hosted-compute-agent and freezing the runner
sudo apt-get remove --purge -y needrestart 2>/dev/null || true
sudo rm -rf /etc/needrestart 2>/dev/null || true
echo "✅ Needrestart purged."

echo "=================================================="
echo "✅ System & Network Optimization Complete"
echo "=================================================="
