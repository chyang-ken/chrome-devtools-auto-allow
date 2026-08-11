use scripting additions

-- 授权框是挂在某个窗口上的 sheet，带 Allow + Cancel 两个按钮，文字含 "remote debugging /
-- wants full control" 之类。本脚本只找这种 sheet 并点 Allow，不读整页文字、不整树递归
-- （旧实现对每个普通窗口递归整棵辅助功能树，在 Google Ads/Gmail 等重页面上会卡死几十秒）。
property allowButtonNames : {"Allow", "允许", "允許", "OK", "Ok", "确定", "確認", "好"}
property cancelButtonNames : {"Cancel", "取消", "取消", "Don't allow", "Deny"}
property debugTerms : {"remote debugging", "full control", "external app", "远程调试", "遠端偵錯", "遠端調試"}
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
		-- 不能先拿 application process 对象再逐个读属性：Chrome 151 下多个进程同名，
		-- System Events 会把每个对象都重新解析成列表中的第一个同名进程。直接批量取 PID 列表。
		set processIds to {}
		set processLabels to {}
		try
			set processIds to processIds & (unix id of every application process whose bundle identifier starts with "com.google.Chrome")
			set processLabels to processLabels & (name of every application process whose bundle identifier starts with "com.google.Chrome")
		end try
		try
			set processIds to processIds & (unix id of every application process whose bundle identifier starts with "org.chromium")
			set processLabels to processLabels & (name of every application process whose bundle identifier starts with "org.chromium")
		end try
		try
			set processIds to processIds & (unix id of every application process whose bundle identifier starts with "com.microsoft.edgemac")
			set processLabels to processLabels & (name of every application process whose bundle identifier starts with "com.microsoft.edgemac")
		end try
		-- 诊断：本次看守启动时记一次"扫了哪几个 Chrome 系进程"
		if not procsLogged then
			set pnames to ""
			repeat with processIndex from 1 to count of processIds
				set pnames to pnames & (item processIndex of processLabels as text) & ":" & (item processIndex of processIds as text) & " "
			end repeat
			my debugLog("scanning " & (count of processIds) & " procs: " & pnames)
			set procsLogged to true
		end if
		repeat with processIndex from 1 to count of processIds
			set processId to item processIndex of processIds
			set pLabel to item processIndex of processLabels
			my scanProcess(processId, pLabel, dryRun)
		end repeat
	end tell
end scanChromiumBrowsers

-- 在一个浏览器进程里找授权 sheet 并点 Allow。
-- Chrome 151 下多个 Chrome/PWA 进程可能同名，必须按 PID 重新定位，不能靠名称引用。
on scanProcess(processId, processLabel, dryRun)
	set targetPid to processId
	tell application "System Events"
		tell (first application process whose unix id is targetPid)
			set windowCount to 0
			try
				set windowCount to count of windows
			end try
			-- 读不到窗口时失败关闭。扫描本身绝不能激活 Chrome/PWA，否则每轮轮询都会抢焦点。
			if windowCount is 0 then return
			repeat with windowIndex from 1 to windowCount
				-- Chrome 151 的确认框不再一定是 macOS sheet，可能是独立的 AXUnknown 小窗口。
				-- 只把尺寸作为缩小递归范围的条件；它本身绝不是授权依据。
				set isSmallDialog to false
				try
					set wSubrole to subrole of window windowIndex as text
					if wSubrole is "AXUnknown" then
						try
							set wSize to size of window windowIndex
							set wWidth to item 1 of wSize
							set wHeight to item 2 of wSize
							if wWidth > 0 and wHeight > 0 and wWidth < 600 and wHeight < 600 then set isSmallDialog to true
							my debugLog(processLabel & " AXUnknown window size=" & wWidth & "x" & wHeight)
						end try
					end if
				end try
				if isSmallDialog then
					set allowBtn to my consentAllowButton(a reference to window windowIndex)
					if allowBtn is not missing value then
						if dryRun then
							my debugLog("Dry run: would click Allow on confirmed AXUnknown dialog (" & processLabel & ")")
						else
							try
								click allowBtn
								my debugLog("Approved confirmed AXUnknown remote-debugging dialog (" & processLabel & ")")
								my extendDeadline()
							on error errMsg
								my debugLog("Click confirmed AXUnknown Allow failed: " & errMsg)
							end try
						end if
						return
					else
						my debugLog("Ignoring unconfirmed AXUnknown dialog (" & processLabel & ")")
					end if
				end if

				set sheetCount to 0
				try
					set sheetCount to count of sheets of window windowIndex
				end try
				if sheetCount > 0 then my debugLog("pid=" & processId & " window=" & windowIndex & " sheets=" & sheetCount)
				repeat with sheetIndex from 1 to sheetCount
					set allowBtn to my consentAllowButton(a reference to sheet sheetIndex of window windowIndex)
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

on textMatchesDebugTerm(inputText)
	ignoring case
		repeat with term in debugTerms
			if inputText contains (term as text) then return true
		end repeat
	end ignoring
	return false
end textMatchesDebugTerm

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

-- 判定一个小型容器是不是远程调试授权框；是则返回它的 Allow 按钮【元素】，否则 missing value。
-- 关键：Chrome 这个框里按钮的 name 是空的，标签在 description（截图实测：[AXButton] desc=Allow）。
-- Chrome 151 对容器的 `entire contents` 返回空列表，必须沿 `UI elements` 递归；
-- 调用方只会传入 sheet 或已确认尺寸很小的 AXUnknown 窗口，不会扫描普通网页窗口。
on consentAllowButton(containerRef)
	-- "Don't allow" 同时包含单词 "allow"；查允许按钮时必须显式排除拒绝标签。
	set allowBtn to my findButtonRecursive(containerRef, allowButtonNames, cancelButtonNames, 0)
	set cancelBtn to my findButtonRecursive(containerRef, cancelButtonNames, {}, 0)
	set hasDebugText to my treeHasDebugText(containerRef, 0)
	my debugLog("consent container seen: allowBtn=" & (allowBtn is not missing value) & " cancel=" & (cancelBtn is not missing value) & " debugText=" & hasDebugText & " recursive=true")
	if allowBtn is missing value then return missing value
	if cancelBtn is missing value then return missing value
	if not hasDebugText then return missing value
	return allowBtn
end consentAllowButton

on findButtonRecursive(rootElement, buttonNames, excludedNames, depth)
	if depth > 12 then return missing value
	tell application "System Events"
		set r to ""
		try
			set r to role of rootElement as text
		end try
		if r is "AXButton" then
			set lbl to my elemLabel(rootElement)
			if my labelMatches(lbl, buttonNames) and not my labelMatches(lbl, excludedNames) then return rootElement
		end if
		try
			repeat with childElement in UI elements of rootElement
				set foundButton to my findButtonRecursive(childElement, buttonNames, excludedNames, depth + 1)
				if foundButton is not missing value then return foundButton
			end repeat
		end try
	end tell
	return missing value
end findButtonRecursive

on treeHasDebugText(rootElement, depth)
	if depth > 12 then return false
	set txt to my elemLabel(rootElement)
	if my textMatchesDebugTerm(txt) then return true
	tell application "System Events"
		try
			repeat with childElement in UI elements of rootElement
				if my treeHasDebugText(childElement, depth + 1) then return true
			end repeat
		end try
	end tell
	return false
end treeHasDebugText

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
