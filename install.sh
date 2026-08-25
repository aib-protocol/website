#!/usr/bin/env bash
# AIB Node installer — no root required, installs to ~/.aib
# Usage: curl -sSfL https://aib.one/install.sh | bash
set -euo pipefail

VERSION="v0.11.4-testnet"
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
ok "Installed: $BIN ($("$BIN" --help >/dev/null 2>&1; echo v0.11.4-testnet))"

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

# ---------- pick a free P2P port (51413 default; bump if taken) ----------
P2P_PORT=51413
while ss -tlnH "( sport = :$P2P_PORT )" 2>/dev/null | grep -q .; do
  P2P_PORT=$((P2P_PORT+1))
done
[ "$P2P_PORT" != "51413" ] && info "Port 51413 busy — using P2P port $P2P_PORT"
# ---------- external-disk detection (protect the system disk) ----------
# Blockchain + logs grow unbounded; prefer a non-root mount when available.
DATA_DIR="$INSTALL_DIR"   # default: system disk
EXT_CAND=$(awk '$3 ~ /^(ext[234]|xfs|btrfs|f2fs|exfat|vfat|ntfs|apfs)$/ && $2!="/" && $2!~/^\/boot/ && $2!~/^\/snap/ && $2!~/^\/proc/ && $2!~/^\/sys/ && $2!~/^\/dev/ && $2!~/^\/run/ && $2!~/^\/var\/lib\/docker/ && $2!~/^\/etc/ {print $2}' /proc/mounts | sort -u | while read -r m; do
  free_kb=$(df -k "$m" 2>/dev/null | awk 'NR==2{print $4}')
  dev=$(df "$m" 2>/dev/null | awk 'NR==2{print $1}')
  root_dev=$(df / 2>/dev/null | awk 'NR==2{print $1}')
  [ -n "$free_kb" ] && [ "$free_kb" -ge 2097152 ] && [ "$dev" != "$root_dev" ] && echo "$free_kb $m"
done | sort -rn | head -1 | awk '{print $2}')

if [ -n "$EXT_CAND" ]; then
  EXT_DATA="$EXT_CAND/aib-node"
  if [ -t 0 ]; then
    echo
    warn "External disk detected: $EXT_CAND ($(df -h "$EXT_CAND" | awk 'NR==2{print $4}') free)"
    printf "  Store blockchain data there (protects system disk)? [Y/n] "
    read -r ans || ans=y
    case "$ans" in n|N*) info "Keeping data on system disk ($INSTALL_DIR)" ;;
      *) DATA_DIR="$EXT_DATA"; ok "Data will be stored on: $DATA_DIR" ;;
    esac
  else
    # Non-interactive (curl|bash): auto-pick the external disk.
    DATA_DIR="$EXT_DATA"
    ok "External disk detected — data goes to $DATA_DIR (protects system disk)"
  fi
fi
[ -n "${AIB_DATA_DIR:-}" ] && DATA_DIR="$AIB_DATA_DIR"   # explicit override wins

NODE_ARGS="-data-dir $DATA_DIR -api-port 8080 -p2p-port $P2P_PORT"

# ---------- systemd --user (Linux only) ----------
RUN_NOW=0
if [ "$OS" = "linux" ] && command -v systemctl >/dev/null 2>&1; then
  mkdir -p "$HOME/.config/systemd/user"
  cat > "$HOME/.config/systemd/user/${SERVICE_NAME}.service" <<UNIT
[Unit]
Description=AIB Node (testnet)
After=network-online.target

[Service]
ExecStart=$BIN $NODE_ARGS
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable --now "${SERVICE_NAME}.service" 2>/dev/null && ok "Service started (systemd --user: aib-node)" || {
    info "systemd --user unavailable — starting in background automatically"
    RUN_BG=1
  }
else
  info "No systemd (or macOS) — starting in background automatically"
  RUN_BG=1
fi

# ---------- fallback: direct background run ----------
if [ "${RUN_BG:-0}" = "1" ]; then
  mkdir -p "$INSTALL_DIR"
  setsid nohup "$BIN" $NODE_ARGS >> "$INSTALL_DIR/node.log" 2>&1 < /dev/null &
  BG_PID=$!
  ok "Node started in background (pid $BG_PID, log: $INSTALL_DIR/node.log)"
fi

# ---------- health check: wait until up, else show real error ----------
info "Waiting for node to come up..."
UP=0
for i in $(seq 1 15); do
  if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:8080/health" 2>/dev/null; then UP=1; break; fi
  # genesis mismatch from an older chain => auto-migrate: keep wallet, move old chain data aside
  if grep -q "GENESIS HASH MISMATCH" "$INSTALL_DIR/node.log" 2>/dev/null || journalctl --user -u aib-node -n 30 --no-pager 2>/dev/null | grep -q "GENESIS HASH MISMATCH"; then
    warn "Old chain detected (genesis changed with v0.10.0). Migrating..."
    systemctl --user stop aib-node >/dev/null 2>&1 || true
    pkill -f aib-node >/dev/null 2>&1 || true
    TS=$(date +%Y%m%d-%H%M%S)
    BAK="$HOME/.aib-oldchain-$TS"
    mkdir -p "$BAK"
    for f in chain.db utxo.db block_index.db; do
      [ -f "$INSTALL_DIR/$f" ] && mv "$INSTALL_DIR/$f" "$BAK/" 2>/dev/null || true
    done
    [ -d "$INSTALL_DIR/blocks" ] && mv "$INSTALL_DIR/blocks" "$BAK/" 2>/dev/null || true
    ok "Old chain data moved to $BAK (wallet keys kept)"
    systemctl --user start aib-node >/dev/null 2>&1 || true
    sleep 2
  fi
done
if [ "$UP" = "1" ]; then
  ok "Node is UP: http://127.0.0.1:8080/health"
else
  warn "Node did NOT come up in 15s. Last log lines:"
  tail -n 15 "$INSTALL_DIR/node.log" 2>/dev/null | sed 's/^/    /'
  journalctl --user -u aib-node -n 15 --no-pager 2>/dev/null | tail -8 | sed 's/^/    /'
  die "Install incomplete — send the log above to the team"
fi

# ---------- live chain status ----------
info "Node is up. Checking chain sync..."
sleep 3
H=$(curl -s --max-time 4 http://127.0.0.1:8080/v1/block/latest 2>/dev/null | grep -o '"height":[0-9]*' | head -1 | cut -d: -f2)
P=$(curl -s --max-time 4 http://127.0.0.1:8080/v1/peers 2>/dev/null | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2)
ok "Chain height: ${H:-0} | Peers: ${P:-0} (syncing from seed)"

# ---------- interactive setup: delegate ALL logic to the Go binary ----------
# (cross-platform, testable; prompts read /dev/tty so `curl | bash` works)
if [ -x "$BIN" ]; then
  "$BIN" setup -data-dir "$DATA_DIR" -api-port 8080 -p2p-port "$P2P_PORT" || true
else
  info "binary missing — skipping interactive setup"
fi

cat <<'DONE'

  ╔══════════════════════════════════════════════╗
     AIB node is RUNNING  ·  one command, done
  ╚══════════════════════════════════════════════╝

  Status   : curl 127.0.0.1:8080/v1/block/latest
  Health   : curl 127.0.0.1:8080/health
  Mining   : curl 127.0.0.1:8080/v1/mining
  Logs     : journalctl --user -u aib-node -f   (or ~/.aib/node.log)
  Stop     : systemctl --user stop aib-node     (or: pkill -f aib-node)

  ── Start MINING (optional) ────────────────────
  Mining is OFF by default. To mine:
    1. Get your wallet address:
         curl 127.0.0.1:8080/v1/wallet/info
    2. Restart the node in validator mode:
         pkill -f aib-node
         setsid nohup ~/.aib/bin/aib-node \
           -data-dir <your data dir> -api-port 8080 \
           -p2p-port 51413 -validator \
           >> ~/.aib/node.log 2>&1 &
    3. Watch mining stats:
         curl 127.0.0.1:8080/v1/mining
    (mining rewards go to your node wallet; ~1 AIB per block)

  ── Your wallet ────────────────────────────────
  Node wallet : curl 127.0.0.1:8080/v1/wallet/info
                (mining rewards go here; key file: node_key.pem in data dir)
  Balance     : curl 127.0.0.1:8080/v1/balance/<address>
  New wallet  : curl -s -X POST 127.0.0.1:8080/v1/wallet/create \
                 -H 'Content-Type: application/json' \
                 -d '{"label":"main"}'
                (private_key shown ONCE — save it!)
  Explorer    : https://aib.one/explorer.html

DONE
