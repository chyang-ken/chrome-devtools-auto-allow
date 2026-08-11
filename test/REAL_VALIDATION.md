# Chromium 浏览器家族验证记录

日期：2026-07-24
平台：macOS
验证分支：`on-demand-deploy`

## 本机浏览器清单

| 浏览器 | 安装状态 | 版本 | 本轮真实运行 |
|---|---|---|---|
| Google Chrome Stable | 已安装 | 150.0.7871.182 | 通过 |
| Google Chrome Beta | 已安装 | 151.0.7922.47 | 通过 |
| Google Chrome Dev / Canary | 未安装 | — | 仅自动测试 |
| Chromium | 未安装 | — | 仅自动测试 |
| Microsoft Edge 各通道 | 未安装 | — | 仅自动测试 |

所有真实连接都使用 `/private/tmp` 下新建的隔离 `user-data-dir`；验证完成后关闭测试进程，
测试目录已移入废纸篓。没有连接或改动日常浏览器 Profile。

## 自动测试

执行：

```bash
node --test scripts/*.test.mjs
```

覆盖：

- Chrome Stable / Beta / Dev / Canary、Chromium、Edge 各通道的进程识别；
- 默认数据目录、自定义 `user-data-dir`、随机端口文件、显式固定端口；
- 缺失、异常、过期端口文件和非浏览器自有监听端口；
- 多浏览器、多端口独立基线；
- 既有连接不算本次新增；
- 新连接存在时续命，连接消失后停止续命；
- 未知工具进入真实连接探测，纯查看命令不打开看守；
- 旧 Codex matcher 迁移、备份、幂等和异常配置手工说明。

结果：14 个测试全部通过。

## 本轮真实运行

### Chrome Stable

- 使用隔离临时目录和随机调试端口启动。
- 浏览器发现器正确识别为 `chrome`，并确认端口由该浏览器主进程监听。
- 运行不含 `web-access`、`3456`、`remote-debugging` 等关键词的
  `test/hold-session.mjs`。
- WebSocket 会话完成 `Browser.getVersion`，返回 `Chrome/150.0.7871.182`。
- 触发日志记录该 Chrome 端口的新连接；连接关闭后看守自动回到 `stopped`。

### Chrome Beta

- 使用另一隔离临时目录和另一随机调试端口启动。
- 浏览器发现器正确识别为 `chrome-beta`。
- 同一无关键词客户端完成连接，返回 `Chrome/151.0.7922.47`。
- 触发日志只把本次新增连接记到 Beta 目标，没有混入 Stable。

### 两个浏览器同时连接

- `test/hold-multiple-sessions.mjs` 同时连接 Stable 与 Beta。
- 两个会话都完成 `Browser.getVersion` 后正常关闭。
- 同一条 `PROBE-HIT` 记录分别包含 Stable 与 Beta 的新增连接，进程、端口和基线相互隔离。

### 快速退出与并发安全

- 另启一个没有调试端口的隔离 Beta 实例；指定该 PID 探测时无输出，`real 0.09s` 返回。
- 8 次并发 `watch 30` 后精确检查进程，只存在 1 个 `cdp-auto-allow.scpt` 看守；测试后立即停止。
- `echo web-access` 前后触发日志行数不变，看守保持 `stopped`，证明纯文本提及关键词不会误点火。

## 2026-07-24 稳定版的 PWA 与弹框点击证据

以下结论只描述当时的 `on-demand-deploy` 稳定版，不代表后续 Chrome 151 候选版没有修改点击层：

- 当前真实运行日志仍能看到 `app_mode_loader`，说明已安装 PWA 仍在扫描范围。
- PWA 的真实端到端点击已由提交 `cd3d85b` 在 ChatGPT PWA 上验证：
  `hook → watch → 找到 app_mode_loader → 三重校验 → 2.1 秒内点击授权`。
- 后续提交 `97a4a5a` 只增加见框续命，没有移除 PWA 扫描逻辑。

为了不连接或干扰日常 Chrome Profile，本轮没有重新制造一次 PWA 授权弹框。因此这里的
PWA 结论只是 2026-07-24 的历史基线；Chrome 151 候选版修改了弹框识别与点击逻辑，不能再以
“点击层未改动”为由继承该结论，必须单独验证。

## 当前安装状态核对

- Claude Code matcher：`Bash`
- Codex matcher：`Bash|exec_command|functions\.exec_command`
- 两个配置均保持原样，本轮未运行安装器、未重新登记 hook。
- 没有安装或加载 LaunchAgent；空闲时看守为 `stopped`。

---

# Chrome 151 候选版验证记录

日期：2026-08-11

平台：macOS

验证分支：`auria/chrome-151-dialog-safety`

稳定基线：`c8e1c1b`（`stable-2026-08-11-pre-chrome-151`）

## 审查意见对应修复

Chrome 151 的授权文案存在两种可确认结构：

- `remote debugging` 及其本地化文本可以独立确认；
- 通用文案必须同时出现 `external app` 与 `full control`，任意一个单独出现都失败关闭。

候选版只在同时满足“Allow 按钮 + Cancel 按钮 + 上述完整文案结构”时点击。窗口尺寸、
`AXUnknown` 类型、单独的 `external app` 或单独的 `full control` 都不能授权。

## 自动检查原始结果

```text
node --test scripts/*.test.mjs
# tests 14
# pass 14
# fail 0

bash -n scripts/*.sh
PASS

osacompile -o /tmp/cdp-auto-allow-review-fix.scpt scripts/cdp-auto-allow.scpt
PASS

git diff --check
PASS
```

结构化文案判定通过已编译 AppleScript 的纯逻辑调用验证：

```text
direct=true externalOnly=false fullControlOnly=false paired=true localized=true
```

其中预期失败样例 `externalOnly` 与 `fullControlOnly` 都返回 `false`；这两个样例用于确认
审查指出的“任意单词独立放行”问题已被关闭。

当前脚本的静态检查未发现 `activate`、`frontmost`、Return、`key code` 或
`approveViaKeystroke`，没有激活浏览器或模拟回车的路径。

## Chrome 151 真实连接与点击

使用日常 Chrome 151 的 `DevToolsActivePort` 浏览器级 WebSocket，仅调用
`Browser.getVersion`，不导航、不读取页面或标签内容。客户端原始输出：

```text
DIRECT_OPEN
DIRECT_READY Chrome/151.0.7922.76
DIRECT_CLOSED
```

同一轮看守的原始日志：

```text
02:00:19 pid=54148 window=1 sheets=1
02:00:24 consent container seen: allowBtn=true cancel=true directDebug=true externalApp=false fullControl=false confirmedText=true recursive=true
02:00:24 Approved remote-debugging consent sheet (Google Chrome)
```

这证明当前修复后的结构化判定识别到真实 `remote debugging` 文案，随后点击 Allow，客户端
完成握手并正常关闭。

## 焦点与失败关闭证据

在结构化文案修复前、但已经删除 `activate` / 回车路径的同一 Chrome 151 候选版上，真实连接
期间连续采样得到：

```text
FOCUS_STABLE:Google Chrome:59630
```

本次审查修复仅把文案判定从“任一词命中”收紧为“直接词或成对通用词”，没有改动窗口扫描、
应用激活或点击方式。修复后再次连接时系统报告当前前台应用为 `NULL`，因此没有把空采样伪报为
新的焦点通过证据；当前版本的“无激活路径”由上述既有真实采样与静态检查共同支撑。

真实小型 `AXUnknown` 非授权窗口曾被扫描到，因缺少按钮和授权文案而忽略：

```text
Google Chrome AXUnknown window size=375x234
consent container seen: allowBtn=false cancel=false debugText=false recursive=true
Ignoring unconfirmed AXUnknown dialog (Google Chrome)
```

结构化修复后的两个预期失败样例进一步证明：即使有 `external app` 或 `full control` 中的一个，
也不会确认授权。

## 当前停点与待独立复核

- 修复后的候选脚本已安装到本地运行目录，本地与工作树文件内容一致。
- 真实连接已关闭；Auto Allow 看守为 `stopped`，空闲时安全防线已恢复。
- Chrome 150 当前版本兼容性需由 Ken 在其环境独立复测。
- 当前候选版的 PWA 点击路径仍需独立复测，不能沿用 2026-07-24 的稳定版结论。
- 合并时应 squash，避免早期不安全候选提交进入正式分支历史。
