#!/usr/bin/env bash
set -euo pipefail

RELEASE_REPO="${COMPANION_RELEASE_REPO:-aicompaniondev/claw-companion-release}"
INSTALL_DIR="${INSTALL_DIR:-/opt/claw-companion}"
COMPANION_PORT="${COMPANION_PORT:-3210}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
SERVICE_NAME="${SERVICE_NAME:-claw-companion}"
AUTO_CREATE_SWAP="${AUTO_CREATE_SWAP:-1}"
SWAP_SIZE_MB="${SWAP_SIZE_MB:-2048}"

NODE_OK=0
OPENCLAW_OK=0
COMPANION_OK=0
FIREWALL_OK=0
SWAP_OK=0

log() { echo "[cc-install] $*"; }
err() { echo "[cc-install] ERROR: $*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { err "Missing dependency: $1"; exit 1; }; }

is_darwin() { [ "$(uname -s 2>/dev/null || echo)" = "Darwin" ]; }
ensure_root() { if is_darwin; then return 0; fi; [ "$(id -u)" = "0" ] || { err "请使用 root 运行（或 sudo）"; exit 1; }; }

ensure_cmds() {
  command -v curl >/dev/null 2>&1 || {
    if command -v apt-get >/dev/null 2>&1; then apt-get update -y >/dev/null 2>&1 && apt-get install -y curl ca-certificates >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then yum install -y curl ca-certificates >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then dnf install -y curl ca-certificates >/dev/null 2>&1
    else err "缺少 curl"; exit 1; fi
  }
  command -v tar >/dev/null 2>&1 || {
    if command -v apt-get >/dev/null 2>&1; then apt-get update -y >/dev/null 2>&1 && apt-get install -y tar >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then yum install -y tar >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then dnf install -y tar >/dev/null 2>&1
    else err "缺少 tar"; exit 1; fi
  }
  command -v systemctl >/dev/null 2>&1 || { err "缺少 systemctl"; exit 1; }
  command -v node >/dev/null 2>&1 || { err "缺少 node，请先通过 install.sh 安装 Node.js"; exit 1; }
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then apt-get update -y >/dev/null 2>&1 && apt-get install -y coreutils >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then yum install -y coreutils >/dev/null 2>&1 || true
    fi
  fi
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi
}

get_primary_ip() {
  local ip
  ip=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1)
  [ -n "${ip:-}" ] || ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo "${ip:-127.0.0.1}"
}

open_firewall_port() {
  local port="$1"
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
    firewall-cmd --quiet --permanent --add-port="${port}/tcp" || true
    firewall-cmd --quiet --reload || true
    FIREWALL_OK=1
    return 0
  fi
  if command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1 || iptables -I INPUT -p tcp --dport "$port" -j ACCEPT || true
    service iptables save >/dev/null 2>&1 || true
    FIREWALL_OK=1
  fi
}

ensure_swap_if_needed() {
  [ "$AUTO_CREATE_SWAP" = "1" ] || return 0
  [ -r /proc/meminfo ] || return 0
  local mem_kb swap_kb total_mb
  mem_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
  swap_kb=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)
  total_mb=$(( (mem_kb + swap_kb) / 1024 ))
  if [ "$total_mb" -ge 4096 ] 2>/dev/null; then return 0; fi
  if swapon --show | grep -q '/swapfile'; then SWAP_OK=1; return 0; fi

  log "检测到可用内存+交换分区仅 ${total_mb}MB，自动创建 ${SWAP_SIZE_MB}MB swap ..."
  if [ -f /swapfile ]; then
    swapoff /swapfile >/dev/null 2>&1 || true
    rm -f /swapfile >/dev/null 2>&1 || true
  fi
  if command -v fallocate >/dev/null 2>&1; then
    fallocate -l "${SWAP_SIZE_MB}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_SIZE_MB"
  else
    dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_SIZE_MB"
  fi
  chmod 600 /swapfile || true
  mkswap /swapfile >/dev/null 2>&1 || return 0
  swapon /swapfile >/dev/null 2>&1 || return 0
  grep -q '^/swapfile ' /etc/fstab 2>/dev/null || echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
  SWAP_OK=1
}

install_linux() {
  local TMP_DIR API JSON TAG ASSET_NAME SHA_NAME ASSET_URL SHA_URL TARBALL SHAFILE EXPECTED ACTUAL BACKUP NODE_PATH IP COMPANION_VER
  TMP_DIR=$(mktemp -d)
  trap 'rm -rf "$TMP_DIR"' EXIT

  API="https://api.github.com/repos/${RELEASE_REPO}/releases/latest"
  log "Fetching latest release: $API"
  JSON=$(curl -fsSL -H "Accept: application/vnd.github+json" "$API")

  TAG=$(echo "$JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const j=JSON.parse(s);console.log(j.tag_name||'');});")
  [ -n "$TAG" ] || { err "无法解析 latest release tag"; exit 1; }

  ASSET_NAME="claw-companion-${TAG}.tar.gz"
  SHA_NAME="${ASSET_NAME}.sha256"

  ASSET_URL=$(echo "$JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const j=JSON.parse(s);const a=(j.assets||[]).find(x=>x.name==='${ASSET_NAME}');console.log(a?a.browser_download_url:'');});")
  SHA_URL=$(echo "$JSON" | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{const j=JSON.parse(s);const a=(j.assets||[]).find(x=>x.name==='${SHA_NAME}');console.log(a?a.browser_download_url:'');});")

  [ -n "$ASSET_URL" ] || { err "未找到 release asset: $ASSET_NAME"; exit 1; }
  [ -n "$SHA_URL" ] || { err "未找到 release asset: $SHA_NAME"; exit 1; }

  TARBALL="$TMP_DIR/$ASSET_NAME"
  SHAFILE="$TMP_DIR/$SHA_NAME"

  log "Downloading tarball..."
  curl -fsSL -L "$ASSET_URL" -o "$TARBALL"
  log "Downloading checksum..."
  curl -fsSL -L "$SHA_URL" -o "$SHAFILE"

  EXPECTED=$(awk '{print $1}' "$SHAFILE" | tr -d '\r\n')
  ACTUAL=$(sha256_file "$TARBALL")
  [ "$EXPECTED" = "$ACTUAL" ] || { err "Checksum mismatch expected=$EXPECTED actual=$ACTUAL"; exit 1; }

  systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true

  if [ -d "$INSTALL_DIR" ]; then
    BACKUP="${INSTALL_DIR}.bak.$(date +%Y%m%d-%H%M%S)"
    log "Backing up ${INSTALL_DIR} -> ${BACKUP}"
    mv "$INSTALL_DIR" "$BACKUP"
  fi

  mkdir -p "$(dirname "$INSTALL_DIR")"
  tar -xzf "$TARBALL" -C "$TMP_DIR"
  [ -d "$TMP_DIR/claw-companion" ] || { err "Release 包结构异常"; exit 1; }
  mv "$TMP_DIR/claw-companion" "$INSTALL_DIR"

  [ -d "$INSTALL_DIR/server/node_modules" ] || { err "Release 包缺少 server/node_modules"; exit 1; }

  NODE_PATH=$(command -v node)
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Claw伴侣 - OpenClaw Web 管理面板
After=network.target

[Service]
Type=simple
ExecStart=${NODE_PATH} ${INSTALL_DIR}/server/index.js
WorkingDirectory=${INSTALL_DIR}/server
Environment=COMPANION_PORT=${COMPANION_PORT}
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=HOME=/root
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" >/dev/null 2>&1 || true
  systemctl restart "$SERVICE_NAME"
  COMPANION_OK=1
  open_firewall_port "$COMPANION_PORT"

  IP=$(get_primary_ip)
  COMPANION_VER=$(node -p "require('${INSTALL_DIR}/server/package.json').version" 2>/dev/null || echo "unknown")

  echo ""
  echo "╔════════════════════════════════════════════╗"
  echo "║         🎉 Claw伴侣 安装完成              ║"
  echo "╚════════════════════════════════════════════╝"
  echo ""
  printf "  %s Claw伴侣已启动\n" "$( [ "$COMPANION_OK" = 1 ] && echo '✅' || echo '❌' )"
  printf "  %s 防火墙已放行 ${COMPANION_PORT}/tcp\n" "$( [ "$FIREWALL_OK" = 1 ] && echo '✅' || echo '⚠️' )"
  printf "  %s 已启用额外 swap\n" "$( [ "$SWAP_OK" = 1 ] && echo '✅' || echo 'ℹ️' )"
  echo ""
  echo "  Claw伴侣版本:    ${COMPANION_VER}"
  echo "  本机访问:        http://127.0.0.1:${COMPANION_PORT}"
  echo "  局域网访问:      http://${IP}:${COMPANION_PORT}"
  echo "  服务状态:        systemctl status ${SERVICE_NAME}"
  echo "  安装目录:        ${INSTALL_DIR}"
  echo ""
}

main() {
  ensure_root
  ensure_cmds
  ensure_swap_if_needed
  if is_darwin; then
    err "macOS 暂不支持该安装器"
    exit 1
  else
    install_linux
  fi
}

main "$@"
