# Claw 伴侣（Claw Companion）

**Claw 伴侣**是为 OpenClaw 打造的可视化管理面板，目标是让你**不用记命令行**也能把一个 AI 助手稳定跑在自己的机器或云服务器上。

---

## 功能一览

### 1. 一站式可视化管理面板

- 深色科技风 Web UI，开箱即用
- 所有核心能力都通过页面完成，无需手动改配置文件：
  - 模型配置
  - 渠道接入
  - 服务管理
  - 日志查看

适合：
- 不熟悉命令行的同学
- 想给团队成员一个“可点点点”的管理入口

---

### 2. 模型管理（Model Management）

- 支持任何 **OpenAI 兼容 API**：
  - OpenAI / Azure OpenAI
  - Anthropic Claude
  - DeepSeek
  - Google Gemini
  - Grok
  - 以及其他兼容的第三方服务
- 可视化配置：
  - API Key / Base URL
  - 模型名称（如 `gpt-4.1`、`claude-3.7`、`deepseek-chat` 等）
  - 超时时间、重试策略等（视实际实现）

特点：
- 随时切换默认模型，无需重启服务
- 可以按渠道或场景选择不同模型（例如：工作群用稳一点的模型，个人对话用便宜大 token 的模型）

---

### 3. 渠道接入（Channel Integration）

在一个面板里管理多种聊天渠道，让同一个 AI 助手出现在不同平台：

已支持/规划支持的渠道包括（视实际实现为准）：

- 🟦 钉钉（DingTalk）
- ✈️ Telegram
- 🎮 Discord
- 💼 Slack
- 💚 微信
- 📱 WhatsApp
- 🔒 Signal
- 🐦 飞书（Lark）

在面板中你可以：

- 为每个渠道配置：
  - Bot Token / App ID / Secret 等凭据
  - Webhook / 回调地址
- 为不同渠道指定不同：
  - 默认模型
  - 回复风格 / 上下文策略（视实现）

---

### 4. 服务管控（Service Control）

- 通过 Web 页面管理后台服务的生命周期（视底层 OpenClaw 集成情况）：
  - 启动 / 停止 / 重启服务
  - 查看健康状态
- 查看运行日志：
  - 最近错误
  - 关键事件
  - 调试信息

用途：
- 出问题时不用上服务器查日志，可以先在面板里快速确认大致状况
- 对不熟悉 Linux 的用户更友好

---

### 5. 配置与状态可视化

- 可视化查看当前配置：
  - 哪些模型已启用
  - 哪些渠道在线
  - 服务当前状态（运行中 / 已停止）
- 某些配置支持在线修改：
  - 例如更新某个渠道的 Token、关闭某个渠道入口等

好处：
- 不用在多个 `.env` / `yaml` 文件之间来回切换
- 对团队协作透明：非开发同事也能看懂和操作

---

### 6. 一键安装 / 一键更新（配套脚本）

虽然这部分通过脚本实现，但本质上是为“更好用的面板”服务：

- 一键安装脚本：
  - 自动部署 Claw 伴侣到推荐目录
  - 配置 systemd 开机自启
- 一键更新脚本：
  - 从 GitHub Release 拉取最新版本
  - 安全替换现有版本后重启服务

对用户来说：
- **首装**：打一条命令 + 浏览器打开面板 → 配置完就能用  
- **升级**：打一条命令 → 面板和服务在后台完成自更新

---

## 安装（推荐：Release 包，无需源码/无需 git）

**推荐安装目录：`/opt/claw-companion`**

```bash
ssh root@YOUR_VPS 'bash -s' < deploy.sh
```

自定义端口：

```bash
COMPANION_PORT=3210 ssh root@YOUR_VPS 'bash -s' < deploy.sh
```

> 旧版可能安装在 `/root/.openclaw/companion`。更新时会自动识别并尽量迁移到 `/opt/claw-companion`（或保持原目录）。

---

## 更新

在管理面板内：**系统 → 检查更新 / 更新 Claw 伴侣**（优先 GitHub Release 更新）。

命令行更新方式：

```bash
curl -fsSL https://raw.githubusercontent.com/aicompaniondev/claw-companion-release/main/scripts/release-update.sh | bash
```

---

## 发布（维护者）

1. 修改 `server/package.json` 的 version（例如 `1.0.1`）
2. 打 tag 并 push：

```bash
git tag v1.0.1
git push origin v1.0.1
```

GitHub Actions 会生成：
- `claw-companion-vX.Y.Z.tar.gz`
- `claw-companion-vX.Y.Z.tar.gz.sha256`

并上传到 GitHub Release。
