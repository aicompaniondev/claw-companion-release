#!/bin/bash
# ============================================================
# Claw伴侣 远程部署脚本（基于 GitHub Release，无需 git 源码）
# 用法: ssh root@YOUR_VPS 'bash -s' < deploy.sh
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()  { echo -e "  ${GREEN}✓${NC} $1"; }
step()  { echo -e "\n${CYAN}${BOLD}▸ $1${NC}"; }
error() { echo -e "  ${RED}✗${NC} $1"; exit 1; }

# Canonical install dir
INSTALL_DIR="${INSTALL_DIR:-/opt/claw-companion}"
COMPANION_PORT="${COMPANION_PORT:-3210}"

echo ""
echo -e "${CYAN}${BOLD}  🐾 Claw伴侣 — 远程部署${NC}"
echo ""

# ======== 1. 停止旧服务 ========
step "停止旧服务"
systemctl stop claw-companion.service 2>/dev/null || true
pkill -f "node.*companion.*index.js" 2>/dev/null || true
sleep 1

# ======== 2. 检查/安装 Node.js ========
step "检查 Node.js"
if command -v node &>/dev/null; then
  NODE_VER=$(node -v | sed 's/v//' | cut -d. -f1)
  if [ "$NODE_VER" -ge 18 ]; then
    info "Node.js $(node -v) ✓"
  else
    info "Node.js 版本过低，正在升级..."
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
    apt-get install -y nodejs >/dev/null 2>&1
    info "Node.js $(node -v) 已安装"
  fi
else
  info "未检测到 Node.js，正在安装..."
  if command -v apt-get &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
    apt-get install -y nodejs >/dev/null 2>&1
  elif command -v dnf &>/dev/null; then
    curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
    dnf install -y nodejs >/dev/null 2>&1
  elif command -v yum &>/dev/null; then
    curl -fsSL https://rpm.nodesource.com/setup_22.x | bash - >/dev/null 2>&1
    yum install -y nodejs >/dev/null 2>&1
  else
    error "无法自动安装 Node.js"
  fi
  info "Node.js $(node -v) 已安装"
fi

# Ensure curl/tar
command -v curl &>/dev/null || (apt-get install -y curl >/dev/null 2>&1)
command -v tar &>/dev/null || (apt-get install -y tar >/dev/null 2>&1)

# ======== 3. 下载并安装最新 Release ========
step "安装最新 Release"
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR"

curl -fsSL "https://raw.githubusercontent.com/aicompaniondev/claw-companion-release/main/scripts/release-update.sh" -o release-update.sh
chmod +x release-update.sh
INSTALL_DIR="$INSTALL_DIR" bash ./release-update.sh
info "已安装到 $INSTALL_DIR"

# ======== 4. 设置 systemd 服务 ========
step "配置 systemd 服务"
NODE_PATH=$(which node)

cat > /etc/systemd/system/claw-companion.service <<EOF
[Unit]
Description=Claw伴侣 - OpenClaw Web 管理面板
After=network.target

[Service]
Type=simple
ExecStart=${NODE_PATH} ${INSTALL_DIR}/server/index.js
WorkingDirectory=${INSTALL_DIR}/server
Environment=COMPANION_PORT=${COMPANION_PORT}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable claw-companion.service
systemctl restart claw-companion.service
info "systemd 服务已创建并启动"

# ======== 5. 验证 ========
step "验证部署"
sleep 2

if systemctl is-active --quiet claw-companion.service; then
  info "服务状态: 运行中 ✓"
else
  error "服务启动失败，请检查: journalctl -u claw-companion -n 30"
fi

PUBLIC_IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || curl -s --connect-timeout 5 ip.sb 2>/dev/null || echo "你的服务器IP")

echo ""
echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════════╗"
echo -e "  ║                                          ║"
echo -e "  ║   🎉 Claw伴侣 部署成功！                ║"
echo -e "  ║                                          ║"
echo -e "  ╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}🌐 访问地址:${NC}"
echo -e "     ${CYAN}http://${PUBLIC_IP}:${COMPANION_PORT}${NC}"
echo ""
echo -e "  ${BOLD}🔧 管理命令:${NC}"
echo -e "     状态: ${CYAN}systemctl status claw-companion${NC}"
echo -e "     停止: ${CYAN}systemctl stop claw-companion${NC}"
echo -e "     重启: ${CYAN}systemctl restart claw-companion${NC}"
echo -e "     日志: ${CYAN}journalctl -u claw-companion -f${NC}"
echo ""
