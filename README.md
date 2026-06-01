# Chrome CDP Auto Allow

一个用于 macOS 的小工具：自动点击 Chrome DevTools Protocol 远程调试确认弹窗里的 `允许`。

当 Codex、Claude Code、Playwright、`chrome-devtools-mcp` 等工具通过 CDP 连接 Chrome 时，Chrome 可能会弹出类似这样的确认框：

```text
Allow remote debugging?
要允许远程调试吗？
```

这个项目会在本机后台监听 Chrome 的 macOS Accessibility UI 树，识别到 Chrome DevTools、CDP、MCP 或远程调试相关弹窗后，自动点击 `Allow` / `允许`。

## 适用场景

- Codex 或 Claude Code 需要通过 Chrome CDP 自动化浏览器。
- `chrome-devtools-mcp` 每次连接 Chrome 都弹确认框。
- Mac mini、远程 Mac、无人值守机器上没有人手动点确认。
- 你明确接受在自己电脑上自动批准 Chrome 远程调试连接的风险。

## 原理

这个工具不修改 Chrome，也不破解 Chrome 的安全机制。

它做的事情很简单：

1. `scripts/cdp-auto-allow.scpt` 作为一个 AppleScript 循环运行。
2. 通过 macOS `System Events` 读取 Chrome 的 Accessibility UI 树。
3. 扫描 `Google Chrome`、`Google Chrome Canary` 和 `Chromium` 的窗口。
4. 如果窗口文本里出现 `remote debugging`、`DevTools`、`CDP`、`MCP`、`远程调试` 等关键词，就认为这是目标弹窗。
5. 递归查找按钮，匹配 `Allow`、`允许`、`允許`、`OK`、`确定` 等按钮文本。
6. 找到后调用 macOS Accessibility 的点击动作。

安装脚本会把 AppleScript 编译成 `CDP Auto Allow.app`，给它设置固定 Bundle ID，并注册成当前用户的 LaunchAgent。

## 安装

```bash
chmod +x scripts/install.sh scripts/uninstall.sh
./scripts/install.sh
```

安装后需要授予 Accessibility 权限：

1. 打开 `System Settings`。
2. 进入 `Privacy & Security > Accessibility`。
3. 添加或启用 `CDP Auto Allow.app`。
4. 如果列表里没有出现，点击 `+`，选择项目目录里生成的 `CDP Auto Allow.app`。

安装脚本会打印准确的 app 路径。

## 验证

查看 LaunchAgent 是否运行：

```bash
launchctl list com.local.cdp-auto-allow
```

查看日志：

```bash
tail -f /tmp/cdp-auto-allow.out.log /tmp/cdp-auto-allow.err.log
```

手动 dry-run：

```bash
osascript scripts/cdp-auto-allow.scpt --dry-run
```

如果此时 Chrome 正显示远程调试确认弹窗，日志里应该能看到匹配提示，但 dry-run 不会真正点击。

## 卸载

```bash
./scripts/uninstall.sh
```

你也可以在 `Privacy & Security > Accessibility` 里移除 `CDP Auto Allow.app`。

## 自定义匹配词

如果你的 Chrome 语言不是英文或中文，弹窗文字可能不同。

可以修改 [scripts/cdp-auto-allow.scpt](scripts/cdp-auto-allow.scpt) 里的两个列表：

```applescript
property allowButtonNames : {"Allow", "允许", "允許", "OK", "Ok", "确定", "確認", "好"}
property requiredTerms : {"debug", "DevTools", "Developer Tools", "remote debugging", "CDP", "chrome-devtools", "MCP", "远程调试"}
```

修改后重新运行：

```bash
./scripts/install.sh
```

## 安全说明

这个工具有明确的安全风险，请只在你信任的本机环境使用：

- Accessibility 权限允许它读取并点击本机 UI。
- CDP 连接可以控制浏览器页面、读取页面状态，能力很强。
- 不建议在包含敏感登录态的日常 Chrome Profile 上无脑开启。
- 建议把 CDP endpoint 绑定到 `127.0.0.1`。
- 更安全的做法是使用专门的自动化 Chrome Profile，而不是日常浏览器 Profile。

如果你希望更保守，可以不要安装常驻服务，只在需要时手动运行：

```bash
osascript scripts/cdp-auto-allow.scpt
```

## 项目结构

```text
.
├── launchd/
│   └── com.local.cdp-auto-allow.plist
├── scripts/
│   ├── cdp-auto-allow.scpt
│   ├── install.sh
│   └── uninstall.sh
├── LICENSE
└── README.md
```

## License

MIT
