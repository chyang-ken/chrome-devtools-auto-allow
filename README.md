# Chromium CDP Auto Allow（macOS / 连接感知 / hook 按需版）

macOS 小工具：当 agent（Claude Code / Codex）连接本机**已在运行的 Chromium 浏览器家族**
做远程调试时，浏览器弹出的「允许远程调试 / An external app wants full control」确认框会被
自动点掉「允许」——让 agent 的浏览器任务不被卡住，又**不**把这道确认防线 7×24 永久拆掉。

代码覆盖 Google Chrome（Stable / Beta / Dev / Canary）、Chromium、Microsoft Edge
（Stable / Beta / Dev / Canary），也支持它们通过绝对路径指定的自定义 `user-data-dir`。
这是 **macOS 专用工具**，不是跨系统的 Universal 工具。

> 一图看懂整条链路：用浏览器打开 [`ARCHITECTURE.html`](ARCHITECTURE.html)。

## 它解决什么

新版 Chromium 浏览器在外部程序连接「已经在运行的浏览器」做 CDP / 远程调试时，可能弹出
确认框要求人手点「允许」。agent 的抓取脚本、浏览器工具和 CDP 客户端都会撞上它，无人值守
时就卡住。

## 核心设计：盯连接，不猜命令

agent 连接浏览器的脚本是**动态生成**的，语言 / 库 / 端口 / 写法无穷，靠「猜命令长什么样」
永远枚举不全。唯一躲不掉的物理事实是——**真实连接必然出现在浏览器自己的调试端口上**。
所以命令特征只用于抢先点火，最终判断来自真实连接：

| 组件 | 角色 |
|---|---|
| `scripts/agent-hook.sh` | **触发层**。明确含连接特征的执行命令走快速路径；其他未知工具进入真实连接探测；确定不会连接浏览器的查看类命令（`ls` / `git` / `echo` 等）秒放过。 |
| `scripts/browser-targets.mjs` | **浏览器发现**。只读取当前运行的受支持浏览器进程，从它的默认或自定义数据目录、启动参数取得候选端口，并确认该端口确实由该浏览器监听。 |
| `scripts/conn-arm.mjs` | **连接探测**。同时盯所有有效浏览器端口，各自保存连接前基线；只把基线外新增的外部连接视为本次连接。既有连接不会误报，多个浏览器不会串线。 |
| `scripts/on-demand.sh` | **看守开关**。`watch N` = 开 N 秒看守（到点自杀）；`stop` / `status`。按需、非常驻。 |
| `scripts/cdp-auto-allow.scpt` | **执行层**（AppleScript）。每 0.4s 扫一次，**只**对「远程调试授权框」（三重校验：有 Allow 按钮 + 有 Cancel + 文字含 debug/remote）点「允许」，别的框一概不碰。 |

一条龙：`你让 agent 跑命令 → PreToolUse 触发 agent-hook → conn-arm 探测到端口新连接 →
on-demand 开看守 → scpt 扫到框点「允许」→ 连接结束看守自杀`。

### 端口发现的边界

- 不扫描本机所有端口，只处理**受支持浏览器进程自己声明**的端口。
- 端口文件缺失、过期、格式错误，或端口并非由对应浏览器监听时，一律忽略。
- 多个浏览器、多个自定义数据目录可以同时存在；基线按浏览器进程和端口隔离。
- `web-access`、`3456` 等命令特征只是快速路径，不是正确性的前提，也不构成运行时绑定。

## 安装

```bash
./scripts/install.sh
```

它会**幂等**地：

1. 把 `agent-hook.sh` 注册成两个 agent 的 PreToolUse hook：
   - **Claude Code** → `~/.claude/settings.json`（matcher `Bash`）
   - **Codex** → `~/.codex/hooks.json`（matcher `Bash|exec_command|functions\.exec_command`）
2. 提示你给 `/usr/bin/osascript` 授予 **Accessibility 权限**（scpt 点框需要，只此一次）。

> 若自动改不动你的 agent 配置（例如配置是含注释的 JSONC），install 会打印「请手动加这一项」
> 的明确指引，绝不强改；改动前都会备份成 `*.bak.auto-allow`。

装完自检：

```bash
./scripts/doctor.sh
```

## 卸载

```bash
./scripts/uninstall.sh   # 从两个 agent 配置移除 hook + 清掉旧 LaunchAgent + 停看守
```

## 安全：为什么这不算「拆防线」

三条闸，任何情况都不破：

1. **按需启动、到点自杀** —— 不是 7×24 常驻；
2. **只点远程调试框**（scpt 三重校验）—— 你别的敏感弹框（付款 / 删除确认）永不触碰；
3. **窗口贴合实际连接** —— 只在「真有命令在连受支持浏览器的那几秒」活，不敞开整个 agent 活跃期。

### 为什么不用常驻 LaunchAgent

最初的实现用 KeepAlive 的 LaunchAgent 让 scpt 7×24 常驻——等于对所有浏览器永久关掉
「每次确认」这道防线。本版改为 PreToolUse hook 按需点火，把风险窗口收缩到「实际在连
浏览器的那几秒」。`launchd/` 里的 plist 仅作「无 agent 的常驻兜底」保留，**默认不装、不推荐**。

### 与 upstream 的关系

本 fork 与 upstream `liaocaoxuezhe/chrome-devtools-auto-allow` 已进入**选择性吸收**关系，
不再把 upstream 的整分支更新视为必须同步的新版。

- **分叉原因**：upstream 选择常驻 LaunchAgent，以全天候自动处理授权换取权限稳定；
  本 fork 选择连接感知、按需启停，只在 Agent 真实连接受支持浏览器的几秒内处理弹窗。
- **同步策略**：保留 upstream 作为项目来历及安全、浏览器兼容性、弹窗识别修复的参考；
  不整体 merge，只在确认不破坏按需安全边界后手工吸收适用部分。
- **重新合流条件**：upstream 提供等价的按需模式，并且默认不安装或启动常驻服务。

## 依赖

macOS；`node`（注册 hook 用）、`lsof`（连接探测用）、`/usr/bin/osascript`（点框用，需 Accessibility 权限）。

## 支持与验证范围

| 范围 | 代码支持 | 本机真实验证（2026-07-24） |
|---|---|---|
| Google Chrome Stable | 是 | 通过（150.0.7871.182） |
| Google Chrome Beta | 是 | 通过（151.0.7922.47） |
| Google Chrome Dev / Canary | 是 | 未安装，仅自动测试覆盖 |
| Chromium | 是 | 未安装，仅自动测试覆盖 |
| Microsoft Edge Stable / Beta / Dev / Canary | 是 | 未安装，仅自动测试覆盖 |
| 自定义 `user-data-dir` | 是 | Stable 与 Beta 均以隔离临时目录通过 |
| Chrome / Edge PWA 授权框扫描 | 是 | 既有真实运行日志确认 PWA 进程仍在扫描范围；本次没有重新制造日常 Profile 的弹框 |

可复核的测试矩阵与本机记录见 [`test/REAL_VALIDATION.md`](test/REAL_VALIDATION.md)。

本工具只负责远程调试授权框；不负责浏览器账号、Profile 路由或网页操作本身。

## 故障排查

- `./scripts/doctor.sh` —— 一键自检（hook 注册 / 依赖 / 权限 / 看守状态 / 日志）。
- 日志：
  - `/tmp/cdp-auto-allow.hook.log` —— 哪些命令 arm 了
  - `/tmp/cdp-auto-allow.probe.log` —— 探测器启动
  - `/tmp/cdp-auto-allow.debug.log` —— scpt 扫到 / 点了哪些框

## 文件结构

```
scripts/
  agent-hook.sh        触发层（PreToolUse hook，注册到两个 agent）
  hook-decision.mjs    区分快速路径、真实连接探测和纯查看命令
  browser-targets.mjs  发现受支持浏览器的真实调试端口
  conn-arm.sh          兼容入口
  conn-arm.mjs         多浏览器、多端口连接探测
  on-demand.sh         看守开关（watch / stop / status）
  cdp-auto-allow.scpt  执行层（扫框点「允许」，三重校验）
  register-hooks.mjs   幂等注册 / 反注册 hook 到 agent 配置
  install.sh / uninstall.sh / doctor.sh
launchd/               可选的常驻兜底 plist（默认不用）
ARCHITECTURE.html      架构总览图（浏览器打开）
```
