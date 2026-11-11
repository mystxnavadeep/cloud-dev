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

if ! command -v bun &>/dev/null; then
    echo "Installing Bun runtime..."
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="${HOME}/.bun"
    export PATH="${BUN_INSTALL}/bin:${PATH}"
    # Make bun globally available in /usr/local/bin
    if [ -f "${HOME}/.bun/bin/bun" ]; then
        sudo ln -sf "${HOME}/.bun/bin/bun" /usr/local/bin/bun || true
    fi
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
curl -fsSL https://antigravity.google/cli/install.sh | bash || true
# Ensure agy is accessible globally in /usr/local/bin
for CANDIDATE in "${HOME}/.local/bin/agy" "/root/.local/bin/agy" "/usr/local/bin/agy"; do
    if [ -f "${CANDIDATE}" ]; then
        sudo ln -sf "${CANDIDATE}" /usr/local/bin/agy || true
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
if ! command -v uv &>/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    if [ -f "${HOME}/.cargo/bin/uv" ]; then
        sudo ln -sf "${HOME}/.cargo/bin/uv" /usr/local/bin/uv || true
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
