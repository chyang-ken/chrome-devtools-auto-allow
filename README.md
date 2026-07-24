# Chrome CDP Auto Allow（连接感知 / hook 按需版）

macOS 小工具：当 agent（Claude Code / Codex）连接本机**已在运行的** Chrome 做远程调试时，
Chrome 弹的「允许远程调试 / An external app wants full control」确认框会被自动点掉「允许」——
让 agent 的浏览器任务不被卡住，又**不**把 Chrome 这道确认防线 7×24 永久拆掉。

> 一图看懂整条链路：用浏览器打开 [`ARCHITECTURE.html`](ARCHITECTURE.html)。

## 它解决什么

Chrome 148+ 起，每次有外部程序连接「已经在运行的」Chrome 做 CDP / 远程调试，都会弹一个
确认框要人手点「允许」。agent 的抓取脚本、web-access、Playwright、`chrome-devtools-mcp`
连你日常 Chrome 时都会撞上它，无人值守时就卡住。

## 核心设计：盯连接，不猜命令

agent 连 Chrome 的脚本是**动态生成**的，语言 / 库 / 端口 / 写法无穷，靠「猜命令长什么样」
永远枚举不全。唯一躲不掉的物理事实是——**连 Chrome 必然建立一条到调试端口的 TCP 连接**。
所以本工具的触发是「盯连接」：

| 组件 | 角色 |
|---|---|
| `scripts/agent-hook.sh` | **触发层**。注册成 agent 的 PreToolUse（每次跑命令前）hook。命令「会跑程序」就后台起连接探测器；纯文本命令（`ls`/`git`）秒放过。 |
| `scripts/conn-arm.sh` | **连接探测**。盯 Chrome 调试端口「基线外新增的外部连接」（= 这条命令亲手发起的那条），有就开看守、连接消失即收。窗口贴合「真连 Chrome 的那几秒」，不敞开整个 agent 活跃期。 |
| `scripts/on-demand.sh` | **看守开关**。`watch N` = 开 N 秒看守（到点自杀）；`stop` / `status`。按需、非常驻。 |
| `scripts/cdp-auto-allow.scpt` | **执行层**（AppleScript）。每 0.4s 扫一次，**只**对「远程调试授权框」（三重校验：有 Allow 按钮 + 有 Cancel + 文字含 debug/remote）点「允许」，别的框一概不碰。 |

一条龙：`你让 agent 跑命令 → PreToolUse 触发 agent-hook → conn-arm 探测到端口新连接 →
on-demand 开看守 → scpt 扫到框点「允许」→ 连接结束看守自杀`。

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
3. **窗口贴合实际连接** —— 只在「真有命令在连 Chrome 的那几秒」活，不敞开整个 agent 活跃期。

### 为什么不用常驻 LaunchAgent

最初的实现用 KeepAlive 的 LaunchAgent 让 scpt 7×24 常驻——等于对所有 Chrome 永久关掉
「每次确认」这道防线。本版改为 PreToolUse hook 按需点火，把风险窗口收缩到「实际在连
Chrome 的那几秒」。`launchd/` 里的 plist 仅作「无 agent 的常驻兜底」保留，**默认不装、不推荐**。

### 与 upstream 的关系

本 fork 与 upstream `liaocaoxuezhe/chrome-devtools-auto-allow` 已进入**选择性吸收**关系，
不再把 upstream 的整分支更新视为必须同步的新版。

- **分叉原因**：upstream 选择常驻 LaunchAgent，以全天候自动处理授权换取权限稳定；
  本 fork 选择连接感知、按需启停，只在 Agent 真实连接 Chrome 的几秒内处理弹窗。
- **同步策略**：保留 upstream 作为项目来历及安全、浏览器兼容性、弹窗识别修复的参考；
  不整体 merge，只在确认不破坏按需安全边界后手工吸收适用部分。
- **重新合流条件**：upstream 提供等价的按需模式，并且默认不安装或启动常驻服务。

## 依赖

macOS；`node`（注册 hook 用）、`lsof`（连接探测用）、`/usr/bin/osascript`（点框用，需 Accessibility 权限）。

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
  conn-arm.sh          连接探测（盯调试端口新连接）
  on-demand.sh         看守开关（watch / stop / status）
  cdp-auto-allow.scpt  执行层（扫框点「允许」，三重校验）
  register-hooks.mjs   幂等注册 / 反注册 hook 到 agent 配置
  install.sh / uninstall.sh / doctor.sh
launchd/               可选的常驻兜底 plist（默认不用）
ARCHITECTURE.html      架构总览图（浏览器打开）
```
