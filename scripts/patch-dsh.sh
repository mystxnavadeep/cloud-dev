#!/usr/bin/env bash
# ==============================================================================
# patch-dsh.sh: Adapt DeepSeek Harness for Secure Remote Cloud Tailnet Access
# Fixes HTTP 403 API errors and enables Workspace Directory Picker:
# 1. Extends loopback trust to Tailnet hostnames (cloud-dev, *.ts.net, 100.*)
# 2. Ensures PRIVILEGED_METHODS check passes trustedHosts
# 3. Ensures frontend isLoopback flag evaluates to true on Tailnet connections
# ==============================================================================

set -eo pipefail

echo "=================================================="
echo "🔧 Applying DeepSeek Harness Remote Cloud Fixes"
echo "=================================================="

python3 - << 'EOF'
import os
import glob
import subprocess

search_dirs = [
    os.path.expanduser("~/.nvm"),
    "/opt/hostedtoolcache",
    "/usr/local/lib/node_modules",
    "/usr/lib/node_modules",
    os.path.expanduser("~/.npm-global"),
    os.path.expanduser("~/.bun"),
    os.path.expanduser("~/node_modules"),
    "/home/runner"
]

try:
    npm_root = subprocess.check_output(["npm", "root", "-g"], text=True, stderr=subprocess.DEVNULL).strip()
    if npm_root and os.path.exists(npm_root) and npm_root not in search_dirs:
        search_dirs.append(npm_root)
except Exception:
    pass

patched_count = 0
visited_files = set()

t_loopback = 'if (hostname === "localhost" || hostname === "[::1]") return true;'
r_loopback = 'if (hostname === "localhost" || hostname === "[::1]" || hostname === "cloud-dev" || hostname.endsWith(".ts.net") || hostname.startsWith("100.")) return true;'

t_priv = 'if (method !== void 0 && PRIVILEGED_METHODS.has(method) && !isTrustedApiRequest(request, []))'
r_priv = 'if (method !== void 0 && PRIVILEGED_METHODS.has(method) && !isTrustedApiRequest(request, trustedHosts))'

for base in search_dirs:
    if not os.path.exists(base):
        continue
    for root, dirs, files in os.walk(base):
        if "dsh-client-connection" in root or "@deepseek-ai" in root:
            for fname in files:
                if fname.endswith(".js"):
                    fpath = os.path.join(root, fname)
                    if fpath in visited_files:
                        continue
                    visited_files.add(fpath)
                    try:
                        with open(fpath, "r", encoding="utf-8", errors="ignore") as f:
                            content = f.read()

                        modified = False

                        # 1. Patch isLoopbackHostname in dsh-client-connection
                        if t_loopback in content:
                            content = content.replace(t_loopback, r_loopback)
                            modified = True

                        # 2. Patch PRIVILEGED_METHODS check if present
                        if t_priv in content:
                            content = content.replace(t_priv, r_priv)
                            modified = True

                        if modified:
                            with open(fpath, "w", encoding="utf-8") as f:
                                f.write(content)
                            print(f"✅ Successfully patched: {fpath}")
                            patched_count += 1
                    except Exception as err:
                        print(f"⚠️ Warning patching {fpath}: {err}")

print(f"Total DeepSeek Harness files patched: {patched_count}")
EOF

echo "DeepSeek Harness remote cloud authorization fixes successfully applied."
