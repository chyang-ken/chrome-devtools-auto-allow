#!/usr/bin/env python3
"""使用 ctypes 直接调用 Quartz API 获取窗口信息"""
import ctypes
import ctypes.util
import json

# 加载 Quartz 框架
quartz = ctypes.CDLL(ctypes.util.find_library('Quartz'))
core_foundation = ctypes.CDLL(ctypes.util.find_library('CoreFoundation'))

# 定义函数
CFRelease = quartz.CFRelease
CFRelease.argtypes = [ctypes.c_void_p]

CGWindowListCopyWindowInfo = quartz.CGWindowListCopyWindowInfo
CGWindowListCopyWindowInfo.argtypes = [ctypes.c_uint32, ctypes.c_uint32]
CGWindowListCopyWindowInfo.restype = ctypes.c_void_p

CFArrayGetCount = core_foundation.CFArrayGetCount
CFArrayGetCount.argtypes = [ctypes.c_void_p]
CFArrayGetCount.restype = ctypes.c_long

CFArrayGetValueAtIndex = core_foundation.CFArrayGetValueAtIndex
CFArrayGetValueAtIndex.argtypes = [ctypes.c_void_p, ctypes.c_long]
CFArrayGetValueAtIndex.restype = ctypes.c_void_p

CFDictionaryGetValue = core_foundation.CFDictionaryGetValue
CFDictionaryGetValue.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
CFDictionaryGetValue.restype = ctypes.c_void_p

CFStringCreateWithCString = core_foundation.CFStringCreateWithCString
CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
CFStringCreateWithCString.restype = ctypes.c_void_p

CFNumberGetValue = core_foundation.CFNumberGetValue
CFNumberGetValue.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
CFNumberGetValue.restype = ctypes.c_bool

CFStringGetCString = core_foundation.CFStringGetCString
CFStringGetCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
CFStringGetCString.restype = ctypes.c_bool

kCFStringEncodingUTF8 = 0x08000100

# 创建 CFString 键
keys = {
    "kCGWindowName": CFStringCreateWithCString(None, b"kCGWindowName", kCFStringEncodingUTF8),
    "kCGWindowOwnerName": CFStringCreateWithCString(None, b"kCGWindowOwnerName", kCFStringEncodingUTF8),
    "kCGWindowNumber": CFStringCreateWithCString(None, b"kCGWindowNumber", kCFStringEncodingUTF8),
    "kCGWindowLayer": CFStringCreateWithCString(None, b"kCGWindowLayer", kCFStringEncodingUTF8),
    "kCGWindowBounds": CFStringCreateWithCString(None, b"kCGWindowBounds", kCFStringEncodingUTF8),
    "kCGWindowAlpha": CFStringCreateWithCString(None, b"kCGWindowAlpha", kCFStringEncodingUTF8),
}

def cfstring_to_str(cfstr):
    if not cfstr:
        return ""
    buf = ctypes.create_string_buffer(256)
    if CFStringGetCString(cfstr, buf, 256, kCFStringEncodingUTF8):
        return buf.value.decode('utf-8')
    return ""

# 获取窗口列表
kCGWindowListOptionAll = 0
kCGNullWindowID = 0
window_list = CGWindowListCopyWindowInfo(kCGWindowListOptionAll, kCGNullWindowID)
count = CFArrayGetCount(window_list)

chrome_windows = []

for i in range(count):
    win = CFArrayGetValueAtIndex(window_list, i)

    owner_ref = CFDictionaryGetValue(win, keys["kCGWindowOwnerName"])
    owner = cfstring_to_str(owner_ref)

    if owner == "Google Chrome":
        name_ref = CFDictionaryGetValue(win, keys["kCGWindowName"])
        name = cfstring_to_str(name_ref)

        win_id = ctypes.c_int32(0)
        win_id_ref = CFDictionaryGetValue(win, keys["kCGWindowNumber"])
        if win_id_ref:
            CFNumberGetValue(win_id_ref, 9, ctypes.byref(win_id))

        layer = ctypes.c_int32(0)
        layer_ref = CFDictionaryGetValue(win, keys["kCGWindowLayer"])
        if layer_ref:
            CFNumberGetValue(layer_ref, 9, ctypes.byref(layer))

        alpha = ctypes.c_double(0)
        alpha_ref = CFDictionaryGetValue(win, keys["kCGWindowAlpha"])
        if alpha_ref:
            CFNumberGetValue(alpha_ref, 13, ctypes.byref(alpha))

        # 获取 bounds (CGRect)
        bounds_ref = CFDictionaryGetValue(win, keys["kCGWindowBounds"])
        bounds_dict = {}
        if bounds_ref:
            # bounds 是一个 CFDictionary，包含 X, Y, Width, Height
            b_keys = {
                "X": CFStringCreateWithCString(None, b"X", kCFStringEncodingUTF8),
                "Y": CFStringCreateWithCString(None, b"Y", kCFStringEncodingUTF8),
                "Width": CFStringCreateWithCString(None, b"Width", kCFStringEncodingUTF8),
                "Height": CFStringCreateWithCString(None, b"Height", kCFStringEncodingUTF8),
            }
            for bk, bcf in b_keys.items():
                bv_ref = CFDictionaryGetValue(bounds_ref, bcf)
                bv = ctypes.c_double(0)
                if bv_ref:
                    CFNumberGetValue(bv_ref, 13, ctypes.byref(bv))
                    bounds_dict[bk] = bv.value
                CFRelease(bcf)

        chrome_windows.append({
            "name": name,
            "window_id": win_id.value,
            "layer": layer.value,
            "alpha": alpha.value,
            "bounds": bounds_dict,
        })

print(f"Found {len(chrome_windows)} Chrome windows:")
for w in chrome_windows:
    print(json.dumps(w, indent=2, default=str))

# 尝试找到弹窗（layer != 0 或大小适中且居中）
print("\n--- Potential dialog candidates ---")
for w in chrome_windows:
    b = w.get("bounds", {})
    width = b.get("Width", 0)
    height = b.get("Height", 0)
    # 弹窗通常是较小的模态对话框
    if w["layer"] != 0 or (200 < width < 600 and 100 < height < 400):
        print(f"Candidate: {w}")

# 释放
CFRelease(window_list)
for k in keys.values():
    CFRelease(k)
