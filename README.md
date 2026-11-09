# ☁️ Cloud Dev: Persistent Cloud Development Environment

[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-Cloud_Runner-2088FF?logo=github-actions&logoColor=white)](https://github.com/features/actions)
[![Storage](https://img.shields.io/badge/Storage-Google_Drive_(gdrive)-34A853?logo=googledrive&logoColor=white)](https://rclone.org/drive/)
[![DeepSeek Harness](https://img.shields.io/badge/DeepSeek_Harness-v0.2-brightgreen)](https://github.com/deepseek-ai/dsh)
[![Cloudflare](https://img.shields.io/badge/Preview-On--Demand_Tunnels-F38020?logo=cloudflare&logoColor=white)](https://www.cloudflare.com/)
[![Tailscale](https://img.shields.io/badge/Private_Access-Tailscale-111827?logo=tailscale&logoColor=white)](https://tailscale.com/)

A full-featured, persistent cloud development environment running inside GitHub Actions. Powered by **DeepSeek Harness (`dsh`)**, preloaded with modern web and Python toolchains, featuring persistent storage backed by **Google Drive (`gdrive:cloud-dev/workspace`)** with automatic 5-minute sync, and supporting on-demand private website previews.

---

## 📑 Architecture Overview

```
 ┌────────────────────────────────────────────────────────────────────────┐
 │                    GitHub Actions Runner (Ubuntu)                      │
 │                                                                        │
 │   ┌──────────────────────┐              ┌──────────────────────────┐   │
 │   │     Google Drive     │ ──(Restore)─>│   workspace/             │   │
 │   │  gdrive:cloud-dev/   │ <──(5m Sync)─│   (Source code, configs, │   │
 │   │      workspace       │ <──(Final)── │    project files, .dsh)  │   │
 │   └──────────────────────┘              └────────────┬─────────────┘   │
 │                                                      │                 │
 │                                                      ▼                 │
 │                                         ┌──────────────────────────┐   │
 │                                         │     DeepSeek Harness     │   │
 │                                         │    Web UI (Port 3080)    │   │
 │                                         └────────────┬─────────────┘   │
 │                                                      │                 │
 │   ┌──────────────────────────────────────────────────┴─────────────┐   │
 │   │                     Preview Services                           │   │
 │   │                                                                │   │
 │   │  • On-Demand Cloudflare Tunnel:  preview tunnel <port>         │   │
 │   │  • Private Tailscale Network:    http://100.x.y.z:<port>       │   │
 │   │  • Development Servers:          Vite, Next.js, FastAPI, Flask │   │
 │   └────────────────────────────────────────────────────────────────┘   │
 └────────────────────────────────────────────────────────────────────────┘
```

---

## 💾 Google Drive Workspace Persistence

All your project files, source code, build artifacts, and agent state live in the persistent `workspace/` directory.

### Where Files Are Stored
- **Remote Google Drive Path:** `gdrive:cloud-dev/workspace`
- **Local Runner Path:** `workspace/` (relative to repository root; also symlinked to `/home/runner/workspace`)
- **Safety Trash Directory:** `gdrive:cloud-dev/trash/<timestamp>` (replaces or deletions are archived in trash to prevent accidental data loss)

### 1. Automatic Workspace Restore (Startup)
When a workflow session starts:
- rclone decodes the `RCLONE_CONFIG_B64` secret securely into `$HOME/.config/rclone/rclone.conf` with `600` permissions.
- Verifies connectivity to the `gdrive:` remote.
- Downloads previous files from `gdrive:cloud-dev/workspace` into local `workspace/`.
- **First-Run Safe:** If the remote directory is empty or new, it initializes cleanly with starter documentation and templates without failing.
- **Overwrite Protection:** Verifies restored files before proceeding; never overwrites restored files with an empty workspace.

### 2. Automatic Sync Every 5 Minutes (Runtime)
While your session is active:
- A background synchronization daemon runs every **300 seconds (5 minutes)**.
- Uses file-descriptor locking (`flock`) to **prevent overlapping sync processes**.
- Synchronizes changes to `gdrive:cloud-dev/workspace`.
- Captures errors gracefully in logs without stopping development or leaking secrets.

### 3. Final Backup (Shutdown)
When the session finishes, times out (up to 6 hours), or is cancelled:
- Triggered automatically via GitHub Actions `if: always()`.
- Stops the background sync daemon cleanly.
- Executes a final synchronization upload to Google Drive.
- Confirms file counts and reports backup status in the GitHub Actions Job Summary.

---

## 🌐 Preview Behavior (On-Demand Tunnels)

To protect your privacy and bandwidth:
- **No Automatic Public Tunnels:** The environment does **NOT** automatically create public Cloudflare Quick Tunnels on startup.
- **On-Demand Tunnels:** A temporary Cloudflare Quick Tunnel is generated **only when explicitly requested** from DeepSeek Harness or via the CLI:
  ```bash
  preview tunnel <port>
  # Example for a React/Vite dev server:
  preview tunnel 5173
  ```
- **Persistent Previews:** Once started, the preview server and tunnel remain active in the background for the entire session.
- **Tailscale Private Previews:** If you configure Tailscale, dev servers bound to `0.0.0.0` are also directly reachable over your private Tailnet (`http://<TAILSCALE_IP>:<PORT>`).

### Developer Preview CLI
Use the pre-installed `preview` command inside your workspace terminal:
```bash
preview list               # List all running dev servers and active tunnels
preview tunnel <port>      # Spawn a temporary Cloudflare Quick Tunnel for <port>
preview serve <dir> [port] # Instantly serve a static folder locally (e.g. preview serve ./dist 8080)
preview info               # Display workspace and network identity
```

---

## 🧰 Preinstalled Development Toolchain

### Web & JavaScript
- **Runtimes & Package Managers:** Node.js LTS (v20), npm, pnpm, yarn, Bun.
- **Frameworks & Scaffolding:** React, Vite, Next.js (`create-next-app`), TypeScript (`ts-node`), Tailwind CSS, shadcn/ui, Bootstrap, Sass, PostCSS, Webpack, Parcel.
- **Animation, Graphics & Icons:** Framer Motion, Three.js, Lucide icons.
- **Linters & Formatters:** ESLint, Prettier.

### Python Environment
- **Python:** Python 3.11 with pip.
- **Tools:** Astral `uv` (fast package installer), `pipx`, `virtualenv`.
- **Frameworks & Notebooks:** Flask, FastAPI, Uvicorn, Django, Jupyter Notebook, JupyterLab.

### System, Testing & Cloud Tools
- **System:** Git, GitHub CLI (`gh`), curl, wget, jq, zip/unzip, build-essential (`gcc`, `g++`, `make`), tree.
- **Browsers & Testing:** Chromium, Playwright (with installed Chromium binary).
- **Cloud Platform CLIs:** Cloudflare Wrangler (`wrangler`), Vercel CLI (`vercel`).
- **AI Agent Framework:** DeepSeek Harness (`@deepseek-ai/dsh`).

---

## 🔐 GitHub Secrets Configuration

Add these in **Settings** → **Secrets and variables** → **Actions**:

| Secret Name | Status | Purpose |
| :--- | :--- | :--- |
| `RCLONE_CONFIG_B64` | **Required** | Base64-encoded `rclone.conf` with Google Drive `gdrive:` remote credentials. |
| `DEEPSEEK_API_KEY` | *Recommended* | DeepSeek API key for Harness agent reasoning and tool calls. |
| `TAILSCALE_AUTHKEY` | *Optional* | Ephemeral auth key for private Tailnet connectivity. |
| `GH_TOKEN` | *Optional* | GitHub token for pre-authenticating GitHub CLI (`gh`). |
| `CLOUDFLARE_API_TOKEN` | *Optional* | Cloudflare API token for Wrangler. |
| `CLOUDFLARE_ACCOUNT_ID` | *Optional* | Cloudflare Account ID for Wrangler. |
| `VERCEL_TOKEN` | *Optional* | Vercel token for Vercel CLI deployments. |
| `VERCEL_ORG_ID` | *Optional* | Vercel Organization ID. |
| `VERCEL_PROJECT_ID` | *Optional* | Vercel Project ID. |

---

## 🛠️ Step-by-Step Setup Guide

### 1. Configure Google Drive in `rclone`
Run rclone setup on your local computer or Termux:
```bash
rclone config
```
1. Type `n` for new remote.
2. Name: `gdrive`
3. Storage type: `drive`
4. Client ID & Secret: Leave blank (or use custom Google Cloud OAuth credentials).
5. Scope: Type `1` (Full access).
6. Complete browser authorization.
7. Confirm and save as `gdrive`.

### 2. Base64-Encode `rclone.conf`
Encode your `rclone.conf` file:
- **Linux / Termux:** `base64 -w 0 ~/.config/rclone/rclone.conf`
- **macOS:** `base64 -i ~/.config/rclone/rclone.conf`
- **Windows (PowerShell):**
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:APPDATA\rclone\rclone.conf"))
  ```
Add the output string as secret **`RCLONE_CONFIG_B64`** in your GitHub repository.

---

## 🚀 Launching Your Cloud Environment

1. Go to the **Actions** tab in this repository.
2. Select **Cloud Development Environment (DeepSeek Harness)**.
3. Click **Run workflow**:
   - `session_duration_minutes`: Default is `350` minutes (max 360 / 6 hours).
   - `force_clean_restore`: Leave unchecked (uncheck preserves Google Drive files).
4. Click **Run workflow**.
5. Open the run and view the **Job Summary** or step logs for your DeepSeek Harness access URL.
6. When creating web apps, run `preview tunnel <port>` to get an instant public preview URL!
