#!/usr/bin/env bash
# Cloudflare WARP on this box: ./warp.sh install | on | off | status
# install needs sudo (run it in your own terminal); on/off/status don't.
set -euo pipefail

install() {
  if command -v warp-cli >/dev/null; then echo "warp-cli already installed: $(warp-cli --version)"; return; fi
  codename=$(. /etc/os-release && echo "${VERSION_CODENAME}")
  # Cloudflare's repo may not carry the newest Ubuntu codename yet; fall back to noble (24.04).
  if ! curl -fsI "https://pkg.cloudflareclient.com/dists/${codename}/Release" >/dev/null; then
    echo "no WARP repo for ${codename}, using noble"; codename=noble
  fi
  curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg |
    sudo gpg --yes --dearmor -o /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ ${codename} main" |
    sudo tee /etc/apt/sources.list.d/cloudflare-client.list >/dev/null
  sudo apt-get update && sudo apt-get install -y cloudflare-warp
  warp-cli --accept-tos registration new
}

case "${1:-status}" in
  install) install ;;
  on)
    command -v warp-cli >/dev/null || { echo "warp-cli missing: ./warp.sh install first" >&2; exit 1; }
    warp-cli --accept-tos registration show >/dev/null 2>&1 || warp-cli --accept-tos registration new
    warp-cli --accept-tos mode warp
    warp-cli --accept-tos connect
    for _ in $(seq 20); do warp-cli --accept-tos status | grep -q Connected && break; sleep 1; done
    warp-cli --accept-tos status
    curl -s https://www.cloudflare.com/cdn-cgi/trace | grep '^warp='
    ;;
  off)
    warp-cli --accept-tos disconnect
    warp-cli --accept-tos status
    ;;
  status)
    warp-cli --accept-tos status
    curl -s https://www.cloudflare.com/cdn-cgi/trace | grep '^warp='
    ;;
  *) echo "usage: $0 install | on | off | status" >&2; exit 2 ;;
esac
