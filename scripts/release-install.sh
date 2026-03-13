#!/usr/bin/env bash
set -euo pipefail

RELEASE_REPO="${COMPANION_RELEASE_REPO:-aicompaniondev/claw-companion-release}"
TAG="${COMPANION_TAG:-v1.0.12}"
INSTALL_DIR="${INSTALL_DIR:-/opt/claw-companion}"
COMPANION_PORT="${COMPANION_PORT:-3210}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
SERVICE_NAME="${SERVICE_NAME:-claw-companion}"
OPENCLAW_RUNTIME_URL="${OPENCLAW_RUNTIME_URL:-http://45.207.206.189/mirror/openclaw-runtime-2026.2.2.tar.gz}"
COMPANION_MIRROR_BASE="${COMPANION_MIRROR_BASE:-http://45.207.206.189/mirror/releases}"
AUTO_CREATE_SWAP="${AUTO_CREATE_SWAP:-1}"
SWAP_SIZE_MB="${SWAP_SIZE_MB:-2048}"

NODESOURCE_DEB_SETUP="${NODESOURCE_DEB_SETUP:-https://deb.nodesource.com/setup_22.x}"
NODESOURCE_RPM_SETUP="${NODESOURCE_RPM_SETUP:-https://rpm.nodesource.com/setup_22.x}"
NODESOURCE_RPM_BASE="${NODESOURCE_RPM_BASE:-http://45.207.206.189/mirror/nodesource/pub_22.x/nodistro/nodejs}"
NODEJS_RPM_VERSION="${NODEJS_RPM_VERSION:-22.22.0}"
CENTOS7_NODE_TARBALL="${CENTOS7_NODE_TARBALL:-http://45.207.206.189/mirror/node/openclaw-node22-centos7-full-x86_64.tar.gz}"

NODE_OK=0
OPENCLAW_OK=0
COMPANION_OK=0
FIREWALL_OK=0
SWAP_OK=0

is_darwin() { [ "$(uname -s 2>/dev/null || echo)" = "Darwin" ]; }
ensure_root() { if is_darwin; then return 0; fi; [ "$(id -u)" = "0" ] || { echo "请使用 root 运行（或 sudo）" >&2; exit 1; }; }
ensure_cmds() {
  command -v curl >/dev/null 2>&1 || { if command -v apt-get >/dev/null 2>&1; then apt-get update -y >/dev/null 2>&1 && apt-get install -y curl ca-certificates >/dev/null 2>&1; else echo "缺少 curl" >&2; exit 1; fi; }
  command -v tar >/dev/null 2>&1 || { if command -v apt-get >/dev/null 2>&1; then apt-get update -y >/dev/null 2>&1 && apt-get install -y tar >/dev/null 2>&1; else echo "缺少 tar" >&2; exit 1; fi; }
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    if command -v apt-get >/dev/null 2>&1; then apt-get update -y >/dev/null 2>&1 && apt-get install -y coreutils >/dev/null 2>&1; else echo "缺少 sha256" >&2; exit 1; fi
  fi
}
sha256_file() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d" " -f1; else shasum -a 256 "$1" | cut -d" " -f1; fi; }
node_major() { local v; v=$(node -v 2>/dev/null || true); echo "$v" | grep -Eq '^v[0-9]+' || { echo ""; return; }; echo "$v" | sed 's/^v//' | cut -d. -f1; }
openclaw_major() {
  local ver
  ver=$(openclaw-cn --version 2>/dev/null | grep -Eo '[0-9]+(\.[0-9]+){1,3}' | head -n1 || true)
  echo "$ver" | grep -Eq '^[0-9]+' || { echo ""; return; }
  echo "$ver" | cut -d. -f1
}
node_check_output() { node -v 2>&1 || true; }
prompt_upgrade_node() {
  local cur ans; cur=$(node -v 2>/dev/null || echo "unknown"); echo "检测到 Node.js 版本过低：${cur}（需要 22+）" >&2
  if [ -t 0 ]; then printf "是否自动升级到最新版 Node.js 22+？(y/N): " >&2; read -r ans || ans="";
  elif [ -r /dev/tty ]; then printf "是否自动升级到最新版 Node.js 22+？(y/N): " > /dev/tty; read -r ans < /dev/tty || ans="";
  else echo "当前为非交互模式，使用 AUTO_UPGRADE_NODE=1 可自动升级。" >&2; exit 1; fi
  [ "$ans" = "y" ] || [ "$ans" = "Y" ] || { echo "已取消安装。请手动升级 Node.js 到 22+ 后重试。" >&2; exit 1; }
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

  echo "检测到可用内存+交换分区仅 ${total_mb}MB，自动创建 ${SWAP_SIZE_MB}MB swap 以提高安装成功率..." >&2

  # 清理可能损坏/不兼容的旧 swapfile（例如之前失败残留）
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

  if ! mkswap /swapfile >/dev/null 2>&1; then
    echo "警告: mkswap 失败，跳过 swap 创建，继续安装。" >&2
    return 0
  fi

  if ! swapon /swapfile >/dev/null 2>&1; then
    echo "警告: swapon 失败（当前文件系统可能不支持 swapfile），跳过 swap 创建，继续安装。" >&2
    return 0
  fi

  grep -q '^/swapfile ' /etc/fstab 2>/dev/null || echo '/swapfile swap swap defaults 0 0' >> /etc/fstab
  SWAP_OK=1
}
install_node_22_centos7_compat() {
  echo "使用兼容版 Node.js 22 完整运行时（源：${CENTOS7_NODE_TARBALL}）..." >&2
  mkdir -p /tmp/node-compat && cd /tmp/node-compat && rm -f centos7-node-full.tar.gz
  curl -fL --connect-timeout 10 --max-time 900 -o centos7-node-full.tar.gz "$CENTOS7_NODE_TARBALL"
  tar -xzf centos7-node-full.tar.gz
  install -d /usr/local/bin /usr/local/lib
  cp -f openclaw-node22-centos7-full/bin/node /usr/local/bin/node
  rm -f /usr/local/bin/npm /usr/local/bin/npx
  ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
  ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
  rm -rf /usr/local/lib/node_modules
  cp -a openclaw-node22-centos7-full/lib/node_modules /usr/local/lib/
  chmod +x /usr/local/bin/node
  hash -r 2>/dev/null || true
}
install_node_22_centos7_rpm_direct() {
  local arch pkg url
  arch="$(uname -m 2>/dev/null || echo x86_64)"
  pkg="nodejs-${NODEJS_RPM_VERSION}-1nodesource.${arch}.rpm"
  url="${NODESOURCE_RPM_BASE}/${arch}/${pkg}"
  echo "CentOS7 检测到，尝试 NodeSource RPM 安装 Node.js ${NODEJS_RPM_VERSION}（源：${NODESOURCE_RPM_BASE}）..." >&2
  mkdir -p /tmp/node-rpm && cd /tmp/node-rpm && rm -f "$pkg"
  curl -fL --connect-timeout 10 --max-time 300 -o "$pkg" "$url"
  yum -y localinstall "$pkg" || rpm -Uvh --force "$pkg" || return 1
}
install_node_22_linux_standard() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y ca-certificates curl gnupg >/dev/null 2>&1 || true
    curl -fsSL "$NODESOURCE_DEB_SETUP" | bash - >/dev/null 2>&1 || true
    apt-get install -y nodejs || true
    return
  fi
  if command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
    local pm; pm=$(command -v dnf >/dev/null 2>&1 && echo dnf || echo yum)
    $pm -y install ca-certificates curl >/dev/null 2>&1 || true
    curl -fsSL "$NODESOURCE_RPM_SETUP" | bash - >/dev/null 2>&1 || true
    $pm -y install nodejs || true
    return
  fi
  echo "未检测到可用的包管理器，无法自动安装 Node.js" >&2; exit 1
}
ensure_node() {
  local major out
  if command -v node >/dev/null 2>&1; then
    major=$(node_major)
    if [ -n "${major:-}" ] && [ "$major" -ge 22 ] 2>/dev/null && command -v npm >/dev/null 2>&1; then NODE_OK=1; return 0; fi
    [ "${AUTO_UPGRADE_NODE:-}" != "1" ] && prompt_upgrade_node
  else
    echo "未检测到 Node.js，正在自动安装 Node.js 22+..."
  fi
  if is_darwin; then echo "macOS 请先安装 Homebrew + Node.js 22+" >&2; exit 1; fi
  install_node_22_linux_standard || true
  major=$(node_major)
  if [ -n "${major:-}" ] && [ "$major" -ge 22 ] 2>/dev/null && command -v npm >/dev/null 2>&1; then NODE_OK=1; echo "Node.js $(node -v) 已就绪（官方安装路径）" >&2; return 0; fi
  out=$(node_check_output)
  if echo "$out" | grep -Eqi 'GLIBC_|GLIBCXX_|CXXABI_|not found|unknown'; then echo "检测到当前系统/运行时与普通 Node.js 22 不兼容，切换到兼容安装路径..." >&2; else echo "普通 Node.js 安装未成功，切换到兼容安装路径..." >&2; fi
  if command -v yum >/dev/null 2>&1 && [ -f /etc/centos-release ] && grep -qE 'CentOS.* 7' /etc/centos-release 2>/dev/null; then
    install_node_22_centos7_compat || true
    if command -v npm >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then major=$(node_major); if [ -n "${major:-}" ] && [ "$major" -ge 22 ] 2>/dev/null; then NODE_OK=1; echo "Node.js $(node -v) / npm $(npm -v) 已就绪（CentOS7 兼容运行时）" >&2; return 0; fi; fi
    install_node_22_centos7_rpm_direct || true
  fi
  major=$(node_major)
  if [ -z "${major:-}" ] || [ "$major" -lt 22 ] 2>/dev/null || ! command -v npm >/dev/null 2>&1; then echo "Node.js/npm 安装失败（node=$(node -v 2>/dev/null || echo unknown), npm=$(npm -v 2>/dev/null || echo missing)），需要 22+" >&2; exit 1; fi
  NODE_OK=1
  echo "Node.js $(node -v) / npm $(npm -v) 已就绪" >&2
}
ensure_gateway_token() {
  local token
  token=$(openclaw-cn config get gateway.auth.token 2>/dev/null | tail -n 1 | tr -d '\r' | tr -d ' ')
  if [ -n "${token:-}" ] && [ "$token" != "null" ] && [ "$token" != "undefined" ]; then
    return 0
  fi

  local new_token
  if command -v openssl >/dev/null 2>&1; then
    new_token=$(openssl rand -hex 16)
  elif command -v node >/dev/null 2>&1; then
    new_token=$(node -e "console.log(require('crypto').randomBytes(16).toString('hex'))")
  elif [ -r /dev/urandom ]; then
    new_token=$(LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 32)
  else
    new_token=$(date +%s%N | head -c 32)
  fi

  [ -n "${new_token:-}" ] || return 0
  openclaw-cn config set gateway.auth.token "$new_token" >/dev/null 2>&1 || true
}

ensure_openclaw() {
  local maj
  if command -v openclaw-cn >/dev/null 2>&1; then
    maj=$(openclaw_major)
    if [ -n "${maj:-}" ] && [ "$maj" -ge 2026 ] 2>/dev/null; then
      OPENCLAW_OK=1
      echo "OpenClaw $(openclaw-cn --version 2>/dev/null || echo installed) 已存在" >&2
      ensure_openclaw_clipboard_binding
      return 0
    fi
    echo "检测到旧版 OpenClaw：$(openclaw-cn --version 2>/dev/null || echo unknown)，将自动升级到预打包运行时..." >&2
  else
    echo "安装 OpenClaw 运行时（预打包产物）..." >&2
  fi
  ensure_swap_if_needed
  mkdir -p /tmp/openclaw-runtime-inst && cd /tmp/openclaw-runtime-inst && rm -f openclaw-runtime.tar.gz
  curl -fL --connect-timeout 10 --max-time 900 -o openclaw-runtime.tar.gz "$OPENCLAW_RUNTIME_URL"
  tar -xzf openclaw-runtime.tar.gz
  install -d /usr/local/bin /usr/local/lib/node_modules
  rm -rf /usr/local/lib/node_modules/openclaw-cn
  cp -a openclaw-runtime/lib/node_modules/openclaw-cn /usr/local/lib/node_modules/
  rm -f /usr/local/bin/openclaw-cn /usr/local/bin/clawdbot-cn
  ln -s ../lib/node_modules/openclaw-cn/dist/entry.js /usr/local/bin/openclaw-cn
  ln -s ../lib/node_modules/openclaw-cn/dist/entry.js /usr/local/bin/clawdbot-cn
  chmod +x /usr/local/lib/node_modules/openclaw-cn/dist/entry.js
  hash -r 2>/dev/null || true
  command -v openclaw-cn >/dev/null 2>&1 || { echo "OpenClaw 运行时安装失败：未找到 openclaw-cn" >&2; exit 1; }
  ensure_openclaw_clipboard_binding
  ensure_gateway_token
  OPENCLAW_OK=1
  echo "OpenClaw $(openclaw-cn --version 2>/dev/null || echo installed) 已就绪" >&2
}

is_musl() {
  if command -v ldd >/dev/null 2>&1; then
    ldd --version 2>&1 | grep -qi musl && return 0
  fi
  return 1
}

detect_clipboard_pkg() {
  local arch
  arch="$(uname -m 2>/dev/null || echo x86_64)"
  case "$arch" in
    x86_64)
      if is_musl; then echo "@mariozechner/clipboard-linux-x64-musl@0.3.2"; else echo "@mariozechner/clipboard-linux-x64-gnu@0.3.2"; fi
      ;;
    aarch64|arm64)
      if is_musl; then echo "@mariozechner/clipboard-linux-arm64-musl@0.3.2"; else echo "@mariozechner/clipboard-linux-arm64-gnu@0.3.2"; fi
      ;;
    *)
      echo ""
      ;;
  esac
}

patch_clipboard_fallback() {
  local base index
  base="/usr/local/lib/node_modules/openclaw-cn"
  index="$base/node_modules/@mariozechner/clipboard/index.js"
  [ -f "$index" ] || return 0

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$index" <<'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
s = p.read_text()
if "CLAW_CLIPBOARD_DISABLED" in s:
    sys.exit(0)
if "throw loadError" in s:
    s = s.replace("throw loadError", "return {availableFormats:()=>[],getText:()=>\"\",setText:()=>false,hasText:()=>false,getImageBinary:()=>null,getImageBase64:()=>\"\",setImageBinary:()=>false,setImageBase64:()=>false,hasImage:()=>false,getHtml:()=>\"\",setHtml:()=>false,hasHtml:()=>false,getRtf:()=>\"\",setRtf:()=>false,hasRtf:()=>false,clear:()=>false,watch:()=>{},callThreadsafeFunction:()=>{},CLAW_CLIPBOARD_DISABLED:true}")
if "throw new Error(`Failed to load native binding`)" in s:
    s = s.replace("throw new Error(`Failed to load native binding`)", "return {availableFormats:()=>[],getText:()=>\"\",setText:()=>false,hasText:()=>false,getImageBinary:()=>null,getImageBase64:()=>\"\",setImageBinary:()=>false,setImageBase64:()=>false,hasImage:()=>false,getHtml:()=>\"\",setHtml:()=>false,hasHtml:()=>false,getRtf:()=>\"\",setRtf:()=>false,hasRtf:()=>false,clear:()=>false,watch:()=>{},callThreadsafeFunction:()=>{},CLAW_CLIPBOARD_DISABLED:true}")
if "CLAW_CLIPBOARD_DISABLED" in s:
    p.write_text(s)
PY
    return 0
  fi

  if command -v node >/dev/null 2>&1; then
    node - "$index" <<'JS'
const fs = require('fs');
const p = process.argv[2];
let s = fs.readFileSync(p, 'utf8');
if (!s.includes('CLAW_CLIPBOARD_DISABLED')) {
  s = s.replace(
    'throw loadError',
    'return {availableFormats:()=>[],getText:()=>"",setText:()=>false,hasText:()=>false,getImageBinary:()=>null,getImageBase64:()=>"",setImageBinary:()=>false,setImageBase64:()=>false,hasImage:()=>false,getHtml:()=>"",setHtml:()=>false,hasHtml:()=>false,getRtf:()=>"",setRtf:()=>false,hasRtf:()=>false,clear:()=>false,watch:()=>{},callThreadsafeFunction:()=>{},CLAW_CLIPBOARD_DISABLED:true}'
  );
  s = s.replace(
    'throw new Error(`Failed to load native binding`)',
    'return {availableFormats:()=>[],getText:()=>"",setText:()=>false,hasText:()=>false,getImageBinary:()=>null,getImageBase64:()=>"",setImageBinary:()=>false,setImageBase64:()=>false,hasImage:()=>false,getHtml:()=>"",setHtml:()=>false,hasHtml:()=>false,getRtf:()=>"",setRtf:()=>false,hasRtf:()=>false,clear:()=>false,watch:()=>{},callThreadsafeFunction:()=>{},CLAW_CLIPBOARD_DISABLED:true}'
  );
  if (s.includes('CLAW_CLIPBOARD_DISABLED')) fs.writeFileSync(p, s);
}
JS
    return 0
  fi

  echo "警告: 无 python3/node，无法自动切换为无剪贴板模式。" >&2
}

ensure_openclaw_clipboard_binding() {
  local base pkg
  base="/usr/local/lib/node_modules/openclaw-cn"
  [ -f "$base/node_modules/@mariozechner/clipboard/index.js" ] || return 0

  if node -e "require('$base/node_modules/@mariozechner/clipboard')" >/dev/null 2>&1; then
    return 0
  fi

  pkg="$(detect_clipboard_pkg)"
  if [ -z "${pkg:-}" ]; then
    echo "警告: 无法识别当前架构的 clipboard 本地绑定，跳过自动修复。" >&2
    return 0
  fi

  echo "检测到 OpenClaw 缺失本地 clipboard 绑定，正在修复: ${pkg}" >&2
  npm --prefix "$base" install --omit=dev --no-audit "$pkg" >/dev/null 2>&1 \
    || npm --prefix "$base" install "$pkg" >/dev/null 2>&1 \
    || { echo "警告: clipboard 本地绑定安装失败，尝试降级为无剪贴板模式。" >&2; }

  if node -e "require('$base/node_modules/@mariozechner/clipboard')" >/dev/null 2>&1; then
    echo "OpenClaw clipboard 本地绑定修复成功。" >&2
  else
    echo "警告: clipboard 绑定仍不可用，自动切换为无剪贴板模式。" >&2
    patch_clipboard_fallback
  fi
}
open_firewall_port() {
  local port="$1"
  if command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then firewall-cmd --quiet --permanent --add-port="${port}/tcp" || true; firewall-cmd --quiet --reload || true; FIREWALL_OK=1; echo "已放行防火墙端口 ${port}/tcp（firewalld）" >&2; return 0; fi
  if command -v iptables >/dev/null 2>&1; then iptables -C INPUT -p tcp --dport "$port" -j ACCEPT >/dev/null 2>&1 || iptables -I INPUT -p tcp --dport "$port" -j ACCEPT || true; service iptables save >/dev/null 2>&1 || true; FIREWALL_OK=1; echo "已尝试放行防火墙端口 ${port}/tcp（iptables）" >&2; return 0; fi
  return 0
}
get_primary_ip() { local ip; ip=$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n 1); [ -n "${ip:-}" ] || ip=$(hostname -I 2>/dev/null | awk '{print $1}'); echo "${ip:-127.0.0.1}"; }
install_linux() {
  local tag base tarball sha expected actual dest parent tmpdir ts node_path ip claw_ver companion_ver
  tag="$TAG"
  base="${COMPANION_MIRROR_BASE}/${tag}"
  tarball="claw-companion-${tag}.tar.gz"
  sha="${tarball}.sha256"
  mkdir -p /tmp/claw-companion-inst && cd /tmp/claw-companion-inst && rm -f "$tarball" "$sha"
  curl -fL -o "$tarball" "$base/$tarball"
  curl -fL -o "$sha" "$base/$sha"
  expected=$(cut -d" " -f1 "$sha")
  actual=$(sha256_file "$tarball")
  [ "$expected" = "$actual" ]
  systemctl stop "$SERVICE_NAME" >/dev/null 2>&1 || true
  dest="$INSTALL_DIR"
  parent=$(dirname "$dest")
  tmpdir="${parent}/.claw-companion.new.${tag}"
  rm -rf "$tmpdir" 2>/dev/null || true
  mkdir -p "$tmpdir"
  tar -xzf "$tarball" -C "$tmpdir"
  ts=$(date +%s)
  [ ! -d "$dest" ] || mv "$dest" "${dest}.bak.${ts}"
  mv "$tmpdir/claw-companion" "$dest"
  rm -rf "$tmpdir" 2>/dev/null || true
  if [ ! -d "$dest/server/node_modules" ]; then echo "Release 包缺少 server/node_modules，请重新发布自包含 release 后再安装" >&2; exit 1; fi
  node_path=$(command -v node)
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Claw伴侣 - OpenClaw Web 管理面板
After=network.target

[Service]
Type=simple
ExecStart=${node_path} ${dest}/server/index.js
WorkingDirectory=${dest}/server
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
  ip=$(get_primary_ip)
  claw_ver=$(openclaw-cn --version 2>/dev/null || echo "unknown")
  companion_ver=$(node -p "require('${dest}/server/package.json').version" 2>/dev/null || echo "unknown")
  echo ""
  echo "╔════════════════════════════════════════════╗"
  echo "║         🎉 OpenClaw 安装完成              ║"
  echo "╚════════════════════════════════════════════╝"
  echo ""
  printf "  %s Node.js 已安装\n" "$( [ "$NODE_OK" = 1 ] && echo '✅' || echo '❌' )"
  printf "  %s OpenClaw 已安装\n" "$( [ "$OPENCLAW_OK" = 1 ] && echo '✅' || echo '❌' )"
  printf "  %s Claw伴侣已启动\n" "$( [ "$COMPANION_OK" = 1 ] && echo '✅' || echo '❌' )"
  printf "  %s 防火墙已放行 ${COMPANION_PORT}/tcp\n" "$( [ "$FIREWALL_OK" = 1 ] && echo '✅' || echo '⚠️' )"
  printf "  %s 已启用额外 swap\n" "$( [ "$SWAP_OK" = 1 ] && echo '✅' || echo 'ℹ️' )"
  echo ""
  echo "  OpenClaw 版本:   ${claw_ver}"
  echo "  Claw伴侣版本:    ${companion_ver}"
  echo ""
  echo "  本机访问:        http://127.0.0.1:${COMPANION_PORT}"
  echo "  局域网访问:      http://${ip}:${COMPANION_PORT}"
  echo "  Gateway 端口:    ${GATEWAY_PORT}"
  echo ""
  echo "  服务状态:        systemctl status ${SERVICE_NAME}"
  echo "  安装目录:        ${dest}"
  echo ""
}
main() { ensure_root; ensure_cmds; ensure_node; ensure_openclaw; if is_darwin; then echo "macOS 暂不支持该安装器" >&2; exit 1; else install_linux; fi; }
main "$@"
