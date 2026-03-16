#!/bin/bash
# ============================================================
# Claw伴侣 🐾 一键安装脚本 (macOS + Linux)
# 安装 Clawdbot + Claw伴侣 Web 管理面板
# ============================================================

# 修复 cwd 被删除的问题
cd "$HOME" 2>/dev/null || cd / 2>/dev/null

# ---- 自动获取最新脚本 ----
if [ -z "$CLAW_FRESH" ]; then
  FRESH_TMP="/tmp/claw-install-$$.sh"
  # 多镜像源，兼容中国大陆网络
  for _url in \
    "https://cdn.jsdelivr.net/gh/aicompaniondev/claw-companion-release@main/scripts/install.sh" \
    "https://raw.githubusercontent.com/aicompaniondev/claw-companion-release/main/scripts/install.sh" \
    "https://raw.gitmirror.com/aicompaniondev/claw-companion-release/main/scripts/install.sh"; do
    curl -fsSL --connect-timeout 5 "$_url" -o "$FRESH_TMP" 2>/dev/null && [ -s "$FRESH_TMP" ] && break
    rm -f "$FRESH_TMP" 2>/dev/null
  done
  if [ -s "$FRESH_TMP" ]; then
    export CLAW_FRESH=1
    exec bash "$FRESH_TMP"
  fi
  rm -f "$FRESH_TMP" 2>/dev/null
  # 如果所有源都失败，尝试用 git 更新本地官网来获取最新脚本
  if [ -d "$HOME/.openclaw/site/.git" ]; then
    cd "$HOME/.openclaw/site" && git pull < /dev/null >/dev/null 2>&1
    cd "$HOME" 2>/dev/null
  fi
fi

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

COMPANION_PORT="${COMPANION_PORT:-3210}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
DEPLOY_TRACK_URL="${DEPLOY_TRACK_URL:-https://clawcp.top/api/track-deploy}"
INSTALL_DIR="$HOME/.openclaw/companion"
REPO_URL="https://github.com/aicompaniondev/claw-companion-release.git"
MIN_NODE_MAJOR=22
NODE_INSTALL_VER="22.22.0"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
NODE_MIRROR_BASE="${NODE_MIRROR_BASE:-https://npmmirror.com/mirrors/node}"
NODE_UNOFFICIAL_MIRROR_BASE="${NODE_UNOFFICIAL_MIRROR_BASE:-https://npmmirror.com/mirrors/node-unofficial-builds}"
NPM_SHARP_MIRROR="${NPM_SHARP_MIRROR:-https://npmmirror.com/mirrors/sharp/}"
REPO_MIRRORS=(
  "$REPO_URL"
  "https://gitclone.com/github.com/aicompaniondev/claw-companion-release.git"
  "https://ghproxy.com/https://github.com/aicompaniondev/claw-companion-release.git"
)
REPO_ARCHIVE_MIRRORS=(
  "http://45.207.206.189/mirror/files/claw-companion-main.tar.gz"
  "https://cdn.jsdelivr.net/gh/aicompaniondev/claw-companion-release@main.tar.gz"
  "https://gitclone.com/github.com/aicompaniondev/claw-companion-release/archive/refs/heads/main.tar.gz"
  "https://ghproxy.com/https://github.com/aicompaniondev/claw-companion-release/archive/refs/heads/main.tar.gz"
  "https://codeload.github.com/aicompaniondev/claw-companion-release/tar.gz/refs/heads/main"
)

banner() {
  echo ""
  echo -e "${CYAN}${BOLD}"
  echo "   ██████╗██╗      █████╗ ██╗    ██╗"
  echo "  ██╔════╝██║     ██╔══██╗██║    ██║"
  echo "  ██║     ██║     ███████║██║ █╗ ██║"
  echo "  ██║     ██║     ██╔══██║██║███╗██║"
  echo "  ╚██████╗███████╗██║  ██║╚███╔███╔╝"
  echo "   ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝"
  echo -e "${NC}"
  echo -e "  ${BOLD}🐾 Claw伴侣 — Clawdbot 可视化管理面板${NC}"
  echo -e "  ${CYAN}一键部署，浏览器管理一切${NC}"
  echo ""
}

info()  { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}!${NC} $1"; }
error() { echo -e "  ${RED}✗${NC} $1"; }
step()  { echo -e "\n${BLUE}${BOLD}▸ $1${NC}"; }

set_npm_mirror_env() {
  export NPM_CONFIG_REGISTRY="$NPM_REGISTRY"
  export npm_config_registry="$NPM_REGISTRY"
  export npm_config_sharp_binary_host="$NPM_SHARP_MIRROR"
  export npm_config_sharp_libvips_binary_host="$NPM_SHARP_MIRROR"
  export npm_config_disturl="$NODE_MIRROR_BASE"
}

download_with_mirrors() {
  local out="$1"; shift
  local url
  for url in "$@"; do
    [ -z "$url" ] && continue
    if curl -fSL --connect-timeout 10 --max-time 1200 "$url" -o "$out" --progress-bar < /dev/null; then
      return 0
    fi
  done
  return 1
}

git_clone_with_mirrors() {
  local dest="$1"; shift
  local repo
  for repo in "$@"; do
    [ -z "$repo" ] && continue
    git clone --depth 1 "$repo" "$dest" < /dev/null 2>&1 | tail -3
    if [ -f "$dest/server/index.js" ]; then
      return 0
    fi
    rm -rf "$dest" 2>/dev/null || true
  done
  return 1
}

download_repo_archive() {
  local dest="$1"
  local tmp="/tmp/claw-companion-$$.tar.gz"
  rm -f "$tmp" 2>/dev/null || true
  if ! download_with_mirrors "$tmp" "${REPO_ARCHIVE_MIRRORS[@]}"; then
    return 1
  fi
  rm -rf "$dest" 2>/dev/null || true
  mkdir -p "$dest"
  tar -xzf "$tmp" -C "$dest" --strip-components=1 2>/dev/null || true
  if [ ! -f "$dest/server/index.js" ]; then
    rm -rf "$dest" 2>/dev/null || true
    mkdir -p "$dest"
    tar -xzf "$tmp" -C "$dest" 2>/dev/null || true
  fi
  rm -f "$tmp" 2>/dev/null || true
  [ -f "$dest/server/index.js" ] || return 1
  return 0
}

# ======================== 检测系统 ========================
detect_os() {
  step "检测系统环境"
  case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux)  OS="linux" ;;
    *)      error "不支持的操作系统: $(uname -s)"; exit 1 ;;
  esac
  ARCH="$(uname -m)"
  IS_ROOT=false
  [ "$(id -u)" = "0" ] && IS_ROOT=true
  info "系统: $OS ($ARCH)$(${IS_ROOT} && echo ' [root]')"
}

# ======================== 安装系统依赖 ========================
install_pkg() {
  if command -v apt-get &>/dev/null; then
    apt-get update -qq < /dev/null >/dev/null 2>&1 || true
    apt-get install -y "$@" < /dev/null >/dev/null 2>&1
  elif command -v dnf &>/dev/null; then
    dnf makecache -y < /dev/null >/dev/null 2>&1 || true
    dnf install -y "$@" < /dev/null >/dev/null 2>&1
  elif command -v yum &>/dev/null; then
    yum makecache -y < /dev/null >/dev/null 2>&1 || true
    yum install -y "$@" < /dev/null >/dev/null 2>&1
  elif command -v microdnf &>/dev/null; then
    microdnf install -y "$@" < /dev/null >/dev/null 2>&1
  elif command -v apk &>/dev/null; then
    apk add --no-cache "$@" < /dev/null >/dev/null 2>&1
  elif command -v zypper &>/dev/null; then
    zypper -n install "$@" < /dev/null >/dev/null 2>&1
  elif command -v pacman &>/dev/null; then
    pacman -Sy --noconfirm "$@" < /dev/null >/dev/null 2>&1
  fi
}

ensure_git() {
  if ! command -v git &>/dev/null; then
    step "安装 git"
    if [ "$OS" = "linux" ]; then
      install_pkg git
    elif [ "$OS" = "macos" ]; then
      xcode-select --install 2>/dev/null || true
    fi
    command -v git &>/dev/null && info "git 已安装" || { error "git 安装失败"; exit 1; }
  fi
}

ensure_curl() {
  if ! command -v curl &>/dev/null; then
    install_pkg curl ca-certificates
    command -v curl &>/dev/null || { error "curl 安装失败"; exit 1; }
  fi
}

ensure_dbus() {
  if [ "$OS" = "linux" ] && ! command -v dbus-launch &>/dev/null; then
    step "安装 dbus-launch (openclaw-cn 需要)"
    install_pkg dbus-x11
    if ! command -v dbus-launch &>/dev/null; then
      install_pkg dbus
    fi
    command -v dbus-launch &>/dev/null && info "dbus-launch ✓" || warn "dbus-launch 安装失败，Gateway 功能可能受限"
  fi
}

# ======================== 检查/安装/升级 Node.js ========================

get_glibc_ver() {
  local ver
  ver=$(ldd --version 2>&1 | head -1 | sed 's/.*[^0-9]\([0-9]\+\.[0-9]\+\).*/\1/')
  if echo "$ver" | grep -q '^[0-9]\+\.[0-9]\+$'; then
    echo "$ver"
  else
    echo "0.0"
  fi
}

install_node_binary() {
  case "$(uname -m)" in
    x86_64)  NODE_ARCH="x64" ;;
    aarch64) NODE_ARCH="arm64" ;;
    armv7l)  NODE_ARCH="armv7l" ;;
    *)       error "不支持的 CPU 架构: $(uname -m)"; exit 1 ;;
  esac

  local GLIBC_VER
  GLIBC_VER=$(get_glibc_ver)
  local GLIBC_MAJOR GLIBC_MINOR GLIBC_NUM
  GLIBC_MAJOR=$(echo "$GLIBC_VER" | cut -d. -f1)
  GLIBC_MINOR=$(echo "$GLIBC_VER" | cut -d. -f2)
  GLIBC_NUM=$(( GLIBC_MAJOR * 100 + GLIBC_MINOR ))

  info "系统 glibc: ${GLIBC_VER}"

  local NODE_URLS=()
  if [ "$GLIBC_NUM" -lt 228 ]; then
    info "glibc < 2.28，使用兼容版 (unofficial-builds)..."
    NODE_URLS=(
      "${NODE_UNOFFICIAL_MIRROR_BASE}/v${NODE_INSTALL_VER}/node-v${NODE_INSTALL_VER}-linux-${NODE_ARCH}-glibc-217.tar.xz"
      "https://unofficial-builds.nodejs.org/download/release/v${NODE_INSTALL_VER}/node-v${NODE_INSTALL_VER}-linux-${NODE_ARCH}-glibc-217.tar.xz"
    )
  else
    NODE_URLS=(
      "${NODE_MIRROR_BASE}/v${NODE_INSTALL_VER}/node-v${NODE_INSTALL_VER}-linux-${NODE_ARCH}.tar.xz"
      "https://nodejs.org/dist/v${NODE_INSTALL_VER}/node-v${NODE_INSTALL_VER}-linux-${NODE_ARCH}.tar.xz"
    )
  fi

  local NODE_TMP="/tmp/node-v${NODE_INSTALL_VER}.tar.xz"

  info "下载 Node.js v${NODE_INSTALL_VER}..."
  for u in "${NODE_URLS[@]}"; do echo -e "  ${CYAN}${u}${NC}"; done
  if ! download_with_mirrors "$NODE_TMP" "${NODE_URLS[@]}"; then
    error "下载 Node.js 失败，请检查网络"
    exit 1
  fi

  # 确保 xz 可用
  if ! command -v xz &>/dev/null; then
    install_pkg xz xz-utils
  fi

  info "解压并安装到 /usr/local ..."
  rm -rf /usr/local/lib/node_modules/npm
  if ! tar xJf "$NODE_TMP" -C /usr/local --strip-components=1; then
    error "解压 Node.js 失败"
    exit 1
  fi

  rm -f "$NODE_TMP"
  hash -r 2>/dev/null || true

  if command -v node &>/dev/null && command -v npm &>/dev/null; then
    info "Node.js $(node -v) + npm $(npm -v) ✓"
  else
    error "Node.js 安装失败"
    exit 1
  fi
}

install_node_macos() {
  if command -v brew &>/dev/null; then
    brew install node@22 2>/dev/null || brew upgrade node@22 2>/dev/null || true
    if [ -d "/opt/homebrew/opt/node@22/bin" ]; then
      export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
      grep -q 'node@22' ~/.zshrc 2>/dev/null || echo 'export PATH="/opt/homebrew/opt/node@22/bin:$PATH"' >> ~/.zshrc
    fi
  else
    error "请先安装 Homebrew:"
    echo -e "  ${CYAN}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
    exit 1
  fi
}

check_node() {
  step "检查 Node.js 环境"

  local need_install=false

  if command -v node &>/dev/null; then
    local NODE_VER
    NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_VER" -ge "$MIN_NODE_MAJOR" ] 2>/dev/null && npm -v &>/dev/null; then
      info "Node.js $(node -v) + npm $(npm -v) ✓"
      return 0
    else
      if [ "$NODE_VER" -lt "$MIN_NODE_MAJOR" ] 2>/dev/null; then
        warn "Node.js $(node -v) 版本过低 (需要 >= $MIN_NODE_MAJOR)，自动升级..."
      else
        warn "Node.js $(node -v) 或 npm 异常，重新安装..."
      fi
      need_install=true
    fi
  else
    warn "未检测到 Node.js，自动安装..."
    need_install=true
  fi

  if $need_install; then
    echo -e "  ${YELLOW}正在安装 Node.js ${NODE_INSTALL_VER}（可能需要 1-2 分钟）...${NC}"
    if [ "$OS" = "macos" ]; then
      install_node_macos
    elif [ "$OS" = "linux" ]; then
      install_node_binary
    fi

    hash -r 2>/dev/null || true

    # 最终验证
    if command -v node &>/dev/null; then
      local NEW_VER
      NEW_VER=$(node -v | sed 's/v//' | cut -d. -f1)
      if [ "$NEW_VER" -ge "$MIN_NODE_MAJOR" ] 2>/dev/null && npm -v &>/dev/null; then
        info "Node.js $(node -v) + npm $(npm -v) ✓"
      else
        error "Node.js 安装异常 ($(node -v))，请重试或手动安装 Node.js >= $MIN_NODE_MAJOR"
        exit 1
      fi
    else
      error "Node.js 安装失败，请手动安装: https://nodejs.org"
      exit 1
    fi
  fi
}

# ======================== 修复 npm 权限 (非 root Linux) ========================
fix_npm_permissions() {
  if [ "$OS" = "linux" ] && ! $IS_ROOT; then
    local NPM_PREFIX
    NPM_PREFIX=$(npm config get prefix 2>/dev/null || echo "/usr")
    if [ "$NPM_PREFIX" = "/usr" ] || [ "$NPM_PREFIX" = "/usr/local" ]; then
      step "修复 npm 全局安装权限"
      mkdir -p ~/.npm-global
      npm config set prefix '~/.npm-global' < /dev/null
      export PATH=~/.npm-global/bin:$PATH
      for rc in ~/.bashrc ~/.zshrc; do
        if [ -f "$rc" ]; then
          grep -q '.npm-global' "$rc" 2>/dev/null || echo 'export PATH=~/.npm-global/bin:$PATH' >> "$rc"
        fi
      done
      info "npm 全局目录设为 ~/.npm-global"
    fi
  fi
}

# ======================== 检查/添加交换空间 (低内存服务器) ========================
check_swap() {
  if [ "$OS" != "linux" ] || ! $IS_ROOT; then return 0; fi
  if ! command -v free &>/dev/null; then return 0; fi
  local avail_mb
  avail_mb=$(free -m 2>/dev/null | awk '/^Mem:/{print $7}') || return 0
  if [ -n "$avail_mb" ] && [ "$avail_mb" -lt 1024 ]; then
    step "内存不足，检查交换空间..."
    if [ ! -f /swapfile ]; then
      dd if=/dev/zero of=/swapfile bs=1M count=2048 status=none 2>/dev/null
      chmod 600 /swapfile
      mkswap /swapfile >/dev/null 2>&1
      swapon /swapfile 2>/dev/null || true
      grep -q '/swapfile' /etc/fstab 2>/dev/null || echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
      info "交换空间创建完成 (2GB)"
    else
      swapon /swapfile 2>/dev/null || true
      info "交换空间已启用"
    fi
  fi
}

# ======================== 安装 Clawdbot ========================
install_clawdbot() {
  step "安装 Clawdbot (openclaw-cn)"

  if command -v openclaw-cn &>/dev/null; then
    local ver
    ver=$(openclaw-cn --version 2>/dev/null || echo "?")
    info "已安装 Clawdbot ($ver)，正在更新..."
  fi

  step "正在下载安装（首次需要 3-10 分钟，请耐心等待）..."
  export SHARP_IGNORE_GLOBAL_LIBVIPS=1
  export NODE_OPTIONS="--max-old-space-size=1536"
  set_npm_mirror_env

  npm --registry "$NPM_REGISTRY" install -g openclaw-cn@latest --prefer-offline --no-audit < /dev/null 2>&1 | tail -10
  hash -r 2>/dev/null || true

  if ! command -v openclaw-cn &>/dev/null; then
    warn "首次安装失败，尝试降级安装..."
    npm --registry "$NPM_REGISTRY" install -g openclaw-cn@latest --omit=optional --no-audit < /dev/null 2>&1 | tail -5
    hash -r 2>/dev/null || true
  fi

  if command -v openclaw-cn &>/dev/null; then
    info "Clawdbot $(openclaw-cn --version 2>/dev/null) ✓"
  else
    error "Clawdbot 安装失败，可能是内存不足或网络问题"
    echo -e "  建议: ${CYAN}手动执行 npm install -g openclaw-cn@latest${NC}"
    exit 1
  fi
}

# ======================== 安装 Claw伴侣 ========================
install_companion() {
  step "安装 Claw伴侣 管理面板"

  # 清理旧安装
  if [ -d "$INSTALL_DIR" ]; then
    rm -rf "$INSTALL_DIR"
    info "已清理旧安装"
  fi

  # 判断是本地安装还是远程安装
  local SCRIPT_DIR SOURCE_DIR
  SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
  SOURCE_DIR="$(dirname "$SCRIPT_DIR" 2>/dev/null)" || SOURCE_DIR=""

  if [ -n "$SOURCE_DIR" ] && [ -f "$SOURCE_DIR/server/index.js" ] && [ -d "$SOURCE_DIR/.git" ]; then
    cp -r "$SOURCE_DIR/." "$INSTALL_DIR/"
    info "本地文件已复制到 $INSTALL_DIR"
  else
    info "从镜像获取项目..."
    if download_repo_archive "$INSTALL_DIR"; then
      info "压缩包下载完成"
    else
      warn "压缩包下载失败，尝试 git 克隆..."
      ensure_git
      if ! git_clone_with_mirrors "$INSTALL_DIR" "${REPO_MIRRORS[@]}"; then
        error "Git 克隆失败，请检查网络"
        exit 1
      fi
      info "克隆完成"
    fi
  fi

  cd "$INSTALL_DIR/server" || { error "安装目录异常"; exit 1; }
  set_npm_mirror_env
  npm --registry "$NPM_REGISTRY" install --omit=dev < /dev/null 2>&1 | tail -2
  info "依赖安装完成"
}

# ======================== 创建 Gateway 系统服务 ========================
setup_gateway_service() {
  if [ "$OS" != "linux" ] || ! $IS_ROOT; then return 0; fi
  if ! command -v openclaw-cn &>/dev/null; then return 0; fi

  step "配置 Gateway 系统服务"
  local GW_SERVICE="/etc/systemd/system/openclaw-gateway.service"
  local NODE_PATH
  NODE_PATH=$(which node)
  local OPENCLAW_PATH
  OPENCLAW_PATH=$(which openclaw-cn)

  systemctl stop openclaw-gateway.service 2>/dev/null || true

  cat > "$GW_SERVICE" <<EOF
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
ExecStart=${OPENCLAW_PATH} gateway --allow-unconfigured --bind lan
WorkingDirectory=${HOME}
Environment=PATH=/usr/local/bin:/usr/bin:/bin
Environment=HOME=${HOME}
Environment=NODE_OPTIONS=--max-old-space-size=1536
Environment=OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=1
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable openclaw-gateway.service >/dev/null 2>&1
  info "Gateway 系统服务已注册 (openclaw-gateway)"
}

# ======================== 配置 nginx Gateway 代理 ========================
setup_nginx_gateway_proxy() {
  if [ "$OS" != "linux" ] || ! $IS_ROOT; then return 0; fi
  if ! command -v openclaw-cn &>/dev/null; then return 0; fi

  step "配置 Gateway nginx 代理 (HTTPS 端口 18800)"
  local GW_PORT=18789 PROXY_PORT=18800

  if ! command -v nginx &>/dev/null; then
    if command -v yum &>/dev/null; then
      yum install -y epel-release < /dev/null >/dev/null 2>&1
      yum install -y nginx < /dev/null >/dev/null 2>&1
    elif command -v apt-get &>/dev/null; then
      apt-get update -qq < /dev/null >/dev/null 2>&1
      apt-get install -y nginx < /dev/null >/dev/null 2>&1
    fi
  fi

  if ! command -v nginx &>/dev/null; then
    warn "nginx 未安装，跳过代理配置。远程访问请运行: curl -fsSL .../fix-gateway.sh | bash"
    return 0
  fi

  local NGINX_CONF="/etc/nginx/nginx.conf"
  if [ -f "$NGINX_CONF" ] && grep -qE "listen[[:space:]]+80[[:space:];]" "$NGINX_CONF"; then
    cp -n "$NGINX_CONF" "${NGINX_CONF}.bak" 2>/dev/null
    sed -i 's/\(listen[[:space:]]*\)80\([[:space:];]\)/\19080\2/g' "$NGINX_CONF"
    sed -i 's/\[::\]:80\([[:space:];]\)/[::]:9080\1/g' "$NGINX_CONF"
  fi

  rm -f /etc/nginx/conf.d/default.conf 2>/dev/null
  mkdir -p /etc/nginx/ssl
  if [ ! -f /etc/nginx/ssl/openclaw.crt ]; then
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout /etc/nginx/ssl/openclaw.key -out /etc/nginx/ssl/openclaw.crt \
      -subj "/CN=openclaw" < /dev/null 2>/dev/null
  fi

  cat > /etc/nginx/conf.d/openclaw-gateway.conf <<NGXEOF
server {
    listen ${PROXY_PORT} ssl;
    ssl_certificate /etc/nginx/ssl/openclaw.crt;
    ssl_certificate_key /etc/nginx/ssl/openclaw.key;
    location / {
        proxy_pass http://127.0.0.1:${GW_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header Origin https://127.0.0.1:${GW_PORT};
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
    }
}
NGXEOF

  if nginx -t 2>&1 | grep -q "successful"; then
    systemctl enable nginx >/dev/null 2>&1
    systemctl restart nginx 2>/dev/null
    if systemctl is-active nginx &>/dev/null; then
      info "Gateway 代理已启动: https://公网IP:${PROXY_PORT}"
    fi
  fi
}

# ======================== 创建系统服务 ========================
setup_service() {
  step "设置开机自启"

  if [ "$OS" = "macos" ]; then
    setup_launchctl
  elif [ "$OS" = "linux" ]; then
    if $IS_ROOT; then
      setup_systemd_system
    else
      setup_systemd_user
    fi
  fi
}

setup_launchctl() {
  local PLIST="$HOME/Library/LaunchAgents/com.claw.companion.plist"
  local NODE_PATH
  NODE_PATH=$(which node)
  mkdir -p "$HOME/Library/LaunchAgents"

  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claw.companion</string>
    <key>ProgramArguments</key>
    <array>
        <string>${NODE_PATH}</string>
        <string>${INSTALL_DIR}/server/index.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${INSTALL_DIR}/server</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>COMPANION_PORT</key>
        <string>${COMPANION_PORT}</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>StandardOutPath</key>
    <string>${INSTALL_DIR}/companion.log</string>
    <key>StandardErrorPath</key>
    <string>${INSTALL_DIR}/companion.log</string>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
</dict>
</plist>
EOF

  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  info "macOS 服务已注册 (launchctl)"
}

setup_systemd_system() {
  local SERVICE_FILE="/etc/systemd/system/claw-companion.service"
  local NODE_PATH
  NODE_PATH=$(which node)
  local NPM_BIN
  NPM_BIN=$(dirname "$(which npm 2>/dev/null || echo /usr/local/bin/npm)")
  local FULL_PATH="/usr/local/bin:/usr/bin:/bin:${NPM_BIN}:${HOME}/.npm-global/bin"

  systemctl stop claw-companion.service 2>/dev/null || true

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Claw伴侣 - Clawdbot Web 管理面板
After=network.target

[Service]
Type=simple
ExecStart=${NODE_PATH} ${INSTALL_DIR}/server/index.js
WorkingDirectory=${INSTALL_DIR}/server
Environment=COMPANION_PORT=${COMPANION_PORT}
Environment=PATH=${FULL_PATH}
Environment=HOME=${HOME}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable claw-companion.service >/dev/null 2>&1
  systemctl start claw-companion.service
  info "Linux 服务已注册 (systemd system)"
}

setup_systemd_user() {
  local SERVICE_DIR="$HOME/.config/systemd/user"
  local SERVICE_FILE="$SERVICE_DIR/claw-companion.service"
  local NODE_PATH
  NODE_PATH=$(which node)
  local NPM_BIN
  NPM_BIN=$(dirname "$(which npm 2>/dev/null || echo /usr/local/bin/npm)")
  local FULL_PATH="/usr/local/bin:/usr/bin:/bin:${NPM_BIN}:${HOME}/.npm-global/bin"
  mkdir -p "$SERVICE_DIR"

  systemctl --user stop claw-companion.service 2>/dev/null || true

  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Claw伴侣 - Clawdbot Web 管理面板
After=network.target

[Service]
Type=simple
ExecStart=${NODE_PATH} ${INSTALL_DIR}/server/index.js
WorkingDirectory=${INSTALL_DIR}/server
Environment=COMPANION_PORT=${COMPANION_PORT}
Environment=PATH=${FULL_PATH}
Environment=HOME=${HOME}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload
  systemctl --user enable claw-companion.service >/dev/null 2>&1
  systemctl --user start claw-companion.service
  info "Linux 服务已注册 (systemd user)"
}

# ======================== 同步更新官网脚本 ========================
update_site_if_exists() {
  local SITE_DIR="$HOME/.openclaw/site"
  if [ -d "$SITE_DIR/.git" ]; then
    step "同步更新官网脚本"
    cd "$SITE_DIR" && git pull < /dev/null >/dev/null 2>&1
    # 重启官网服务（如果存在）
    if systemctl is-active claw-site &>/dev/null; then
      systemctl restart claw-site 2>/dev/null || true
    fi
    info "官网脚本已同步"
    cd "$HOME"
  fi
}

# ======================== 验证安装 ========================
verify_install() {
  step "验证安装"

  # 检查关键文件
  if [ ! -f "$INSTALL_DIR/server/index.js" ]; then
    error "安装目录异常，缺少核心文件"
    exit 1
  fi
  info "核心文件 ✓"

  # 等待服务启动
  local ok=false
  for i in 1 2 3 4 5; do
    sleep 1
    if curl -s --connect-timeout 2 "http://127.0.0.1:${COMPANION_PORT}/api/system/info" > /dev/null 2>&1; then
      ok=true
      break
    fi
  done

  if $ok; then
    info "管理面板服务运行正常 ✓"
  else
    warn "服务启动较慢，可能需要几秒钟..."
  fi
}

# ======================== 获取 IP ========================
get_public_ip() {
  curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || \
  curl -s --connect-timeout 5 ip.sb 2>/dev/null || \
  echo ""
}

get_lan_ip() {
  if [ "$OS" = "macos" ]; then
    ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1"
  else
    hostname -I 2>/dev/null | awk '{print $1}' || echo "127.0.0.1"
  fi
}

# ======================== 完成 ========================
finish() {
  local LAN_IP
  LAN_IP=$(get_lan_ip)
  local PUBLIC_IP
  PUBLIC_IP=$(get_public_ip)

  if [ -n "$DEPLOY_TRACK_URL" ]; then
    curl -fsS -X POST "$DEPLOY_TRACK_URL" >/dev/null 2>&1 || true
  fi

  echo ""
  echo -e "${GREEN}${BOLD}"
  echo "  ╔══════════════════════════════════════════╗"
  echo "  ║                                          ║"
  echo "  ║   🎉 Claw伴侣 安装成功！                ║"
  echo "  ║                                          ║"
  echo "  ╚══════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${BOLD}🌐 打开浏览器访问:${NC}"
  echo ""
  echo -e "  本地:   ${CYAN}${BOLD}http://127.0.0.1:${COMPANION_PORT}${NC}"
  echo -e "  局域网: ${CYAN}${BOLD}http://${LAN_IP}:${COMPANION_PORT}${NC}"
  if [ -n "$PUBLIC_IP" ]; then
    echo -e "  公网:   ${CYAN}${BOLD}http://${PUBLIC_IP}:${COMPANION_PORT}${NC}"
  fi
  echo ""
  echo -e "  ${BOLD}📖 OpenClaw 面板 (启动 Gateway 后):${NC}"
  if [ -n "$PUBLIC_IP" ]; then
    echo -e "  ${CYAN}https://${PUBLIC_IP}:18800${NC} (首次需接受自签名证书)"
  fi
  echo ""
  echo -e "  ${BOLD}📖 接下来:${NC}"
  echo -e "  ${CYAN}1.${NC} 在浏览器中配置 AI 模型和 API Key"
  echo -e "  ${CYAN}2.${NC} 添加消息渠道（钉钉、Telegram 等）"
  echo -e "  ${CYAN}3.${NC} 一键启动 Clawdbot"
  echo ""
  echo -e "  ${BOLD}🔧 管理命令:${NC}"
  if [ "$OS" = "macos" ]; then
    echo -e "  停止: ${CYAN}launchctl unload ~/Library/LaunchAgents/com.claw.companion.plist${NC}"
    echo -e "  启动: ${CYAN}launchctl load ~/Library/LaunchAgents/com.claw.companion.plist${NC}"
  elif $IS_ROOT; then
    echo -e "  状态: ${CYAN}systemctl status claw-companion${NC}"
    echo -e "  停止: ${CYAN}systemctl stop claw-companion${NC}"
    echo -e "  重启: ${CYAN}systemctl restart claw-companion${NC}"
    echo -e "  日志: ${CYAN}journalctl -u claw-companion -f${NC}"
  else
    echo -e "  状态: ${CYAN}systemctl --user status claw-companion${NC}"
    echo -e "  停止: ${CYAN}systemctl --user stop claw-companion${NC}"
    echo -e "  启动: ${CYAN}systemctl --user start claw-companion${NC}"
  fi
  echo ""

  if [ "$OS" = "macos" ]; then
    open "http://127.0.0.1:${COMPANION_PORT}" 2>/dev/null || true
  fi
}

# ======================== 主流程 ========================
main() {
  banner
  detect_os
  ensure_curl
  ensure_dbus
  check_node
  fix_npm_permissions
  check_swap
  install_clawdbot
  install_companion
  setup_gateway_service
  setup_nginx_gateway_proxy
  setup_service
  update_site_if_exists
  verify_install
  finish
}

main "$@"
