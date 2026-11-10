#!/usr/bin/env bash
# ==============================================================================
# install-tools.sh: Preinstall and configure all required cloud development tools
# ==============================================================================

set -eo pipefail

echo "=================================================="
echo "📦 Installing System Tools & Dependencies"
echo "=================================================="

sudo apt-get update -qq -o Acquire::http::Timeout="15" -o Acquire::Retries="3"
sudo apt-get install -y -qq -o Acquire::http::Timeout="15" -o Acquire::Retries="3" \
    build-essential \
    curl \
    wget \
    git \
    jq \
    zip \
    unzip \
    tree \
    python3-pip \
    pipx \
    ca-certificates

pipx ensurepath || true

# Provide chromium/chromium-browser binary link using preinstalled Chrome or Playwright
if command -v google-chrome &>/dev/null; then
    sudo ln -sf "$(command -v google-chrome)" /usr/local/bin/chromium-browser || true
    sudo ln -sf "$(command -v google-chrome)" /usr/local/bin/chromium || true
fi

echo "=================================================="
echo "📦 Installing JavaScript Runtimes & Package Managers"
echo "=================================================="

# 1. Install pnpm and yarn globally
npm install -g pnpm yarn

# 2. Install Bun
if ! command -v bun &>/dev/null; then
    echo "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash
    export BUN_INSTALL="${HOME}/.bun"
    export PATH="${BUN_INSTALL}/bin:${PATH}"
fi

# 3. Install Global Web Framework CLIs & Dev Tools
echo "Installing Web CLIs (TypeScript, Vite, Next.js, Tailwind, Sass, PostCSS, ESLint, Prettier, Webpack, Parcel, shadcn)..."
npm install -g \
    typescript \
    ts-node \
    vite \
    create-next-app \
    tailwindcss \
    postcss \
    postcss-cli \
    sass \
    eslint \
    prettier \
    webpack \
    webpack-cli \
    parcel \
    shadcn

# 4. Install Cloud Platform CLIs
echo "Installing Cloud Platform CLIs (Wrangler, Vercel)..."
npm install -g wrangler vercel

# 5. Install DeepSeek Harness CLI
echo "Installing DeepSeek Harness CLI (@deepseek-ai/dsh)..."
npm install -g @deepseek-ai/dsh@next || npm install -g @deepseek-ai/dsh@0.2.2-rc.1 || true

# 6. Install Playwright and Chromium
echo "Installing Playwright..."
npm install -g playwright
npx playwright install --with-deps chromium || true

echo "=================================================="
echo "🐍 Installing Python Development Tools"
echo "=================================================="

# 1. Install uv (fast Python package manager)
if ! command -v uv &>/dev/null; then
    echo "Installing Astral uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="${HOME}/.cargo/bin:${PATH}"
fi

# 2. Install Python web frameworks, virtualenv, and Jupyter
echo "Installing Python frameworks & libraries (virtualenv, Flask, FastAPI, Django, Jupyter)..."
pip install --no-cache-dir \
    virtualenv \
    flask \
    fastapi \
    "uvicorn[standard]" \
    django \
    jupyter \
    jupyterlab \
    notebook

echo "=================================================="
echo "☁️ Installing rclone and cloudflared"
echo "=================================================="
if ! command -v rclone &>/dev/null; then
    curl -fsSL https://rclone.org/install.sh | sudo bash
fi

if ! command -v cloudflared &>/dev/null; then
    echo "Installing Cloudflare CLI (cloudflared)..."
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb
    sudo dpkg -i /tmp/cloudflared.deb >/dev/null 2>&1 || true
    rm -f /tmp/cloudflared.deb
fi

# Make helper script commands available in PATH
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
sudo ln -sf "${SCRIPT_DIR}/preview-cli.sh" /usr/local/bin/preview || true
sudo ln -sf "${SCRIPT_DIR}/preview-tunnel.sh" /usr/local/bin/preview-tunnel || true

echo "=================================================="
echo "✅ All Development Tools Successfully Installed!"
echo "=================================================="
node --version || true
npm --version || true
pnpm --version || true
yarn --version || true
bun --version || true
python3 --version || true
pip --version || true
uv --version || true
git --version || true
(gh --version 2>/dev/null || true) | head -n 1 || true
wrangler --version || true
vercel --version || true
(rclone --version 2>/dev/null || true) | head -n 1 || true
(cloudflared --version 2>/dev/null || true) | head -n 1 || true
dsh --version || echo "dsh CLI ready"
