#!/usr/bin/env bash
# ==============================================================================
# init-templates.sh: Initialize example projects for website preview
# ==============================================================================

set -eo pipefail

GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-/home/runner}"
WORKSPACE_DIR="${WORKSPACE_DIR:-${GITHUB_WORKSPACE}/workspace}"
EXAMPLES_DIR="${WORKSPACE_DIR}/examples"

mkdir -p "${EXAMPLES_DIR}"

# 1. React + Vite + Tailwind CSS + Lucide starter
VITE_DIR="${EXAMPLES_DIR}/react-vite-app"
if [ ! -d "${VITE_DIR}" ]; then
    echo "Creating React + Vite + Tailwind starter..."
    mkdir -p "${VITE_DIR}/src"

    cat << 'EOF' > "${VITE_DIR}/package.json"
{
  "name": "react-vite-app",
  "private": true,
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite --host 0.0.0.0 --port 5173",
    "build": "vite build",
    "preview": "vite preview --host 0.0.0.0 --port 4173"
  },
  "dependencies": {
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "lucide-react": "^0.460.0"
  },
  "devDependencies": {
    "@types/react": "^18.3.12",
    "@types/react-dom": "^18.3.1",
    "@vitejs/plugin-react": "^4.3.3",
    "autoprefixer": "^10.4.20",
    "postcss": "^8.4.49",
    "tailwindcss": "^3.4.15",
    "vite": "^5.4.11"
  }
}
EOF

    cat << 'EOF' > "${VITE_DIR}/index.html"
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Private Cloud Dev Preview</title>
  </head>
  <body class="bg-slate-900 text-white min-h-screen flex items-center justify-center">
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
EOF

    cat << 'EOF' > "${VITE_DIR}/src/main.jsx"
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App.jsx'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
EOF

    cat << 'EOF' > "${VITE_DIR}/src/App.jsx"
import React from 'react'
import { Cloud, Lock, Sparkles } from 'lucide-react'

export default function App() {
  return (
    <div className="p-8 max-w-xl mx-auto text-center space-y-6">
      <div className="inline-flex items-center justify-center p-4 bg-emerald-500/10 rounded-2xl border border-emerald-500/20 text-emerald-400">
        <Lock className="w-10 h-10 mr-3" />
        <Cloud className="w-10 h-10" />
      </div>
      <h1 className="text-3xl font-bold tracking-tight">Private Tailscale Website Preview</h1>
      <p className="text-slate-400">
        This React + Vite application is running inside your persistent GitHub Actions cloud environment and previewed strictly over your private Tailnet.
      </p>
      <div className="p-4 bg-slate-800/60 rounded-xl border border-slate-700 text-sm font-mono text-emerald-300">
        npm run dev -- --host 0.0.0.0
      </div>
    </div>
  )
}
EOF

    cat << 'EOF' > "${VITE_DIR}/src/index.css"
@tailwind base;
@tailwind components;
@tailwind utilities;
EOF

    cat << 'EOF' > "${VITE_DIR}/tailwind.config.js"
export default {
  content: ["./index.html", "./src/**/*.{js,ts,jsx,tsx}"],
  theme: { extend: {} },
  plugins: [],
}
EOF

    cat << 'EOF' > "${VITE_DIR}/vite.config.js"
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 5173
  }
})
EOF
fi

# 2. FastAPI Python Starter
PYTHON_DIR="${EXAMPLES_DIR}/python-fastapi"
if [ ! -d "${PYTHON_DIR}" ]; then
    echo "Creating FastAPI starter..."
    mkdir -p "${PYTHON_DIR}"

    cat << 'EOF' > "${PYTHON_DIR}/main.py"
from fastapi import FastAPI
from fastapi.responses import HTMLResponse

app = FastAPI(title="Private Tailscale FastAPI Preview")

@app.get("/", response_class=HTMLResponse)
def index():
    return """
    <!DOCTYPE html>
    <html>
    <head>
        <title>FastAPI Tailscale Preview</title>
        <style>
            body { font-family: -apple-system, sans-serif; background: #0f172a; color: white; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
            .card { background: #1e293b; padding: 2rem; border-radius: 12px; max-width: 500px; text-align: center; border: 1px solid #334155; }
            h1 { color: #38bdf8; }
            code { background: #0f172a; padding: 0.2rem 0.5rem; border-radius: 4px; color: #4ade80; }
        </style>
    </head>
    <body>
        <div class="card">
            <h1>🐍 FastAPI on Tailscale</h1>
            <p>Your Python web app is running securely in the cloud runner.</p>
            <p>Start it with: <code>uvicorn main:app --host 0.0.0.0 --port 8000 --reload</code></p>
        </div>
    </body>
    </html>
    """
EOF
fi

echo "✅ Example templates initialized in ${EXAMPLES_DIR}."
