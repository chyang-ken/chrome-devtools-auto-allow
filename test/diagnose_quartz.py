#!/usr/bin/env python3
"""使用 Quartz 获取所有窗口信息，绕过 System Events Accessibility"""
import Quartz
import json

# 获取所有窗口信息
window_list = Quartz.CGWindowListCopyWindowInfo(
    Quartz.kCGWindowListOptionAll,
    Quartz.kCGNullWindowID
)

chrome_windows = []
for win in window_list:
    owner = win.get(Quartz.kCGWindowOwnerName, "")
    if owner == "Google Chrome":
        chrome_windows.append({
            "name": win.get(Quartz.kCGWindowName, ""),
            "window_id": win.get(Quartz.kCGWindowNumber, 0),
            "bounds": win.get(Quartz.kCGWindowBounds, {}),
            "layer": win.get(Quartz.kCGWindowLayer, 0),
            "alpha": win.get(Quartz.kCGWindowAlpha, 0),
            "memory": win.get(Quartz.kCGWindowMemoryUsage, 0),
            "sharing_state": win.get(Quartz.kCGWindowSharingState, 0),
        })

print(f"Found {len(chrome_windows)} Chrome windows via Quartz:")
for w in chrome_windows:
    print(json.dumps(w, indent=2, default=str))
