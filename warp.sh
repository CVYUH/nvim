#!/usr/bin/env bash
# Cloudflare WARP on this box, Linux (apt) or macOS (Homebrew): ./warp.sh install | run | stop | uninstall | status
# install and uninstall use sudo (run them in your own terminal); run installs first when WARP is missing.
set -euo pipefail

OS=$(uname -s)

KEYRING=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
SOURCE=/etc/apt/sources.list.d/cloudflare-client.list
REPO=https://pkg.cloudflareclient.com
CASK=cloudflare-warp

warp() { warp-cli --accept-tos "$@"; }
installed() { command -v warp-cli >/dev/null; }
connected() { warp status | grep -q Connected; }

# Cloudflare's repo may not carry the newest Ubuntu codename yet; noble (24.04) when it doesn't.
codename() {
  local name
  name=$(. /etc/os-release && echo "${VERSION_CODENAME}")
  curl -fsI "${REPO}/dists/${name}/Release" >/dev/null && echo "$name" || echo noble
}

add_repo() {
  [ "$OS" = Darwin ] && return
  curl -fsSL "${REPO}/pubkey.gpg" | sudo gpg --yes --dearmor -o "$KEYRING"
  echo "deb [signed-by=${KEYRING}] ${REPO}/ $(codename) main" | sudo tee "$SOURCE" >/dev/null
  sudo apt-get update
}

remove_repo() {
  [ "$OS" = Darwin ] && return
  sudo rm -f "$SOURCE" "$KEYRING"
  sudo apt-get update
}

add_package() {
  case "$OS" in
    Darwin) brew install --cask "$CASK" ;;
    *) sudo apt-get install -y cloudflare-warp ;;
  esac
}

remove_package() {
  case "$OS" in
    Darwin) brew uninstall --cask --zap "$CASK" ;;
    *) sudo apt-get purge -y cloudflare-warp && sudo apt-get autoremove -y ;;
  esac
}

# On macOS the cask's launchd daemon answers warp-cli a few seconds after the install.
daemon_up() {
  for _ in $(seq 30); do warp status >/dev/null 2>&1 && return; sleep 1; done
  echo "the WARP daemon is not answering" >&2
  exit 1
}

register() { daemon_up; warp registration show >/dev/null 2>&1 || warp registration new; }
unregister() { warp registration delete || true; }

connect() {
  warp mode warp
  warp connect
  for _ in $(seq 20); do connected && return; sleep 1; done
}

disconnect() { warp disconnect || true; }

install() {
  installed && { echo "warp-cli already installed: $(warp-cli --version)"; return; }
  add_repo
  add_package
  register
}

run() {
  installed || install
  register
  connect
  status
}

stop() {
  installed || { echo "WARP is not installed"; return; }
  disconnect
  warp status
}

uninstall() {
  if installed; then
    disconnect
    unregister
    remove_package
  fi
  remove_repo
  installed && { echo "warp-cli still present" >&2; exit 1; }
  case "$OS" in
    Darwin) echo "WARP removed: cask, app, daemon and registration" ;;
    *) echo "WARP removed: package, registration, apt source and keyring" ;;
  esac
}

status() {
  installed || { echo "WARP is not installed"; return; }
  warp status
  curl -s https://www.cloudflare.com/cdn-cgi/trace | grep '^warp='
}

cmd=${1:-status}
case "$cmd" in
  install | run | stop | uninstall | status) "$cmd" ;;
  *) echo "usage: $0 install | run | stop | uninstall | status" >&2; exit 2 ;;
esac
