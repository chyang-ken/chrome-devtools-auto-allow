use scripting additions

-- 授权框是挂在某个窗口上的 sheet，带 Allow + Cancel 两个按钮，文字含 "remote debugging /
-- wants full control" 之类。本脚本只找这种 sheet 并点 Allow，不读整页文字、不整树递归
-- （旧实现对每个普通窗口递归整棵辅助功能树，在 Google Ads/Gmail 等重页面上会卡死几十秒）。
property allowButtonNames : {"Allow", "允许", "允許", "OK", "Ok", "确定", "確認", "好"}
property cancelButtonNames : {"Cancel", "取消", "取消", "Don't allow", "Deny"}
property debugTerms : {"debug", "remote", "full control", "远程", "遠端", "调试", "調試"}
property debugLogPath : "/tmp/cdp-auto-allow.debug.log"
property deadlinePath : "/tmp/cdp-auto-allow.deadline"
property procsLogged : false
-- 每点掉一个真实授权框就把 watch 截止时间往后推这么多秒。
-- 动机:Codex 启动浏览器走 exec_command(命中 hook、点火 60s),但之后用 write_stdin
-- 驱动常驻 cdp 代理、不再发新 shell 命令,固定 60s 窗口会在会话中途到期,后续每 ~20s
-- 复弹的框就没人点了。改成"见框续命":只要框还在弹(=agent 还在连),看守就一直活;
-- 一旦停手、框不再弹,看守自然过期。仅在 watch 模式(存在 deadline 文件)下生效,
-- 安全性质不变(仍需先被真实命令点亮、仍会自动收口)。
property extendOnClickSecs : 60

on debugLog(msg)
	try
		do shell script "printf '%s %s\\n' \"$(date '+%H:%M:%S')\" " & quoted form of (msg as text) & " >> " & quoted form of debugLogPath
	end try
end debugLog

on run argv
	set pollInterval to 0.4
	set dryRun to false
	if (count of argv) > 0 then
		repeat with arg in argv
			if (arg as text) is "--dry-run" then set dryRun to true
			if (arg as text) starts with "--interval=" then
				set pollInterval to text 12 thru -1 of (arg as text) as number
			end if
		end repeat
	end if

	my debugLog("script started, interval=" & pollInterval & " dry=" & dryRun)

	repeat
		-- 到点自杀：存在 deadline 文件且已过期则退出（watch 窗口模式）；
		-- 无 deadline 文件 = 永久运行（start 模式）。每轮重读，便于 watch 续期。
		try
			set dl to (do shell script "cat " & quoted form of deadlinePath & " 2>/dev/null || echo 0") as number
			if dl > 0 then
				set nowT to (do shell script "date +%s") as number
				if nowT > dl then
					my debugLog("watch window expired, exiting")
					return
				end if
			end if
		end try
		try
			my scanChromiumBrowsers(dryRun)
		on error errMsg number errNum
			my debugLog("scan error " & errNum & ": " & errMsg)
		end try
		delay pollInterval
	end repeat
end run

-- 按 bundle id 囊括所有 Chrome 系进程，含【PWA / 安装成 Mac App 的网站】。
-- 关键：PWA 是独立进程，名字叫 app_mode_loader、不叫 "Google Chrome"，
-- 授权框常弹进当前最前的 PWA 里——按进程名找会整个漏掉（实测踩坑：ChatGPT PWA）。
-- bundle id 前缀：com.google.Chrome（主 Chrome / Canary / PWA com.google.Chrome.app.*）、
-- org.chromium（Chromium）、com.microsoft.edgemac（Edge 及其 PWA）。
on scanChromiumBrowsers(dryRun)
	tell application "System Events"
		set procs to {}
		try
			set procs to procs & (application processes whose bundle identifier starts with "com.google.Chrome")
		end try
		try
			set procs to procs & (application processes whose bundle identifier starts with "org.chromium")
		end try
		try
			set procs to procs & (application processes whose bundle identifier starts with "com.microsoft.edgemac")
		end try
		-- 诊断：本次看守启动时记一次"扫了哪几个 Chrome 系进程"
		if not procsLogged then
			set pnames to ""
			repeat with p in procs
				try
					set pnames to pnames & (name of p) & " "
				end try
			end repeat
			my debugLog("scanning " & (count of procs) & " procs: " & pnames)
			set procsLogged to true
		end if
		repeat with p in procs
			set pLabel to "?"
			try
				set pLabel to name of p
			end try
			my scanProcess(p, pLabel, dryRun)
		end repeat
	end tell
end scanChromiumBrowsers

-- 在一个浏览器进程里找授权 sheet 并点 Allow。
-- 顺序：焦点窗口优先（命中就秒退）→ 全部窗口兜底（用户切走窗口时 sheet 仍在原窗口）。
on scanProcess(chromeProcess, processLabel, dryRun)
	tell application "System Events"
		tell chromeProcess
			set ordered to {}
			-- 1) 焦点窗口排最前（加速：授权框通常挂在连接发生时的活动窗口上）
			try
				set end of ordered to (value of attribute "AXFocusedWindow")
			end try
			-- 2) 追加所有窗口做兜底覆盖（焦点窗口会被再查一次，无害）
			try
				repeat with w in (every window)
					set end of ordered to (contents of w)
				end repeat
			end try
			-- 3) Chrome 未激活时可能读不到窗口，激活后再补一次
			if (count of ordered) is 0 then
				try
					tell application processLabel to activate
					delay 0.3
					repeat with w in (every window)
						set end of ordered to (contents of w)
					end repeat
				end try
			end if

			repeat with win in ordered
				set shts to {}
				try
					set shts to every sheet of win
				end try
				repeat with s in shts
					set allowBtn to my consentAllowButton(s)
					if allowBtn is not missing value then
						if dryRun then
							my debugLog("Dry run: would click Allow on consent sheet (" & processLabel & ")")
						else
							try
								click allowBtn
								my debugLog("Approved remote-debugging consent sheet (" & processLabel & ")")
								my extendDeadline() -- 见框续命:跟着真实授权框延长 watch 窗口
							on error errMsg
								my debugLog("Click Allow failed: " & errMsg)
							end try
						end if
						return -- 点到一个就结束本轮；下一轮 poll 会再看
					end if
				end repeat
			end repeat
		end tell
	end tell
end scanProcess

-- 见框续命:点掉一个真实授权框后,把 watch 截止时间推到 now+extendOnClickSecs。
-- 仅在 watch 模式(deadline 文件存在且 >0)下生效;永久模式(无文件)不创建文件。
-- 只往后推、不缩短(避免把用户手动设的更长窗口改小)。
on extendDeadline()
	-- 全程用 shell 算:Unix 时间戳(~17.8 亿)超过 AppleScript 整数上限(2^29),
	-- 在 AS 里加减会被存成科学计数法、污染 deadline 文件。只把小整数 extendOnClickSecs 传进去。
	try
		do shell script "dl=$(cat " & quoted form of deadlinePath & " 2>/dev/null || echo 0); " & ¬
			"if [ \"$dl\" -gt 0 ]; then new=$(( $(date +%s) + " & (extendOnClickSecs as text) & " )); " & ¬
			"if [ \"$new\" -gt \"$dl\" ]; then printf '%s' \"$new\" > " & quoted form of deadlinePath & "; fi; fi"
	end try
end extendDeadline

-- 判定一个 sheet 是不是远程调试授权框；是则返回它的 Allow 按钮名，否则返回 ""。
-- 只做廉价的按钮存在性 + 浅层文字检查，不递归整棵树。
-- 判定一个 sheet 是不是远程调试授权框；是则返回它的 Allow 按钮【元素】，否则 missing value。
-- 关键：Chrome 这个框里按钮的 name 是空的，标签在 description（截图实测：[AXButton] desc=Allow）。
-- 所以遍历 sheet 的 entire contents（小，~16 个元素），按 name+description+title+value 匹配，
-- 不能用 `button "Allow" of s`（按 name 找会全漏）。
on consentAllowButton(s)
	tell application "System Events"
		set allowBtn to missing value
		set hasCancel to false
		set hasDebugText to false
		set ec to {}
		try
			set ec to entire contents of s
		on error
			return missing value
		end try
		repeat with e in ec
			set r to ""
			try
				set r to role of e as text
			end try
			if r is "AXButton" then
				set lbl to my elemLabel(e)
				if my labelMatches(lbl, cancelButtonNames) then
					set hasCancel to true -- 先判 cancel，免得 "Don't allow" 被当成 allow
				else if my labelMatches(lbl, allowButtonNames) then
					set allowBtn to (contents of e)
				end if
			else if not hasDebugText then
				-- 文字确认是远程调试框（标题/正文含 debug / remote / full control 等）
				set txt to my elemLabel(e)
				ignoring case
					repeat with term in debugTerms
						if txt contains (term as text) then
							set hasDebugText to true
							exit repeat
						end if
					end repeat
				end ignoring
			end if
		end repeat
		-- 诊断：看到有内容的 sheet 就记三要素，便于排查"看到框却没点"
		if (count of ec) > 0 then my debugLog("sheet seen: allowBtn=" & (allowBtn is not missing value) & " cancel=" & hasCancel & " debugText=" & hasDebugText & " elems=" & (count of ec))
		-- 三条都满足才点：有 Allow 按钮 + 有 Cancel 按钮 + 文字确认是远程调试框
		if allowBtn is missing value then return missing value
		if not hasCancel then return missing value
		if not hasDebugText then return missing value
		return allowBtn
	end tell
end consentAllowButton

-- 元素标签：name + description + title + value 拼一起（按钮标签可能在其中任意一个）
on elemLabel(e)
	set p to ""
	tell application "System Events"
		try
			set v to name of e
			if v is not missing value then set p to p & " " & (v as text)
		end try
		try
			set v to description of e
			if v is not missing value then set p to p & " " & (v as text)
		end try
		try
			set v to title of e
			if v is not missing value then set p to p & " " & (v as text)
		end try
		try
			set v to value of e
			if v is not missing value then set p to p & " " & (v as text)
		end try
	end tell
	return p
end elemLabel

-- 空格词边界匹配：要求名字作为完整单词出现，避免子串误判（如 "Bookmark" 含 "ok"）
on labelMatches(lbl, nameList)
	set padded to " " & lbl & " "
	ignoring case
		repeat with nm in nameList
			if padded contains (" " & (nm as text) & " ") then return true
		end repeat
	end ignoring
	return false
end labelMatches
