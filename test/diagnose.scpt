use scripting additions

tell application "System Events"
    tell process "Google Chrome"
        set allWindows to every window
        set results to "Window count: " & (count of allWindows) & return
        repeat with w in allWindows
            try
                set wName to name of w
            on error
                set wName to "<noname>"
            end try
            set results to results & "--- Window: " & wName & return

            try
                set wRole to role of w
                set results to results & "  Role: " & wRole & return
            end try

            try
                set subroleValue to subrole of w
                set results to results & "  Subrole: " & subroleValue & return
            end try

            try
                set sheets to every sheet of w
                set results to results & "  Sheets: " & (count of sheets) & return
                repeat with s in sheets
                    try
                        set sName to name of s
                    on error
                        set sName to "<noname>"
                    end try
                    set results to results & "    Sheet: " & sName & return
                    try
                        set uiElems to every UI element of s
                        set results to results & "      UI elements: " & (count of uiElems) & return
                        repeat with elem in uiElems
                            try
                                set eName to name of elem
                                set eRole to role of elem
                                set results to results & "        - " & eRole & ": " & eName & return
                            end try
                        end repeat
                    end try
                end repeat
            end try

            try
                set dialogs to every dialog of w
                set results to results & "  Dialogs: " & (count of dialogs) & return
            end try

            try
                set uiElems to every UI element of w
                set results to results & "  Top-level UI elements: " & (count of uiElems) & return
                repeat with elem in uiElems
                    try
                        set eName to name of elem
                        set eRole to role of elem
                        set results to results & "    - " & eRole & ": " & eName & return
                    end try
                end repeat
            end try
        end repeat
        return results
    end tell
end tell
