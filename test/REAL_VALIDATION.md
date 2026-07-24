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

## PWA 与弹框点击证据

本轮改动没有修改 `cdp-auto-allow.scpt` 的进程枚举、按钮识别或三重校验：

- 当前真实运行日志仍能看到 `app_mode_loader`，说明已安装 PWA 仍在扫描范围。
- PWA 的真实端到端点击已由提交 `cd3d85b` 在 ChatGPT PWA 上验证：
  `hook → watch → 找到 app_mode_loader → 三重校验 → 2.1 秒内点击授权`。
- 后续提交 `97a4a5a` 只增加见框续命，没有移除 PWA 扫描逻辑。

为了不连接或干扰日常 Chrome Profile，本轮没有重新制造一次 PWA 授权弹框。因此 PWA 的
结论是“既有真实证据仍适用于未改动的点击层”，不是本轮新建隔离 Profile 的独立复测。

## 当前安装状态核对

- Claude Code matcher：`Bash`
- Codex matcher：`Bash|exec_command|functions\.exec_command`
- 两个配置均保持原样，本轮未运行安装器、未重新登记 hook。
- 没有安装或加载 LaunchAgent；空闲时看守为 `stopped`。
