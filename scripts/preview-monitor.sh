#!/usr/bin/env bash
# ==============================================================================
# preview-monitor.sh: Automatic detector for private website previews over Tailscale
# Detects listening development ports (Vite, Next.js, Flask, FastAPI, etc.)
# and outputs clickable Tailscale URLs.
# ==============================================================================

set -eo pipefail

TAILSCALE_IP="${TAILSCALE_IP:-}"
if [ -z "${TAILSCALE_IP}" ]; then
    TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "127.0.0.1")
fi

TAILSCALE_HOSTNAME="${TAILSCALE_HOSTNAME:-}"
if [ -z "${TAILSCALE_HOSTNAME}" ]; then
    TAILSCALE_HOSTNAME=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//' || echo "${TAILSCALE_IP}")
fi

ACTIVE_FILE="/tmp/active_previews.txt"
touch "${ACTIVE_FILE}"

echo "=================================================="
echo "👀 Website Preview Monitor Started"
echo "=================================================="
echo "Tailscale IP: ${TAILSCALE_IP}"
echo "Hostname:     ${TAILSCALE_HOSTNAME}"
echo "Monitoring for development servers (Vite, Next.js, Flask, FastAPI, etc.)..."

# Known system or non-preview ports to ignore
IGNORED_PORTS="22|53|3080|41641|111"

declare -A DETECTED_PORTS

while true; do
    # Get list of unique listening TCP ports
    CURRENT_PORTS=$(ss -tlnH | awk '{print $4}' | awk -F: '{print $NF}' | sort -u || true)

    for PORT in ${CURRENT_PORTS}; do
        if [[ ! "${PORT}" =~ ^[0-9]+$ ]]; then
            continue
        fi

        # Skip ignored internal ports
        if echo "${PORT}" | grep -E -q "^(${IGNORED_PORTS})$"; then
            continue
        fi

        # Check if already announced
        if [ -z "${DETECTED_PORTS[${PORT}]:-}" ]; then
            DETECTED_PORTS[${PORT}]=1
            echo "${PORT}" >> "${ACTIVE_FILE}"

            echo ""
            echo "================================================================================"
            echo "🌐 NEW PRIVATE WEBSITE PREVIEW DETECTED ON PORT :${PORT}"
            echo "================================================================================"
            echo "🔗 Tailscale IP URL:       http://${TAILSCALE_IP}:${PORT}"
            echo "🔗 MagicDNS Hostname URL:  http://${TAILSCALE_HOSTNAME}:${PORT}"
            echo "🔒 Accessible exclusively to devices authenticated on your Tailnet."
            echo "================================================================================"
            echo ""

            # Update GitHub Step Summary if available
            if [ -n "${GITHUB_STEP_SUMMARY}" ]; then
                {
                    echo "### 🌐 Live Website Preview (Port ${PORT})"
                    echo "- **Private URL:** [http://${TAILSCALE_IP}:${PORT}](http://${TAILSCALE_IP}:${PORT})"
                    echo "- **MagicDNS URL:** [http://${TAILSCALE_HOSTNAME}:${PORT}](http://${TAILSCALE_HOSTNAME}:${PORT})"
                    echo "- **Detected At:** $(date -u +"%Y-%m-%d %H:%M:%SZ")"
                    echo ""
                } >> "${GITHUB_STEP_SUMMARY}"
            fi
        fi
    done

    sleep 5
done
