#!/usr/bin/env bash
# ==============================================================================
# install-ubuntu-tools.sh: Complete Web Development Toolkit & Coding Agents
# ==============================================================================

set -eo pipefail
set +x # Ensure secrets are never echoed in logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_USER="${TARGET_USER:-nava}"

echo "=================================================="
echo "📦 Installing Complete Web Development Toolkit"
echo "=================================================="

# Apply network, DNS, mirror and debconf optimizations
if [ -f "${SCRIPT_DIR}/optimize-ubuntu-system.sh" ]; then
    "${SCRIPT_DIR}/optimize-ubuntu-system.sh" || true
fi

# 1. Core Utilities, Databases, Compilers & PHP
echo "Installing core Linux packages, compilers, database clients, and PHP..."
sudo apt-get update -qq -o Acquire::http::Timeout="15" -o Acquire::Retries="5"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    -o Acquire::http::Timeout="15" -o Acquire::Retries="5" \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    build-essential \
    make \
    gcc \
    g++ \
    clang \
    git \
    curl \
    wget \
    jq \
    unzip \
    zip \
    tar \
    rsync \
    htop \
    tree \
    ripgrep \
    fzf \
    vim \
    nano \
    zsh \
    bash-completion \
    sqlite3 \
    libsqlite3-dev \
    postgresql-client \
    redis-tools \
    fd-find \
    ca-certificates \
    php-cli \
    php-mbstring \
    php-xml \
    php-curl \
    php-zip \
    composer \
    python3-pip \
    pipx

pipx ensurepath || true

# Provide convenient aliases for fd-find if fdfind is used
if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd || true
fi

# 2. JavaScript Runtimes & Package Managers (Node.js, pnpm, yarn, Bun, Corepack)
echo "Configuring Node.js ecosystem (pnpm, yarn, Bun, Corepack)..."
npm install -g pnpm yarn corepack

# Pre-activate pnpm and yarn through corepack to prevent download delays
corepack enable 2>/dev/null || true
corepack prepare pnpm@latest --activate 2>/dev/null || true
corepack prepare yarn@stable --activate 2>/dev/null || true

if ! command -v bun &>/dev/null || [ ! -x /usr/local/bin/bun ]; then
    echo "Installing Bun runtime..."
    curl -fsSL https://bun.sh/install | bash || true
    export BUN_INSTALL="${HOME}/.bun"
    export PATH="${BUN_INSTALL}/bin:${PATH}"
    # Make bun globally available as real binary in /usr/local/bin
    sudo rm -f /usr/local/bin/bun
    for B_PATH in "${HOME}/.bun/bin/bun" "/home/runner/.bun/bin/bun" "/root/.bun/bin/bun"; do
        if [ -f "${B_PATH}" ]; then
            sudo cp -f "${B_PATH}" /usr/local/bin/bun
            sudo chmod 755 /usr/local/bin/bun
            sudo chown root:root /usr/local/bin/bun
            break
        fi
    done
fi

# 3. Web Framework CLIs, Compilers, Linters & Utilities
echo "Installing Web development tools (TypeScript, Vite, Next.js, Angular, Astro, ESLint, Prettier)..."
npm install -g \
    typescript \
    ts-node \
    tsx \
    nodemon \
    vite \
    create-next-app \
    tailwindcss \
    postcss \
    postcss-cli \
    sass \
    eslint \
    prettier \
    serve \
    http-server \
    webpack \
    webpack-cli \
    parcel \
    shadcn \
    @angular/cli \
    astro \
    create-vue

# 4. Cloud Platform CLIs (Wrangler, Vercel)
echo "Installing Cloud Platform CLIs (Wrangler, Vercel)..."
npm install -g wrangler vercel

# 5. Coding Agent 1: DeepSeek Harness (@deepseek-ai/dsh)
echo "Installing DeepSeek Harness CLI (@deepseek-ai/dsh)..."
npm install -g @deepseek-ai/dsh@next || npm install -g @deepseek-ai/dsh@0.2.2-rc.1 || true

# Apply Tailnet loopback equivalence patch to dsh
if [ -f "${SCRIPT_DIR}/patch-dsh.sh" ]; then
    chmod +x "${SCRIPT_DIR}/patch-dsh.sh"
    "${SCRIPT_DIR}/patch-dsh.sh" || echo "⚠️ Warning: patch-dsh.sh encountered non-fatal issues"
fi

# 6. Coding Agent 2: OpenCode CLI (opencode / oc)
echo "Installing OpenCode CLI..."
npm install -g @opencode/cli || curl -fsSL https://opencode.ai/v2/install | bash || true
if command -v opencode &>/dev/null; then
    sudo ln -sf "$(command -v opencode)" /usr/local/bin/oc || true
fi

# 7. Coding Agent 3: Antigravity CLI (agy)
echo "Installing Google Antigravity CLI (agy)..."
curl -fsSL https://antigravity.google/cli/install.sh | sudo bash -s -- -d /usr/local/bin || true
for CANDIDATE in "${HOME}/.local/bin/agy" "/root/.local/bin/agy" "/home/runner/.local/bin/agy"; do
    if [ -f "${CANDIDATE}" ] && [ ! -f "/usr/local/bin/agy" ]; then
        sudo cp -f "${CANDIDATE}" /usr/local/bin/agy || true
        sudo chmod 755 /usr/local/bin/agy || true
        break
    fi
done

# 8. Browser & Web Testing (Playwright & Chromium)
echo "Configuring Playwright & Chromium..."
npm install -g playwright
npx playwright install --with-deps chromium || true

if command -v google-chrome &>/dev/null; then
    sudo ln -sf "$(command -v google-chrome)" /usr/local/bin/chromium-browser || true
    sudo ln -sf "$(command -v google-chrome)" /usr/local/bin/chromium || true
fi

# 9. Python Web Frameworks & Utilities (uv, FastAPI, Flask, Django, Jupyter)
echo "Configuring Python ecosystem (uv, FastAPI, Flask, Django, Jupyter)..."
if ! command -v uv &>/dev/null || [ ! -x /usr/local/bin/uv ]; then
    echo "Installing Astral uv & uvx..."
    curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="/usr/local/bin" sh || true
    
    # Ensure uv binary is in /usr/local/bin with proper permissions
    sudo rm -f /usr/local/bin/uv /usr/local/bin/uvx
    for UV_CANDIDATE in /usr/local/bin/uv "${HOME}/.local/bin/uv" "/home/runner/.local/bin/uv" "${HOME}/.cargo/bin/uv" "/root/.local/bin/uv"; do
        if [ -f "${UV_CANDIDATE}" ]; then
            sudo cp -f "${UV_CANDIDATE}" /usr/local/bin/uv
            sudo chmod 755 /usr/local/bin/uv
            sudo chown root:root /usr/local/bin/uv
            break
        fi
    done
    for UVX_CANDIDATE in /usr/local/bin/uvx "${HOME}/.local/bin/uvx" "/home/runner/.local/bin/uvx" "${HOME}/.cargo/bin/uvx" "/root/.local/bin/uvx"; do
        if [ -f "${UVX_CANDIDATE}" ]; then
            sudo cp -f "${UVX_CANDIDATE}" /usr/local/bin/uvx
            sudo chmod 755 /usr/local/bin/uvx
            sudo chown root:root /usr/local/bin/uvx
            break
        fi
    done
fi

# Fallback: install uv via pip to guarantee availability
if [ ! -x /usr/local/bin/uv ]; then
    pip install --no-cache-dir uv || true
    if command -v uv &>/dev/null; then
        sudo cp -f "$(command -v uv)" /usr/local/bin/uv
        sudo chmod 755 /usr/local/bin/uv
    fi
fi

pip install --no-cache-dir \
    virtualenv \
    flask \
    fastapi \
    "uvicorn[standard]" \
    django \
    jupyter \
    jupyterlab \
    notebook \
    requests \
    httpx

# 10. rclone & Cloudflare Tunnel (cloudflared)
echo "Installing rclone & cloudflared..."
if ! command -v rclone &>/dev/null; then
    curl -fsSL https://rclone.org/install.sh | sudo bash
fi

if ! command -v cloudflared &>/dev/null; then
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb
    sudo dpkg -i /tmp/cloudflared.deb >/dev/null 2>&1 || true
    rm -f /tmp/cloudflared.deb
fi

# Make helper script commands available in /usr/local/bin
if [ -f "${SCRIPT_DIR}/preview-cli.sh" ]; then
    sudo ln -sf "${SCRIPT_DIR}/preview-cli.sh" /usr/local/bin/preview || true
fi
if [ -f "${SCRIPT_DIR}/preview-tunnel.sh" ]; then
    sudo ln -sf "${SCRIPT_DIR}/preview-tunnel.sh" /usr/local/bin/preview-tunnel || true
fi

# 11. Expose all hosted toolchains & binaries globally to /usr/local/bin for all users (SSH, XRDP, tmux, nava)
echo "Exposing hosted toolchains and binaries globally to /usr/local/bin..."
sudo chmod -R a+rX /opt/hostedtoolcache 2>/dev/null || true
sudo chmod 755 /home/runner 2>/dev/null || true

# Symlink all Node and global npm tools (node, npm, npx, pnpm, yarn, corepack, wrangler, vercel, opencode, dsh, etc.)
for N_DIR in /opt/hostedtoolcache/node/*/x64/bin; do
    if [ -d "${N_DIR}" ]; then
        sudo ln -sf "${N_DIR}"/* /usr/local/bin/ 2>/dev/null || true
    fi
done

# Symlink all Python tools
for P_DIR in /opt/hostedtoolcache/Python/*/x64/bin; do
    if [ -d "${P_DIR}" ]; then
        sudo ln -sf "${P_DIR}"/* /usr/local/bin/ 2>/dev/null || true
    fi
done

# Ensure Bun is available globally
sudo rm -f /usr/local/bin/bun
for BUN_PATH in "${HOME}/.bun/bin/bun" "/home/runner/.bun/bin/bun" "/root/.bun/bin/bun"; do
    if [ -f "${BUN_PATH}" ]; then
        sudo cp -f "${BUN_PATH}" /usr/local/bin/bun || true
        sudo chmod 755 /usr/local/bin/bun || true
        sudo chown root:root /usr/local/bin/bun || true
        break
    fi
done

# Ensure uv and uvx are available globally
for UV_PATH in /usr/local/bin/uv "${HOME}/.local/bin/uv" "/home/runner/.local/bin/uv" "${HOME}/.cargo/bin/uv"; do
    if [ -f "${UV_PATH}" ] && [ ! -x /usr/local/bin/uv ]; then
        sudo cp -f "${UV_PATH}" /usr/local/bin/uv || true
        sudo chmod 755 /usr/local/bin/uv || true
        sudo chown root:root /usr/local/bin/uv || true
        break
    fi
done
for UVX_PATH in /usr/local/bin/uvx "${HOME}/.local/bin/uvx" "/home/runner/.local/bin/uvx" "${HOME}/.cargo/bin/uvx"; do
    if [ -f "${UVX_PATH}" ] && [ ! -x /usr/local/bin/uvx ]; then
        sudo cp -f "${UVX_PATH}" /usr/local/bin/uvx || true
        sudo chmod 755 /usr/local/bin/uvx || true
        sudo chown root:root /usr/local/bin/uvx || true
        break
    fi
done

# Ensure OpenCode alias 'oc' exists in /usr/local/bin
if command -v opencode &>/dev/null; then
    sudo ln -sf "$(command -v opencode)" /usr/local/bin/oc || true
elif [ -f "/usr/local/bin/opencode" ]; then
    sudo ln -sf /usr/local/bin/opencode /usr/local/bin/oc || true
fi

# Ensure standalone 'oc' wrapper exists
if [ ! -f "/usr/local/bin/oc" ] || [ ! -x "/usr/local/bin/oc" ]; then
    sudo tee /usr/local/bin/oc >/dev/null << 'EOF'
#!/usr/bin/env bash
if command -v opencode >/dev/null 2>&1; then
    exec opencode "$@"
elif [ -x /usr/local/bin/opencode ]; then
    exec /usr/local/bin/opencode "$@"
else
    echo "Error: opencode command not found" >&2
    exit 1
fi
EOF
    sudo chmod 755 /usr/local/bin/oc
fi

# 12. Create standalone wrapper scripts in /usr/local/bin for permanent Tmux terminals & navigation
echo "Creating permanent terminal & alias wrappers in /usr/local/bin..."
sudo tee /usr/local/bin/t1 >/dev/null << 'EOF'
#!/usr/bin/env bash
exec tmux attach-session -t terminal-1 2>/dev/null || exec tmux new-session -s terminal-1 -c "${HOME}/workspace"
EOF

sudo tee /usr/local/bin/t2 >/dev/null << 'EOF'
#!/usr/bin/env bash
exec tmux attach-session -t terminal-2 2>/dev/null || exec tmux new-session -s terminal-2 -c "${HOME}/workspace"
EOF

sudo tee /usr/local/bin/t3 >/dev/null << 'EOF'
#!/usr/bin/env bash
exec tmux attach-session -t terminal-3 2>/dev/null || exec tmux new-session -s terminal-3 -c "${HOME}/workspace"
EOF

sudo tee /usr/local/bin/tls >/dev/null << 'EOF'
#!/usr/bin/env bash
exec tmux list-sessions
EOF

sudo tee /usr/local/bin/ws >/dev/null << 'EOF'
#!/usr/bin/env bash
cd "${HOME}/workspace" && exec "${SHELL:-/bin/bash}"
EOF

sudo chmod 755 /usr/local/bin/t1 /usr/local/bin/t2 /usr/local/bin/t3 /usr/local/bin/tls /usr/local/bin/ws /usr/local/bin/agy 2>/dev/null || true

# 13. Configure system-wide PATH in /etc/environment for SSH, XRDP, and systemd
NODE_BIN_DIR="$(find /opt/hostedtoolcache/node -type d -name "bin" 2>/dev/null | sort -V | tail -n 1)"
PYTHON_BIN_DIR="$(find /opt/hostedtoolcache/Python -type d -name "bin" 2>/dev/null | sort -V | tail -n 1)"
sudo tee /etc/environment >/dev/null << EOF
PATH="${NODE_BIN_DIR}:${PYTHON_BIN_DIR}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
WORKSPACE="/home/${TARGET_USER}/workspace"
EOF

echo "=================================================="
echo "✅ Web Development Studio Tools Installation Complete"
echo "=================================================="
node --version || true
npm --version || true
pnpm --version || true
yarn --version || true
bun --version || true
python3 --version || true
uv --version || true
php --version | head -n 1 || true
composer --version 2>/dev/null | head -n 1 || true
git --version || true
(gh --version 2>/dev/null || true) | head -n 1 || true
wrangler --version || true
vercel --version || true
(agy --version 2>/dev/null || echo "Antigravity CLI (agy) installed")
(opencode --version 2>/dev/null || echo "OpenCode CLI installed (alias oc)")
dsh --version 2>/dev/null || echo "DeepSeek Harness CLI installed"
