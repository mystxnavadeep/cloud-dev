#!/usr/bin/env bash
# ==============================================================================
# preview-cli.sh: Developer CLI for managing private website previews
# Usage:
#   preview list                List all active preview servers
#   preview serve <dir> [port]  Quickly serve a directory over Tailscale
#   preview info                Show Tailscale connection identity
# ==============================================================================

set -eo pipefail

TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || echo "127.0.0.1")
TAILSCALE_HOSTNAME=$(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName // empty' | sed 's/\.$//' || echo "${TAILSCALE_IP}")

case "${1:-list}" in
    list)
        echo "=================================================="
        echo "🌐 Active Private Website Previews (Tailscale)"
        echo "=================================================="
        echo "Runner Tailscale IP: ${TAILSCALE_IP}"
        echo "MagicDNS Hostname:   ${TAILSCALE_HOSTNAME}"
        echo ""
        
        IGNORED_PORTS="22|53|3080|41641|111"
        LISTENING=$(ss -tlnH | awk '{print $4}' | awk -F: '{print $NF}' | sort -u || true)
        
        FOUND=0
        for PORT in ${LISTENING}; do
            if [[ "${PORT}" =~ ^[0-9]+$ ]] && ! echo "${PORT}" | grep -E -q "^(${IGNORED_PORTS})$"; then
                echo "  🟢 Port ${PORT}:"
                echo "     👉 http://${TAILSCALE_IP}:${PORT}"
                echo "     👉 http://${TAILSCALE_HOSTNAME}:${PORT}"
                FOUND=$((FOUND + 1))
            fi
        done
        
        if [ "${FOUND}" -eq 0 ]; then
            echo "ℹ️ No custom website preview servers currently running."
            echo "To start one, run your dev server with '--host 0.0.0.0', e.g.:"
            echo "   npm run dev -- --host 0.0.0.0"
            echo "   python3 -m http.server 8080 --bind 0.0.0.0"
        fi
        echo "=================================================="
        ;;

    serve)
        DIR="${2:-.}"
        PORT="${3:-8080}"
        if [ ! -d "${DIR}" ]; then
            echo "❌ Error: Directory '${DIR}' does not exist." >&2
            exit 1
        fi
        echo "🚀 Serving '${DIR}' on port ${PORT} over Tailscale..."
        echo "🔗 Access at: http://${TAILSCALE_IP}:${PORT}"
        python3 -m http.server "${PORT}" --bind 0.0.0.0 --directory "${DIR}"
        ;;

    info)
        echo "Tailscale IP:       ${TAILSCALE_IP}"
        echo "MagicDNS Hostname:  ${TAILSCALE_HOSTNAME}"
        echo "DeepSeek Harness:   http://${TAILSCALE_IP}:3080"
        ;;

    *)
        echo "Usage: preview [list | serve <dir> [port] | info]"
        exit 1
        ;;
esac
