# ☁️ Cloud Dev: Persistent DeepSeek Harness Environment

[![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-Cloud_Runner-2088FF?logo=github-actions&logoColor=white)](https://github.com/features/actions)
[![DeepSeek Harness](https://img.shields.io/badge/DeepSeek_Harness-v0.2-brightgreen)](https://github.com/deepseek-ai/dsh)
[![Persistence](https://img.shields.io/badge/Storage-Google_Drive_via_rclone-34A853?logo=googledrive&logoColor=white)](https://rclone.org/drive/)
[![Tunnel](https://img.shields.io/badge/Tunnel-Cloudflare-F38020?logo=cloudflare&logoColor=white)](https://www.cloudflare.com/)

A persistent cloud development environment running **DeepSeek Harness (`dsh`)** inside GitHub Actions. Exposes a browser-accessible Web UI via a secure tunnel, automatically restores your workspace from **Google Drive** at startup, synchronizes changes every 5 minutes, and performs a final backup before the workflow terminates.

---

## 📑 Architecture Overview

```
 ┌─────────────────────────────────────────────────────────────┐
 │                    GitHub Actions Runner                    │
 │                                                             │
 │   ┌─────────────────┐             ┌─────────────────────┐   │
 │   │  Google Drive   │ ──(Restore)─>  /home/runner/      │   │
 │   │ (rclone remote) │ <──(5m Sync)──  workspace         │   │
 │   └─────────────────┘ <──(Final)─── └──────────┬────────┘   │
 │                                                │            │
 │                                         (DSH_HOME & CWD)    │
 │                                                ▼            │
 │   ┌──────────────────────┐        ┌─────────────────────┐   │
 │   │  Cloudflare Tunnel   │ <────> │   DeepSeek Harness  │   │
 │   │ (trycloudflare / cfd)│        │  Web UI (Port 3080) │   │
 │   └──────────┬───────────┘        └─────────────────────┘   │
 └──────────────┼──────────────────────────────────────────────┘
                │ Secure HTTPS
                ▼
      ┌──────────────────┐
      │   Your Browser   │
      └──────────────────┘
```

---

## ✨ Features

- **🚀 DeepSeek Harness Web UI:** Full agentic coding assistant environment powered by `@deepseek-ai/dsh`.
- **🌐 Zero-Config Secure Tunnel:** Out-of-the-box browser URL provided by Cloudflare quick tunnels (with custom tunnel support).
- **💾 Continuous Persistence:** Auto-syncs your projects and agent configuration to Google Drive every 5 minutes.
- **🛡️ Clean Workspace Handling:** Automatically detects first-time setup or restores existing workspace files without manual intervention.
- **🧹 Cache Exclusions:** Ignores build caches (`node_modules/.cache`, `.next/cache`, `__pycache__`), temporary files, and sensitive credentials.
- **⏱️ Up to 6-Hour Sessions:** Configurable duration up to the standard GitHub Actions 6-hour runner limit with graceful termination traps.
- **🔒 Zero Secret Leaks:** Google Drive tokens and API keys are kept encrypted in GitHub Secrets and never printed in logs.

---

## 🔑 Required Secrets Setup

Configure these secrets in your repository: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

| Secret Name | Requirement | Description |
| :--- | :--- | :--- |
| `RCLONE_CONFIG_B64` | **Required** | Base64-encoded `rclone.conf` containing your Google Drive credentials. |
| `DEEPSEEK_API_KEY` | *Optional* | Your DeepSeek API key for agent chat completions and reasoning. |
| `CLOUDFLARE_TUNNEL_TOKEN` | *Optional* | Cloudflare Named Tunnel token (if you prefer a persistent custom domain instead of a quick tunnel). |

---

## 🛠️ Step-by-Step Google Drive & rclone Setup

To connect Google Drive securely, generate an `rclone.conf` on your local device (computer, laptop, or Termux) and encode it as a GitHub Secret.

### Step 1: Install rclone locally

- **Linux / macOS / Termux:**
  ```bash
  curl https://rclone.org/install.sh | sudo bash
  # On Termux: pkg install rclone
  ```
- **Windows:**
  Download from [rclone.org/downloads](https://rclone.org/downloads/) or install via `winget install Rclone.Rclone` or `choco install rclone`.

### Step 2: Configure Google Drive Remote

Run the rclone interactive wizard:

```bash
rclone config
```

1. Type `n` for **New remote**.
2. Name the remote: `gdrive`
3. Storage type: Select `drive` (type `drive` or its corresponding number).
4. **Google Application Client ID / Secret:**
   - Press `Enter` to leave blank for default credentials, OR provide your own [Google Cloud Console OAuth Client ID](https://rclone.org/drive/#making-your-own-client-id) for optimal speed and reliability.
5. Scope: Type `1` for full access (`drive`).
6. Root folder ID / Service Account: Press `Enter` to leave blank.
7. Advanced configuration: Type `n` (No).
8. Use web browser to authenticate:
   - If on a local computer with a browser: Type `y`. A browser window will open; log into your Google account and grant permissions.
   - If on a headless server or Termux: Type `n`, run `rclone authorize "drive"` on a desktop machine with a browser, and paste the authorization token back.
9. Configure as a team drive: Type `n` (No).
10. Confirm and save: Type `y`, then `q` to quit.

### Step 3: Verify Your Local rclone Configuration

Test that the remote is working:

```bash
rclone lsd gdrive:
```

### Step 4: Encode `rclone.conf` into Base64

Locate your `rclone.conf` file:
- **Linux / Termux / macOS:** `~/.config/rclone/rclone.conf`
- **Windows:** `%APPDATA%\rclone\rclone.conf`

Encode the file to base64:

- **Linux / macOS / Termux:**
  ```bash
  base64 -w 0 ~/.config/rclone/rclone.conf
  # On macOS: base64 -i ~/.config/rclone/rclone.conf
  ```
- **Windows (PowerShell):**
  ```powershell
  [Convert]::ToBase64String([IO.File]::ReadAllBytes("$env:APPDATA\rclone\rclone.conf"))
  ```

### Step 5: Add Secret to GitHub

1. Copy the entire base64 string printed by the command above.
2. Go to your repository on GitHub: `https://github.com/mystxnavadeep/cloud-dev`
3. Click **Settings** → **Secrets and variables** → **Actions**.
4. Click **New repository secret**.
5. Name: `RCLONE_CONFIG_B64`
6. Value: Paste the base64 string.
7. Click **Add secret**.

*(Optional)* Add `DEEPSEEK_API_KEY` with your DeepSeek API key.

---

## 🚀 Running Your Cloud Environment

1. Navigate to the **Actions** tab in this repository.
2. Under **Workflows**, click **Cloud Development Environment (DeepSeek Harness)**.
3. Click the **Run workflow** dropdown on the right:
   - **Session duration in minutes:** `350` (up to 360 minutes / 6 hours).
   - **Initialize clean workspace:** Leave unchecked (unless you want to start fresh).
4. Click the green **Run workflow** button.

---

## 🌐 Accessing DeepSeek Harness in Your Browser

1. Click on the running workflow run.
2. Click on the **cloud-dev** job to view the live logs.
3. Once the runner starts, locate the **Launch DeepSeek Harness & Expose Web Interface** step or click the **Summary** tab in the left sidebar.
4. You will see a prominent message with the direct browser URL:
   ```
   ================================================================================
   🎉 DEEPSEEK HARNESS WEB UI IS ONLINE!
   ================================================================================

   🔗 Access URL: https://random-name-xxxx.trycloudflare.com/?token=...
   ```
5. Click the link to open the DeepSeek Harness interface directly in your browser!

---

## 💾 Workspace Persistence Details

- **Local Path on Runner:** `/home/runner/workspace`
- **Google Drive Storage Path:** `gdrive:cloud-dev/workspace`
- **Agent Config & State:** Saved in `/home/runner/workspace/.dsh` and automatically preserved between sessions.
- **Sync Cadence:**
  - **Restore:** Automatic at startup.
  - **Periodic:** Every 5 minutes in background.
  - **Final Backup:** Executes on session expiry, manual cancellation, or workflow completion (`always()` hook).
- **Excluded Files:** Build caches (`node_modules/.cache`, `.next/cache`, `__pycache__`), temporary files (`*.tmp`), and secret keys (`.git-credentials`, `*.pem`, `*.key`) are excluded to optimize speed and security.
