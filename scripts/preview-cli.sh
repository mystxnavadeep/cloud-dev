#!/usr/bin/env bash
# ==============================================================================
# preview-cli.sh: Developer CLI for managing website previews
# Usage:
#   preview list                    List all active preview servers & tunnels
#   preview tunnel <port>           Create temporary Cloudflare Quick Tunnel on demand
#   preview serve <dir> [port]      Quickly serve directory locally
#   preview info                    Show connection and preview identity
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "127.0.0.1")
TAILSCALE_HOSTNAME=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//' || echo "${TAILSCALE_IP}")

case "${1:-list}" in
    list)
        echo "=================================================="
        echo "🌐 Active Website Previews"
        echo "=================================================="
        echo "Local / Tailscale IP: ${TAILSCALE_IP}"
        echo ""

        # 1. Listening ports
        IGNORED_PORTS="22|53|3080|41641|111"
        LISTENING=$(ss -tlnH | awk '{print $4}' | awk -F: '{print $NF}' | sort -u || true)

        echo "Listening Development Servers:"
        FOUND=0
        for PORT in ${LISTENING}; do
            if [[ "${PORT}" =~ ^[0-9]+$ ]] && ! echo "${PORT}" | grep -E -q "^(${IGNORED_PORTS})$"; then
                echo "  🟢 Port ${PORT}:"
                echo "     👉 http://${TAILSCALE_IP}:${PORT}"
                echo "     👉 http://localhost:${PORT}"
                FOUND=$((FOUND + 1))
            fi
        done
        if [ "${FOUND}" -eq 0 ]; then
            echo "  (No dev servers currently running)"
        fi

        echo ""
        echo "Active Cloudflare Preview Tunnels:"
        if [ -d "/tmp/tunnels" ] && [ "$(ls -A /tmp/tunnels/*.pid 2>/dev/null)" ]; then
            for PID_F in /tmp/tunnels/*.pid; do
                P_PORT=$(basename "${PID_F}" .pid | sed 's/tunnel_//')
                P_PID=$(cat "${PID_F}" 2>/dev/null || true)
                if [ -n "${P_PID}" ] && kill -0 "${P_PID}" 2>/dev/null; then
                    P_URL=$(grep -o -E "https://[-a-zA-Z0-9.]+\.trycloudflare\.com" "/tmp/tunnels/tunnel_${P_PORT}.log" 2>/dev/null | head -n 1 || echo "initializing...")
                    echo "  🌐 Port ${P_PORT}: ${P_URL} (PID: ${P_PID})"
                fi
            done
        else
            echo "  (No Cloudflare Quick Tunnels active. To create one: 'preview tunnel <port>')"
        fi
        echo "=================================================="
        ;;

    tunnel)
        PORT="${2:-}"
        if [ -z "${PORT}" ]; then
            echo "Usage: preview tunnel <port>" >&2
            exit 1
        fi
        "${SCRIPT_DIR}/preview-tunnel.sh" "${PORT}"
        ;;

    serve)
        DIR="${2:-.}"
        PORT="${3:-8080}"
        if [ ! -d "${DIR}" ]; then
            echo "❌ Error: Directory '${DIR}' does not exist." >&2
            exit 1
        fi
        echo "🚀 Serving '${DIR}' on port ${PORT}..."
        echo "🔗 Local access: http://localhost:${PORT}"
        if [ -n "${TAILSCALE_IP}" ] && [ "${TAILSCALE_IP}" != "127.0.0.1" ]; then
            echo "🔗 Private Tailscale: http://${TAILSCALE_IP}:${PORT}"
        fi
        python3 -m http.server "${PORT}" --bind 0.0.0.0 --directory "${DIR}"
        ;;

    info)
        echo "Workspace:          ${WORKSPACE_DIR:-/home/runner/workspace}"
        echo "DeepSeek Harness:   http://localhost:3080"
        if [ -n "${TAILSCALE_IP}" ] && [ "${TAILSCALE_IP}" != "127.0.0.1" ]; then
            echo "Tailscale IP:       ${TAILSCALE_IP}"
        fi
        ;;

    *)
        echo "Usage: preview [list | tunnel <port> | serve <dir> [port] | info]"
        exit 1
        ;;
esac
