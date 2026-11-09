#!/usr/bin/env bash
# ==============================================================================
# install-tools.sh: Preinstall and configure all required cloud development tools
# ==============================================================================

set -eo pipefail

echo "=================================================="
echo "📦 Installing System Tools & Dependencies"
echo "=================================================="

sudo apt-get update -qq
sudo apt-get install -y -qq \
    build-essential \
    curl \
    wget \
    git \
    jq \
    zip \
    unzip \
    tree \
    chromium-browser \
    python3-pip \
    pipx \
    ca-certificates

# Ensure pipx path
pipx ensurepath || true

echo "=================================================="
echo "📦 Installing JavaScript Runtimes & Package Managers"
echo "=================================================="

# 1. Install pnpm and yarn globally
npm install -g pnpm yarn

# 2. Install Bun
if ! command -v bun &>/dev/null; then
    echo "Installing Bun..."
    curl -fsSL https://bun.sh/install | bash
    # Export for current session and downstream bashrc
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
npm install -g @deepseek-ai/dsh

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
echo "☁️ Installing rclone"
echo "=================================================="
if ! command -v rclone &>/dev/null; then
    curl -fsSL https://rclone.org/install.sh | sudo bash
fi

# Make helper script commands available in PATH
sudo ln -sf "${PWD}/scripts/preview-cli.sh" /usr/local/bin/preview || true

echo "=================================================="
echo "✅ All Development Tools Successfully Installed!"
echo "=================================================="
node --version
npm --version
pnpm --version
yarn --version
bun --version || true
python3 --version
pip --version
uv --version || true
git --version
gh --version | head -n 1
wrangler --version || true
vercel --version || true
rclone --version | head -n 1
dsh --version || echo "dsh CLI ready"
