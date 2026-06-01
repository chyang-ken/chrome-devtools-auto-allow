use scripting additions

property allowButtonNames : {"Allow", "允许", "允許", "OK", "Ok", "确定", "確認", "好"}
property requiredTerms : {"debug", "DevTools", "Developer Tools", "remote debugging", "CDP", "chrome-devtools", "MCP", "remote debugging connection", "another program is trying", "远程调试", "遠端偵錯", "遠端調試"}

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
	
	repeat
		try
			my scanChromiumBrowsers(dryRun)
		on error errMsg number errNum
			log "scan error " & errNum & ": " & errMsg
		end try
		delay pollInterval
	end repeat
end run

on scanChromiumBrowsers(dryRun)
	tell application "System Events"
		if exists process "Google Chrome" then my scanProcess(process "Google Chrome", dryRun)
		if exists process "Google Chrome Canary" then my scanProcess(process "Google Chrome Canary", dryRun)
		if exists process "Chromium" then my scanProcess(process "Chromium", dryRun)
	end tell
end scanChromiumBrowsers

on scanProcess(chromeProcess, dryRun)
	tell application "System Events"
		tell chromeProcess
			repeat with w in windows
				set uiText to my textOfElement(w)
				if my looksLikeCdpPrompt(uiText) then
					log "Matched Chrome CDP/DevTools prompt: " & my clipText(uiText)
					if dryRun then
						log "Dry run: would approve prompt"
					else
						if my clickAllowButton(w) then
							log "Approved Chrome CDP/DevTools prompt"
						else
							log "Matched prompt, but no allow button was clickable"
						end if
					end if
				end if
			end repeat
		end tell
	end tell
end scanProcess

on looksLikeCdpPrompt(uiText)
	ignoring case
		repeat with t in requiredTerms
			if uiText contains (t as text) then return true
		end repeat
	end ignoring
	return false
end looksLikeCdpPrompt

on clickAllowButton(rootElement)
	tell application "System Events"
		repeat with buttonName in allowButtonNames
			try
				if exists button (buttonName as text) of rootElement then
					click button (buttonName as text) of rootElement
					return true
				end if
			end try
		end repeat
		
		try
			set roleText to role of rootElement as text
			ignoring case
				set isButton to roleText contains "button"
			end ignoring
			if isButton then
				set buttonText to my buttonLabel(rootElement)
				ignoring case
					repeat with buttonName in allowButtonNames
						if buttonText contains (buttonName as text) then
							log "Clicking allow button: " & buttonText
							click rootElement
							return true
						end if
					end repeat
				end ignoring
			end if
		end try
		
		try
			repeat with childElement in UI elements of rootElement
				if my clickAllowButton(childElement) then return true
			end repeat
		end try
	end tell
	return false
end clickAllowButton

on buttonLabel(rootElement)
	set pieces to ""
	tell application "System Events"
		try
			set buttonName to name of rootElement
			if buttonName is not missing value then set pieces to pieces & " " & (buttonName as text)
		end try
		try
			set buttonDescription to description of rootElement
			if buttonDescription is not missing value then set pieces to pieces & " " & (buttonDescription as text)
		end try
		try
			set buttonValue to value of rootElement
			if buttonValue is not missing value then set pieces to pieces & " " & (buttonValue as text)
		end try
	end tell
	return pieces
end buttonLabel

on textOfElement(rootElement)
	set pieces to ""
	tell application "System Events"
		try
			set elementName to name of rootElement
			if elementName is not missing value then set pieces to pieces & " " & (elementName as text)
		end try
		try
			set elementDescription to description of rootElement
			if elementDescription is not missing value then set pieces to pieces & " " & (elementDescription as text)
		end try
		try
			set elementValue to value of rootElement
			if elementValue is not missing value then set pieces to pieces & " " & (elementValue as text)
		end try
		try
			repeat with childElement in UI elements of rootElement
				set pieces to pieces & " " & my textOfElement(childElement)
			end repeat
		end try
	end tell
	return pieces
end textOfElement

on clipText(inputText)
	if (length of inputText) > 500 then return text 1 thru 500 of inputText
	return inputText
end clipText
