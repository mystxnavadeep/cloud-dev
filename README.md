# ☁️ Cloud Dev: Persistent DeepSeek Harness Environment (Tailscale-Only)

[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-Cloud_Runner-2088FF?logo=github-actions&logoColor=white)](https://github.com/features/actions)
[![DeepSeek Harness](https://img.shields.io/badge/DeepSeek_Harness-v0.2-brightgreen)](https://github.com/deepseek-ai/dsh)
[![Network](https://img.shields.io/badge/Access-Tailscale_Private_WireGuard-111827?logo=tailscale&logoColor=white)](https://tailscale.com/)
[![Persistence](https://img.shields.io/badge/Storage-Google_Drive_via_rclone-34A853?logo=googledrive&logoColor=white)](https://rclone.org/drive/)

A complete, persistent cloud development environment running **DeepSeek Harness (`dsh`)** inside GitHub Actions runners. Remote access is strictly restricted to your private **Tailscale** network (zero public tunnels, zero open internet ports). Projects and configurations are automatically synchronized to **Google Drive** every 5 minutes and restored seamlessly between sessions.

---

## 📑 Architecture Overview

```
 ┌────────────────────────────────────────────────────────────────────────┐
 │                    GitHub Actions Runner (Ubuntu)                      │
 │                                                                        │
 │   ┌──────────────────────┐              ┌──────────────────────────┐   │
 │   │     Google Drive     │ ──(Restore)─>│   /home/runner/          │   │
 │   │   (rclone remote)    │ <──(5m Sync)─│    workspace             │   │
 │   └──────────────────────┘ <──(Final)── └────────────┬─────────────┘   │
 │                                                      │                 │
 │                                               (DSH_HOME & CWD)         │
 │                                                      ▼                 │
 │   ┌──────────────────────┐              ┌──────────────────────────┐   │
 │   │  Tailscale Interface │ <──────────> │   DeepSeek Harness       │   │
 │   │   (tailscale0 / WireGuard)          │   Web UI (:3080)         │   │
 │   │                      │              ├──────────────────────────┤   │
 │   │  100.x.y.z           │ <──────────> │   Website Previews       │   │
 │   │  cloud-dev.tailnet   │              │   (:5173, :3000, :8000)  │   │
 │   └──────────┬───────────┘              └──────────────────────────┘   │
 └──────────────┼─────────────────────────────────────────────────────────┘
                │ Encrypted WireGuard Peer-to-Peer
                ▼
      ┌──────────────────┐
      │   Your Browser   │ (Authenticated on your Tailscale tailnet)
      └──────────────────┘
```

---

## 🧰 Preinstalled Tool Inventory

### JavaScript & Web Development
- **Runtimes & Package Managers:** Node.js LTS (v20), npm, pnpm, yarn, Bun.
- **Frameworks & Build Tools:** React, Vite, Next.js, TypeScript (`ts-node`), Tailwind CSS, shadcn/ui, Bootstrap, Sass, PostCSS, Webpack, Parcel.
- **Animation, Graphics & Icons:** Framer Motion, Three.js, Lucide icons.
- **Code Quality:** ESLint, Prettier.

### Python Environment
- **Python 3 & Pip:** Python 3.11 with pip.
- **Tooling:** Astral `uv` (ultra-fast package installer), `pipx`, `virtualenv`.
- **Frameworks & Notebooks:** Flask, FastAPI, Uvicorn, Django, Jupyter Notebook, JupyterLab.

### System & Testing Tools
- **Utilities:** Git, GitHub CLI (`gh`), curl, wget, jq, zip/unzip, build-essential (`gcc`, `g++`, `make`), tree.
- **Browser Automation:** Chromium, Playwright (with preinstalled chromium browser binaries).

### Cloud Platform CLIs
- **GitHub CLI:** `gh`
- **Cloudflare:** `wrangler`
- **Vercel:** `vercel`

---

## 🔐 GitHub Secrets Configuration

Add these secrets in your repository: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

| Secret Name | Required | Description |
| :--- | :--- | :--- |
| `TAILSCALE_AUTHKEY` | **Required** | Tailscale pre-authenticated ephemeral key (e.g. `tskey-auth-...`). |
| `RCLONE_CONFIG_B64` | **Required** | Base64-encoded `rclone.conf` with your Google Drive OAuth token. |
| `DEEPSEEK_API_KEY` | *Recommended* | DeepSeek API key for agent chat completions and code reasoning. |
| `GH_TOKEN` | *Optional* | GitHub Personal Access Token for GitHub CLI (`gh`) operations. |
| `CLOUDFLARE_API_TOKEN` | *Optional* | Cloudflare API token for Cloudflare Wrangler CLI. |
| `CLOUDFLARE_ACCOUNT_ID` | *Optional* | Cloudflare Account ID for Wrangler projects. |
| `VERCEL_TOKEN` | *Optional* | Vercel Personal Access Token for Vercel CLI deployments. |
| `VERCEL_ORG_ID` | *Optional* | Vercel Organization ID (team or user scope). |
| `VERCEL_PROJECT_ID` | *Optional* | Vercel Project ID for linked project deployments. |

---

## 🛡️ Tailscale Setup & Private Network Access

Tailscale is the **exclusive** remote access method. No public reverse tunnels (Cloudflare Tunnels, ngrok) are used, guaranteeing your cloud runner cannot be accessed by anyone outside your Tailnet.

### Step 1: Generate a Tailscale Auth Key
1. Go to the [Tailscale Admin Console: Settings → Keys](https://login.tailscale.com/admin/settings/keys).
2. Click **Generate auth key**.
3. Enable:
   - **Reusable:** Optional (Enable if you plan to launch multiple runs).
   - **Ephemeral:** **YES** (Ensures the runner is automatically pruned from your Tailnet when the workflow finishes).
   - **Tags:** Optional (e.g., `tag:ci` if using ACL tags).
4. Copy the generated key (starts with `tskey-auth-...`).
5. Add it to your repository secrets as **`TAILSCALE_AUTHKEY`**.

### Step 2: Tailscale ACLs (Access Control Lists)
If your tailnet uses customized ACLs, ensure your devices are allowed to reach the runner:
```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["autogroup:member"],
      "dst": ["tag:ci:*", "cloud-dev:*"]
    }
  ]
}
```
*(Default personal Tailscale accounts with default ACLs allow full peer-to-peer communication automatically without additional rules).*

---

## 💾 Google Drive Workspace Persistence Setup

### Step 1: Install `rclone` locally
- **Linux / macOS:** `curl https://rclone.org/install.sh | sudo bash`
- **Termux:** `pkg install rclone`
- **Windows:** Download from [rclone.org/downloads](https://rclone.org/downloads) or `winget install Rclone.Rclone`

### Step 2: Configure Google Drive Remote
```bash
rclone config
```
1. Type `n` for **New remote**.
2. Name: `gdrive`
3. Storage type: `drive`
4. Client ID & Secret: Leave blank (or enter custom Google Cloud OAuth credentials).
5. Scope: Type `1` (Full access: `drive`).
6. Root Folder ID / Service Account: Leave blank.
7. Advanced configuration: Type `n`.
8. Web Browser Authentication:
   - On desktop: Type `y` and log in via your browser.
   - On headless/Termux: Type `n`, run `rclone authorize "drive"` on a desktop machine, and paste the authorization JSON.
9. Configure as Team Drive: `n`.
10. Confirm and save: `y`, then `q`.

### Step 3: Base64-Encode `rclone.conf`
- **Linux / Termux:**
  ```bash
  base64 -w 0 ~/.config/rclone/rclone.conf
  ```
- **macOS:**
  ```bash
  base64 -i ~/.config/rclone/rclone.conf
  ```
- **Windows (PowerShell):**
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:APPDATA\rclone\rclone.conf"))
  ```
Add the output string to repository secrets as **`RCLONE_CONFIG_B64`**.

---

## ☁️ Cloud Platform CLI Setup

When provided, these secrets automatically authenticate the respective CLIs inside your cloud workspace:

### 1. GitHub CLI (`GH_TOKEN`)
1. Go to [GitHub Settings → Developer Settings → Personal Access Tokens](https://github.com/settings/tokens).
2. Generate a token with `repo`, `workflow`, and `read:org` scopes.
3. Save as secret `GH_TOKEN`.

### 2. Cloudflare Wrangler (`CLOUDFLARE_API_TOKEN` & `CLOUDFLARE_ACCOUNT_ID`)
1. In Cloudflare Dashboard, go to **My Profile** → **API Tokens** → **Create Token** (using the "Edit Cloudflare Workers" template).
2. Account ID can be found in your Workers & Pages dashboard overview.
3. Save as secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`.

### 3. Vercel CLI (`VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID`)
1. In Vercel, go to **Account Settings** → **Tokens** → **Create**.
2. (Optional) In any linked project's `.vercel/project.json`, find `orgId` and `projectId`.
3. Save as secrets `VERCEL_TOKEN`, `VERCEL_ORG_ID`, and `VERCEL_PROJECT_ID`.

---

## 🚀 Running Your Cloud Environment

1. Navigate to the **Actions** tab in this repository.
2. Select **Cloud Development Environment (DeepSeek Harness)**.
3. Click **Run workflow**:
   - **Session duration in minutes:** `350` (up to 360 minutes / 6 hours).
   - **Initialize clean workspace:** Leave unchecked (unless you want to discard Google Drive backup).
4. Click **Run workflow**.

---

## 🤖 Accessing DeepSeek Harness in Your Browser

1. In the running workflow run, open the **Run DeepSeek Harness Cloud Environment** job.
2. Once the runner connects to Tailscale, the logs and the **Job Summary** display your private access URLs:
   ```text
   ================================================================================
   🔒 DEEPSEEK HARNESS WEB UI IS ONLINE (TAILSCALE PRIVATE ACCESS ONLY)
   ================================================================================

   🔗 Direct Tailscale IP URL:    http://100.x.y.z:3080/?token=abc123xyz...
   🔗 MagicDNS Hostname URL:     http://cloud-dev.tailxxxx.ts.net:3080/?token=abc123xyz...
   ```
3. Open either URL in your browser on any device connected to your Tailscale network.

---

## 🌐 Private Website Previews

You can launch and preview any website or API without making it public or creating external tunnels.

### How to Run Dev Servers
Always bind your development server to `0.0.0.0` so it accepts connections routed across the `tailscale0` network interface:

- **React + Vite:**
  ```bash
  npm run dev -- --host 0.0.0.0
  # Preview: http://<TAILSCALE_IP>:5173
  ```
- **Next.js:**
  ```bash
  npx next dev -H 0.0.0.0 -p 3000
  # Preview: http://<TAILSCALE_IP>:3000
  ```
- **FastAPI:**
  ```bash
  uvicorn main:app --host 0.0.0.0 --port 8000 --reload
  # Preview: http://<TAILSCALE_IP>:8000
  ```
- **Flask:**
  ```bash
  flask run --host=0.0.0.0 --port=5000
  # Preview: http://<TAILSCALE_IP>:5000
  ```
- **Static HTML / Directory:**
  ```bash
  preview serve ./dist 8080
  # Preview: http://<TAILSCALE_IP>:8080
  ```

### Automatic Port Detection
The built-in `preview-monitor` daemon automatically detects when a development server starts listening on any port and outputs the direct Tailscale preview link in the workflow logs and Job Summary!

You can also list active preview servers anytime in your terminal:
```bash
preview list
```

---

## 💾 Workspace Persistence & Backup Mechanism

- **Local Runner Path:** `/home/runner/workspace`
- **Google Drive Storage Path:** `gdrive:cloud-dev/workspace`
- **Auto-Sync:** Every 5 minutes in background via `rclone sync`.
- **Termination Backup:** Triggers on normal completion, session timeout, or manual cancellation (`if: always()`).
- **Excluded Files:** `node_modules/`, `.next/cache/`, `__pycache__/`, `.venv/`, `.git-credentials`, private keys (`*.pem`, `*.key`), and temporary files are excluded to maintain high sync speed and prevent credential leakage.

---

## 🔧 Troubleshooting

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| **"Could not obtain a valid Tailscale IPv4"** | `TAILSCALE_AUTHKEY` is missing or expired. | Generate a fresh ephemeral auth key from Tailscale Admin Console and update the GitHub secret. |
| **"Cannot reach http://100.x.y.z:3080"** | Your client device is not connected to Tailscale. | Open the Tailscale app on your phone or computer and ensure you are logged into the same Tailnet. |
| **"Website preview refuses connection"** | Server was started on `127.0.0.1` instead of `0.0.0.0`. | Restart server with `--host 0.0.0.0` or `--bind 0.0.0.0`. |
| **"No remote found in decoded rclone configuration"** | `RCLONE_CONFIG_B64` was not properly base64-encoded. | Re-run `base64 -w 0 ~/.config/rclone/rclone.conf` and update the secret. |
| **"Session terminates after 6 hours"** | GitHub Actions runner hard limit. | 6 hours (360 minutes) is GitHub's runner limit. Your files are automatically backed up to Google Drive and restored on your next run. |
