#!/usr/bin/env bash
# Concept: Mukesh Kesharwani
# Contact: mukesh.kesharwani@adobe.com
#
# Example docker run for headless-chrome with recommended DNS and resources.
# Override DNS via environment: DNS_PRIMARY=10.0.0.1 DNS_SECONDARY=8.8.8.8 ./deploy/docker-run.example.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=defaults.env
source "${SCRIPT_DIR}/defaults.env"

DNS_PRIMARY="${DNS_PRIMARY:-192.168.1.200}"
IMAGE="${IMAGE:-keekar/headless-chrome:latest}"
NAME="${NAME:-headless-chrome}"

docker run -d --restart unless-stopped \
  --name "${NAME}" \
  -p 6080:6080 \
  --shm-size=2g \
  --dns "${DNS_PRIMARY}" \
  --dns-search . \
  --dns-opt ndots:2 \
  --dns-opt attempts:2 \
  --dns-opt timeout:2 \
  -e CHROME_MODE=desktop \
  -e NOVNC_PORT=6080 \
  -e NOVNC_LISTEN=0.0.0.0 \
  -e START_URL=about:blank \
  "${IMAGE}"

echo "Started ${NAME}. Open: http://<host>:6080/"
echo "DNS: ${DNS_PRIMARY} (AdGuard/LAN only; no search-domain fallback)"
