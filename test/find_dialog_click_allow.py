#!/usr/bin/env python3
"""
通过屏幕截图识别 Chrome 远程调试弹窗并自动点击 Allow。
适用于 System Events Accessibility 失效的场景。
"""
import ctypes
import ctypes.util
import subprocess
import tempfile
import time
from PIL import Image

quartz = ctypes.CDLL(ctypes.util.find_library('Quartz'))

# Quartz 常量
kCGEventMouseMoved = 5
kCGEventLeftMouseDown = 1
kCGEventLeftMouseUp = 2
kCGHIDEventTap = 0
kCGMouseButtonLeft = 0

# 显示器尺寸
CGMainDisplayID = quartz.CGMainDisplayID
CGMainDisplayID.restype = ctypes.c_uint32
CGDisplayBounds = quartz.CGDisplayBounds
CGDisplayBounds.argtypes = [ctypes.c_uint32]

class CGRect(ctypes.Structure):
    _fields_ = [
        ("origin_x", ctypes.c_double), ("origin_y", ctypes.c_double),
        ("size_width", ctypes.c_double), ("size_height", ctypes.c_double),
    ]
CGDisplayBounds.restype = CGRect

main_display = CGMainDisplayID()
bounds = CGDisplayBounds(main_display)
SCREEN_W = int(bounds.size_width)
SCREEN_H = int(bounds.size_height)

CGEventCreateMouseEvent = quartz.CGEventCreateMouseEvent
CGEventCreateMouseEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32]
CGEventCreateMouseEvent.restype = ctypes.c_void_p
CGEventPost = quartz.CGEventPost
CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]

class CGPoint(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]

def click_at(x, y):
    """Quartz 坐标系原点在左下角"""
    qy = SCREEN_H - y
    pt = CGPoint(x, qy)
    for evt_type in [kCGEventMouseMoved, kCGEventLeftMouseDown, kCGEventLeftMouseUp]:
        event = CGEventCreateMouseEvent(None, evt_type, ctypes.byref(pt), kCGMouseButtonLeft)
        CGEventPost(kCGHIDEventTap, event)
        quartz.CFRelease(event)
        time.sleep(0.05)

def screenshot(path="/tmp/cdp_dialog_screen.png"):
    subprocess.run(["screencapture", "-x", path], check=True)
    return path

def find_dialog_and_allow():
    """
    截图 -> 找白色弹窗 -> 找蓝色 Allow 按钮 -> 点击
    """
    start = time.time()
    img_path = screenshot()
    img = Image.open(img_path).convert("RGB")
    pixels = img.load()
    w, h = img.size

    # 1. 找弹窗：屏幕中央的白色/浅灰色大矩形
    #    弹窗背景色通常是 (250, 250, 250) 左右
    #    我们扫描屏幕中央区域，找到连续的浅色区域
    dialog_left = dialog_top = dialog_right = dialog_bottom = None

    # 扫描范围：屏幕中央 70%
    scan_x1 = int(w * 0.15)
    scan_x2 = int(w * 0.85)
    scan_y1 = int(h * 0.20)
    scan_y2 = int(h * 0.80)

    # 找弹窗上边界：从 scan_y1 向下找，连续有大量浅色像素的行
    bg_threshold = 245  # 背景色阈值
    min_width = 300     # 弹窗最小宽度

    candidate_rows = []
    for y in range(scan_y1, scan_y2):
        light_count = 0
        for x in range(scan_x1, scan_x2):
            r, g, b = pixels[x, y]
            if r > bg_threshold and g > bg_threshold and b > bg_threshold:
                light_count += 1
        if light_count >= min_width:
            candidate_rows.append(y)

    if len(candidate_rows) < 30:
        print(f"No dialog found (only {len(candidate_rows)} light rows)")
        return False

    dialog_top = candidate_rows[0]
    dialog_bottom = candidate_rows[-1]

    # 找弹窗左右边界：在 dialog_top + 10 处扫描
    check_y = dialog_top + 10
    light_xs = []
    for x in range(scan_x1, scan_x2):
        r, g, b = pixels[x, check_y]
        if r > bg_threshold and g > bg_threshold and b > bg_threshold:
            light_xs.append(x)

    if not light_xs:
        print("No dialog width found")
        return False

    dialog_left = light_xs[0]
    dialog_right = light_xs[-1]

    dialog_w = dialog_right - dialog_left
    dialog_h = dialog_bottom - dialog_top

    print(f"Dialog found: x={dialog_left}, y={dialog_top}, w={dialog_w}, h={dialog_h}")

    # 2. 在弹窗内找 Allow 按钮（浅蓝色）
    #    Allow 按钮通常在右下角，颜色大约是 (180-210, 200-220, 240-255)
    #    我们扫描弹窗右下 1/3 区域
    btn_search_x1 = dialog_left + int(dialog_w * 0.55)
    btn_search_x2 = dialog_right - 10
    btn_search_y1 = dialog_top + int(dialog_h * 0.60)
    btn_search_y2 = dialog_bottom - 10

    blue_pixels = []
    for y in range(btn_search_y1, btn_search_y2):
        for x in range(btn_search_x1, btn_search_x2):
            r, g, b = pixels[x, y]
            # 浅蓝色特征：B 明显大于 R 和 G
            if b > r + 15 and b > g + 10 and b > 220 and r > 170 and g > 190:
                blue_pixels.append((x, y))

    if len(blue_pixels) < 50:
        print(f"No blue Allow button found (only {len(blue_pixels)} blue pixels)")
        return False

    # 计算蓝色区域的中心
    bx = sum(p[0] for p in blue_pixels) // len(blue_pixels)
    by = sum(p[1] for p in blue_pixels) // len(blue_pixels)

    print(f"Allow button center: ({bx}, {by})")

    # 3. 点击
    click_at(bx, by)
    elapsed = time.time() - start
    print(f"Clicked Allow in {elapsed:.2f}s")
    return True


if __name__ == "__main__":
    result = find_dialog_and_allow()
    print(f"Result: {result}")
