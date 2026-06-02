#!/usr/bin/env python3
"""
使用 Quartz 直接发送键盘事件（Enter/Return），绕过 System Events Accessibility。
"""
import ctypes
import ctypes.util
import time

quartz = ctypes.CDLL(ctypes.util.find_library('Quartz'))

kCGEventKeyDown = 10
kCGEventKeyUp = 11
kCGSessionEventTap = 1

CGEventCreateKeyboardEvent = quartz.CGEventCreateKeyboardEvent
CGEventCreateKeyboardEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint16, ctypes.c_int]
CGEventCreateKeyboardEvent.restype = ctypes.c_void_p

CGEventPost = quartz.CGEventPost
CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]

# macOS 虚拟键码
kVK_Return = 36

def send_key(keycode):
    """发送单个按键"""
    event_down = CGEventCreateKeyboardEvent(None, keycode, 1)
    event_up = CGEventCreateKeyboardEvent(None, keycode, 0)
    CGEventPost(kCGSessionEventTap, event_down)
    time.sleep(0.05)
    CGEventPost(kCGSessionEventTap, event_up)
    time.sleep(0.05)
    if event_down:
        quartz.CFRelease(event_down)
    if event_up:
        quartz.CFRelease(event_up)

print("Sending Enter key in 2 seconds...")
time.sleep(2)
send_key(kVK_Return)
print("Enter key sent.")
