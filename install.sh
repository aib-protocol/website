#!/usr/bin/env bash
# AIB Node installer — no root required, installs to ~/.aib
# Usage: curl -sSfL https://www.aib.one/install.sh | bash
set -euo pipefail

VERSION="v0.8.0-testnet"
REPO="aib-protocol/aib"
INSTALL_DIR="${AIB_HOME:-$HOME/.aib}"
BIN_DIR="$INSTALL_DIR/bin"
BIN="$BIN_DIR/aib-node"
SERVICE_NAME="aib-node"

# ---------- pretty output ----------
info()  { printf '\033[1;34m[AIB]\033[0m %s\n' "$*"; }
ok()    { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()   { printf '\033[1;31m[AIB] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- detect ----------
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$OS" in
  linux) OS="linux" ;;
  darwin) OS="darwin" ;;
  *) die "Unsupported OS: $OS (linux/darwin only for now)" ;;
esac
case "$ARCH" in
  x86_64|amd64) ARCH="amd64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) die "Unsupported architecture: $ARCH" ;;
esac
ASSET="aib-node-${OS}-${ARCH}"
info "Detected: ${OS}/${ARCH} → ${ASSET}"

# root not needed — refuse if running as root unnecessarily
if [ "$(id -u)" = "0" ]; then
  warn "Running as root — AIB does not need root. Installing for root user anyway."
fi

# ---------- download ----------
DL="https://github.com/${REPO}/releases/download/${VERSION}"
mkdir -p "$BIN_DIR"
info "Downloading ${ASSET} (${VERSION})..."
if command -v curl >/dev/null 2>&1; then
  curl -sSfL "$DL/$ASSET" -o "$BIN.tmp" || die "download failed"
else
  wget -q "$DL/$ASSET" -O "$BIN.tmp" || die "download failed (need curl or wget)"
fi

# ---------- verify ----------
info "Verifying sha256..."
EXPECT="$(curl -sSfL "$DL/SHA256SUMS" | grep " ${ASSET}\$" | awk '{print $1}')"
[ -n "$EXPECT" ] || die "checksum entry missing for $ASSET"
GOT="$(sha256sum "$BIN.tmp" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$BIN.tmp" | awk '{print $1}')"
[ "$GOT" = "$EXPECT" ] || die "sha256 mismatch! expected $EXPECT got $GOT"
ok "Checksum verified"

chmod +x "$BIN.tmp"
mv "$BIN.tmp" "$BIN"
ok "Installed: $BIN ($("$BIN" --help >/dev/null 2>&1; echo v0.8.0-testnet))"

# ---------- config / data ----------
mkdir -p "$INSTALL_DIR/data"
[ -f "$INSTALL_DIR/config.toml" ] || cat > "$INSTALL_DIR/config.toml" <<'CFG'
# AIB node configuration — defaults are fine for testnet
network = "testnet"
block_time = 30
# api_port = 8080
# p2p_port = 51413
# bootstrap = ""
# nickname = ""
CFG
ok "Config: $INSTALL_DIR/config.toml"

# ---------- PATH hint ----------
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "Add to PATH:  export PATH=\"\$PATH:$BIN_DIR\"" ;;
esac

# ---------- systemd --user (Linux only) ----------
RUN_NOW=0
if [ "$OS" = "linux" ] && command -v systemctl >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/${SERVICE_NAME}.service" <<UNIT
[Unit]
Description=AIB Node (testnet)
After=network-online.target

[Service]
ExecStart=$BIN -data-dir $INSTALL_DIR -api-port 8080
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload
  systemctl --user enable --now "${SERVICE_NAME}.service" 2>/dev/null && ok "Service started (systemd --user: aib-node)" || {
    warn "systemd --user unavailable — falling back to background run"
    RUN_BG=1
  }
else
  warn "No systemd (or macOS) — running in background"
  RUN_BG=1
fi

# ---------- fallback: direct background run ----------
if [ "${RUN_BG:-0}" = "1" ]; then
  mkdir -p "$INSTALL_DIR"
  nohup "$BIN" -data-dir "$INSTALL_DIR" -api-port 8080 >> "$INSTALL_DIR/node.log" 2>&1 &
  BG_PID=$!
  disown $BG_PID 2>/dev/null || true
  ok "Node started in background (pid $BG_PID, log: $INSTALL_DIR/node.log)"
fi

# ---------- health check: wait until up, else show real error ----------
info "Waiting for node to come up..."
UP=0
for i in $(seq 1 15); do
  if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:8080/health" 2>/dev/null; then UP=1; break; fi
  sleep 1
done
if [ "$UP" = "1" ]; then
  ok "Node is UP: http://127.0.0.1:8080/health"
else
  warn "Node did NOT come up in 15s. Last log lines:"
  tail -n 15 "$INSTALL_DIR/node.log" 2>/dev/null | sed 's/^/    /'
  journalctl --user -u aib-node -n 15 --no-pager 2>/dev/null | tail -8 | sed 's/^/    /'
  die "Install incomplete — send the log above to the team"
fi

cat <<'DONE'

  ╔══════════════════════════════════════════════╗
     AIB node installed  ·  zero-root install
  ╚══════════════════════════════════════════════╝

  Binary   : ~/.aib/bin/aib-node        (static, no deps)
  Data     : ~/.aib/data/
  Config   : ~/.aib/config.toml
  Service  : systemctl --user status aib-node
  Logs     : journalctl --user -u aib-node -f
  API      : http://127.0.0.1:8080/health
  Uninstall: systemctl --user disable --now aib-node; rm -rf ~/.aib

DONE
