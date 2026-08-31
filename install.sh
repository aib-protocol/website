#!/usr/bin/env bash
# AIB Node installer — no root required, installs to ~/.aib
# Usage: curl -sSfL https://aib.one/install.sh | bash
set -euo pipefail

VERSION="v0.11.24-testnet"
REPO="aib-protocol/aib"
# Pinned artifact hashes (multi-source integrity anchor).
# Every source must match the pinned hash or the installer refuses to run.
PINNED_SHA256_AMD64="b796fe208825f8e28215799372c121716de639466c2a4a3d6bafbba334ac91cd"
PINNED_SHA256_ARM64="__ARM64__"
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

# ---------- download (multi-source, censorship resistant) ----------
# Order: GitHub -> aib.one mirror -> community P2P nodes.
# Every source serves the SAME file; the pinned hash above is the only
# trust anchor - a malicious mirror cannot make us execute bad code.
SOURCES=(
  "https://github.com/${REPO}/releases/download/${VERSION}"
  "https://aib.one/releases/${VERSION}"
  "http://154.53.40.40:51414/${VERSION}"
  "http://216.180.75.219:51413/${VERSION}"
  "http://144.91.108.90:51413/${VERSION}"
)
PINNED=""
case "$ARCH" in
  amd64) PINNED="$PINNED_SHA256_AMD64" ;;
  arm64) PINNED="$PINNED_SHA256_ARM64" ;;
esac
case "$PINNED" in ""|__*) die "pinned hash missing for $ARCH" ;; esac

mkdir -p "$BIN_DIR"
GOT=""
for SRC in "${SOURCES[@]}"; do
  info "Trying ${SRC} ..."
  rm -f "$BIN.tmp"
  if command -v curl >/dev/null 2>&1; then
    curl -sSfL --max-time 60 "${SRC}/${ASSET}" -o "$BIN.tmp" 2>/dev/null || continue
  else
    wget -q --timeout=60 "${SRC}/${ASSET}" -O "$BIN.tmp" 2>/dev/null || continue
  fi
  [ -s "$BIN.tmp" ] || continue
  GOT="$(sha256sum "$BIN.tmp" 2>/dev/null | awk '{print $1}' || shasum -a 256 "$BIN.tmp" | awk '{print $1}')"
  if [ "$GOT" = "$PINNED" ]; then
    ok "Downloaded + pinned sha256 verified from ${SRC}"
    break
  fi
  warn "Hash mismatch from ${SRC} - trying next source"
  GOT=""
done
[ -n "$GOT" ] || die "all download sources failed or returned bad hashes"

chmod +x "$BIN.tmp"
mv "$BIN.tmp" "$BIN"
ok "Installed: $BIN ($("$BIN" --help >/dev/null 2>&1; echo v0.11.24-testnet))"

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

# ---------- kill any stale node from a previous install ----------
# A stale process may still serve an OLD chain on port 8080 and fool the
# health check below. Stop it so the freshly installed binary takes over.
if pgrep -f aib-node >/dev/null 2>&1; then
  info "Stopping existing aib-node process(es)..."
  systemctl --user stop aib-node >/dev/null 2>&1 || true
  pkill -f aib-node >/dev/null 2>&1 || true
  sleep 2
  pgrep -f aib-node >/dev/null 2>&1 && { pkill -9 -f aib-node >/dev/null 2>&1 || true; sleep 1; }
  systemctl --user reset-failed aib-node >/dev/null 2>&1 || true
  ok "Old node stopped"
fi

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

# ---------- health check: behavior-driven self-heal ----------
# A node that keeps failing to start (corrupt/old chain DB, genesis change)
# shows up as: service active but /health never answers. We do NOT parse logs
# (journald may be unreadable for the user); we watch behavior instead.
info "Waiting for node to come up..."
UP=0
for i in $(seq 1 20); do
  if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:8080/health" 2>/dev/null; then UP=1; break; fi
  sleep 1
done

heal_chain() {  # archive chain DBs (keep wallet keys), restart
  warn "Node failing to start — archiving broken/old chain data (wallet keys kept)"
  systemctl --user stop aib-node >/dev/null 2>&1 || true
  pkill -f aib-node >/dev/null 2>&1 || true
  sleep 1
  local TS BAK f d
  TS=$(date +%Y%m%d-%H%M%S); BAK="$HOME/.aib-oldchain-$TS"; mkdir -p "$BAK"
  for f in chain.db utxo.db block_index.db node.log; do
    for d in "$INSTALL_DIR" "$DATA_DIR"; do
      [ -f "$d/$f" ] && mv "$d/$f" "$BAK/" 2>/dev/null || true
    done
  done
  [ -d "$DATA_DIR/blocks" ] && mv "$DATA_DIR/blocks" "$BAK/" 2>/dev/null || true
  ok "Old chain data archived to $BAK"
  systemctl --user reset-failed aib-node >/dev/null 2>&1 || true
  systemctl --user start aib-node >/dev/null 2>&1 || {
    setsid nohup "$BIN" $NODE_ARGS >> "$INSTALL_DIR/node.log" 2>&1 < /dev/null &
  }
  for i in $(seq 1 25); do
    if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:8080/health" 2>/dev/null; then return 0; fi
    sleep 1
  done
  return 1
}

if [ "$UP" = "0" ]; then
  warn "Node did not come up in 20s — attempting automatic repair..."
  if heal_chain; then
    ok "Repair successful — node is UP with a fresh chain (resyncing)"
    UP=1
  fi
fi

if [ "$UP" = "1" ]; then
  ok "Node is UP: http://127.0.0.1:8080/health"
else
  warn "Node still failing after repair. Last log lines:"
  tail -n 15 "$INSTALL_DIR/node.log" 2>/dev/null | sed 's/^/    /'
  warn "Try manually:  systemctl --user status aib-node"
  warn "If stuck, archive data:  mv ~/.aib ~/.aib-broken && rerun this installer"
  die "Install incomplete — send the log above to the team"
fi

# ---------- chain sync watchdog: detect broken/stale chains and self-heal ----------
height() { curl -s --max-time 4 "http://127.0.0.1:8080/v1/block/latest" 2>/dev/null | grep -o '"height":[0-9]*' | head -1 | cut -d: -f2; }

info "Node is up. Checking chain sync against the network..."
sleep 3
NET_H=$(curl -s --max-time 6 https://aib.one/v1/block/latest 2>/dev/null | grep -o '"height":[0-9]*' | head -1 | cut -d: -f2)
H1=$(height); H1=${H1:-0}
P=$(curl -s --max-time 4 http://127.0.0.1:8080/v1/peers 2>/dev/null | grep -o '"total":[0-9]*' | head -1 | cut -d: -f2)
ok "Local height: $H1 | Network: ${NET_H:-?} | Peers: ${P:-0}"

if [ -n "${NET_H:-}" ] && [ "$NET_H" -gt 0 ] 2>/dev/null; then
  if [ "$H1" -lt $((NET_H > 100 ? NET_H - 100 : 0)) ] 2>/dev/null; then
    info "Far behind network ($H1 vs $NET_H) — watching sync for 60s..."
    sleep 60
    H2=$(height); H2=${H2:-0}
    if [ "$H2" -le "$H1" ]; then
      warn "Height stuck at $H1 (no progress in 60s) — chain data is stale"
      if heal_chain; then ok "Resync started — full history downloads in background"; fi
    else
      ok "Sync in progress ($H1 → $H2), continuing in background"
    fi
  fi
fi

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
