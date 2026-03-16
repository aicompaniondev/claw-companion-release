# ============================================================
# Claw伴侣 🐾 一键安装脚本 (Windows PowerShell)
# 安装 Clawdbot + Claw伴侣 Web 管理面板
# ============================================================

$ErrorActionPreference = "Stop"
$CompanionPort = if ($env:COMPANION_PORT) { $env:COMPANION_PORT } else { "3210" }
$GatewayPort = if ($env:GATEWAY_PORT) { $env:GATEWAY_PORT } else { "18789" }
$DeployTrackUrl = if ($env:DEPLOY_TRACK_URL) { $env:DEPLOY_TRACK_URL } else { "https://clawcp.top/api/track-deploy" }
$InstallDir = Join-Path $env:USERPROFILE ".openclaw\companion"

function Write-Banner {
    Write-Host ""
    Write-Host "   ██████╗██╗      █████╗ ██╗    ██╗" -ForegroundColor Cyan
    Write-Host "  ██╔════╝██║     ██╔══██╗██║    ██║" -ForegroundColor Cyan
    Write-Host "  ██║     ██║     ███████║██║ █╗ ██║" -ForegroundColor Cyan
    Write-Host "  ██║     ██║     ██╔══██║██║███╗██║" -ForegroundColor Cyan
    Write-Host "  ╚██████╗███████╗██║  ██║╚███╔███╔╝" -ForegroundColor Cyan
    Write-Host "   ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  🐾 Claw伴侣 — Clawdbot 可视化管理面板" -ForegroundColor White
    Write-Host "  一键部署，浏览器管理一切" -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step($msg)  { Write-Host "`n▸ $msg" -ForegroundColor Blue }
function Write-Info($msg)  { Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Warn($msg)  { Write-Host "  ! $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "  ✗ $msg" -ForegroundColor Red }

# ======================== 检测系统 ========================
function Test-System {
    Write-Step "检测系统环境"
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    Write-Info "系统: Windows ($arch)"

    # 检查是否管理员
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Warn "非管理员运行，部分功能可能受限"
    }
}

# ======================== 检查/安装 Node.js ========================
function Install-NodeJs {
    Write-Step "检查 Node.js 环境"

    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        $ver = (node -v) -replace 'v', ''
        $major = [int]($ver.Split('.')[0])
        if ($major -ge 22) {
            Write-Info "Node.js v$ver ✓"
            return
        }
        Write-Warn "Node.js v$ver 版本过低，Clawdbot 需要 >= 22"
    } else {
        Write-Warn "未检测到 Node.js"
    }

    Write-Host "  正在安装 Node.js 22..." -ForegroundColor Yellow

    # 尝试 winget
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        try {
            winget install OpenJS.NodeJS.LTS --version 22 --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            # 刷新 PATH
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

            $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
            if ($nodeCmd) {
                Write-Info "Node.js $(node -v) 已通过 winget 安装"
                return
            }
        } catch {
            Write-Warn "winget 安装失败，尝试手动下载..."
        }
    }

    # 手动下载安装
    $nodeUrl = "https://nodejs.org/dist/v22.12.0/node-v22.12.0-x64.msi"
    if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq "Arm64") {
        $nodeUrl = "https://nodejs.org/dist/v22.12.0/node-v22.12.0-arm64.msi"
    }

    $msiPath = Join-Path $env:TEMP "node-install.msi"
    Write-Host "  下载 Node.js..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $nodeUrl -OutFile $msiPath -UseBasicParsing

    Write-Host "  安装 Node.js (可能需要管理员权限)..." -ForegroundColor Cyan
    Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn" -Wait -NoNewWindow

    # 刷新 PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCmd) {
        Write-Info "Node.js $(node -v) 已安装"
    } else {
        Write-Err "Node.js 安装失败，请手动安装: https://nodejs.org"
        exit 1
    }
}

# ======================== 安装 Clawdbot ========================
function Install-Clawdbot {
    Write-Step "安装 Clawdbot (openclaw-cn)"

    $existing = Get-Command openclaw-cn -ErrorAction SilentlyContinue
    if ($existing) {
        $ver = (openclaw-cn --version 2>$null) ?? "?"
        Write-Info "已安装 Clawdbot ($ver)，正在更新..."
    }

    $env:SHARP_IGNORE_GLOBAL_LIBVIPS = "1"
    npm install -g openclaw-cn@latest 2>&1 | Select-Object -Last 3

    # 刷新 PATH
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    $clawdCmd = Get-Command openclaw-cn -ErrorAction SilentlyContinue
    if ($clawdCmd) {
        Write-Info "Clawdbot $(openclaw-cn --version 2>$null) ✓"
    } else {
        Write-Err "Clawdbot 安装失败"
        Write-Host "  手动安装: npm install -g openclaw-cn@latest" -ForegroundColor Cyan
        exit 1
    }
}

# ======================== 安装 Claw伴侣 ========================
function Install-Companion {
    Write-Step "安装 Claw伴侣 管理面板"

    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

    # 定位源文件
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    $sourceDir = Split-Path -Parent $scriptDir

    if (Test-Path (Join-Path $sourceDir "server\index.js")) {
        # 本地安装
        Copy-Item -Path (Join-Path $sourceDir "server") -Destination $InstallDir -Recurse -Force
        Copy-Item -Path (Join-Path $sourceDir "web") -Destination $InstallDir -Recurse -Force
        Write-Info "文件已复制到 $InstallDir"
    } else {
        Write-Err "远程安装模式暂未实现，请从项目目录运行"
        exit 1
    }

    # 安装依赖
    Push-Location (Join-Path $InstallDir "server")
    npm install --omit=dev 2>&1 | Select-Object -Last 2
    Pop-Location
    Write-Info "依赖安装完成"
}

# ======================== 创建任务计划 ========================
function Setup-Service {
    Write-Step "设置开机自启"

    $taskName = "ClawCompanion"
    $nodePath = (Get-Command node).Source
    $serverPath = Join-Path $InstallDir "server\index.js"

    # 删除旧任务
    schtasks /Delete /TN $taskName /F 2>$null | Out-Null

    # 创建新任务
    $action = New-ScheduledTaskAction -Execute $nodePath -Argument "`"$serverPath`"" -WorkingDirectory (Join-Path $InstallDir "server")
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "Claw伴侣 Web 管理面板" -Force | Out-Null
        Write-Info "Windows 任务计划已创建"
    } catch {
        Write-Warn "任务计划创建失败 (可能需要管理员权限)"
        Write-Host "  你可以手动启动: node `"$serverPath`"" -ForegroundColor Cyan
    }

    # 立即启动
    Write-Host "  启动服务..." -ForegroundColor Cyan
    $env:COMPANION_PORT = $CompanionPort
    Start-Process -FilePath $nodePath -ArgumentList "`"$serverPath`"" -WorkingDirectory (Join-Path $InstallDir "server") -WindowStyle Hidden
    Write-Info "服务已启动"
}

# ======================== 获取局域网 IP ========================
function Get-LanIp {
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" -and $_.PrefixOrigin -eq "Dhcp" } | Select-Object -First 1).IPAddress
    if (-not $ip) {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } | Select-Object -First 1).IPAddress
    }
    return $ip ?? "127.0.0.1"
}

# ======================== 完成 ========================
function Show-Finish {
    $lanIp = Get-LanIp

    Start-Sleep -Seconds 2

    try {
        if ($DeployTrackUrl) {
            Invoke-WebRequest -Uri $DeployTrackUrl -Method Post -UseBasicParsing | Out-Null
        }
    } catch {}

    Write-Host ""
    Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                                          ║" -ForegroundColor Green
    Write-Host "  ║   🎉 Claw伴侣 安装成功！                ║" -ForegroundColor Green
    Write-Host "  ║                                          ║" -ForegroundColor Green
    Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "  🌐 打开浏览器访问:" -ForegroundColor White
    Write-Host ""
    Write-Host "  本地:   http://127.0.0.1:$CompanionPort" -ForegroundColor Cyan
    Write-Host "  局域网: http://${lanIp}:$CompanionPort" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  📖 接下来:" -ForegroundColor White
    Write-Host "  1. 在浏览器中配置 AI 模型和 API Key" -ForegroundColor Cyan
    Write-Host "  2. 添加消息渠道（钉钉、Telegram 等）" -ForegroundColor Cyan
    Write-Host "  3. 一键启动 Clawdbot" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  🔧 管理:" -ForegroundColor White
    Write-Host "  停止: schtasks /End /TN ClawCompanion" -ForegroundColor Cyan
    Write-Host "  启动: schtasks /Run /TN ClawCompanion" -ForegroundColor Cyan
    Write-Host ""

    # 自动打开浏览器
    Start-Process "http://127.0.0.1:$CompanionPort"
}

# ======================== 主流程 ========================
Write-Banner
Test-System
Install-NodeJs
Install-Clawdbot
Install-Companion
Setup-Service
Show-Finish
