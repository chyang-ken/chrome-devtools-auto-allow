#!/usr/bin/env python3
"""使用 Quartz 直接模拟鼠标点击 Allow 按钮"""
import ctypes
import ctypes.util
import time

quartz = ctypes.CDLL(ctypes.util.find_library('Quartz'))

# Quartz 鼠标事件类型
kCGEventMouseMoved = 5
kCGEventLeftMouseDown = 1
kCGEventLeftMouseUp = 2

# 获取主显示器尺寸
CGMainDisplayID = quartz.CGMainDisplayID
CGMainDisplayID.restype = ctypes.c_uint32

CGDisplayBounds = quartz.CGDisplayBounds
CGDisplayBounds.argtypes = [ctypes.c_uint32]

class CGRect(ctypes.Structure):
    _fields_ = [
        ("origin_x", ctypes.c_double),
        ("origin_y", ctypes.c_double),
        ("size_width", ctypes.c_double),
        ("size_height", ctypes.c_double),
    ]

CGDisplayBounds.restype = CGRect

main_display = CGMainDisplayID()
bounds = CGDisplayBounds(main_display)
screen_width = bounds.size_width
screen_height = bounds.size_height

print(f"Screen: {screen_width}x{screen_height}")

# 从截图和 Quartz 数据推断弹窗位置
# 主窗口 11108: X=0, Y=33, Width=1512, Height=944
# 弹窗在主窗口中央，宽度约 500px，高度约 220px
# Allow 按钮在弹窗右下角
main_window_x = 0
main_window_y = 33
main_window_w = 1512
main_window_h = 944

# 估算弹窗尺寸
dialog_w = 500
dialog_h = 220

# 弹窗中心（在主窗口中央）
dialog_center_x = main_window_x + main_window_w / 2
dialog_center_y = main_window_y + main_window_h / 2

# Allow 按钮在弹窗右下角区域
# 按钮约 80x30，距离弹窗右边约 20px，距离弹窗底部约 20px
allow_btn_x = dialog_center_x + dialog_w / 2 - 60
allow_btn_y = dialog_center_y + dialog_h / 2 - 25

print(f"Estimated Allow button position: ({allow_btn_x}, {allow_btn_y})")

# Quartz 坐标系：原点在左下角，Y 向上
quartz_y = screen_height - allow_btn_y

print(f"Quartz coordinates: ({allow_btn_x}, {quartz_y})")

# 创建鼠标事件
CGEventCreateMouseEvent = quartz.CGEventCreateMouseEvent
CGEventCreateMouseEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_uint32]
CGEventCreateMouseEvent.restype = ctypes.c_void_p

CGEventPost = quartz.CGEventPost
CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]

CGEventSetLocation = quartz.CGEventSetLocation
CGEventSetLocation.argtypes = [ctypes.c_void_p, ctypes.c_void_p]

kCGHIDEventTap = 0
kCGMouseButtonLeft = 0

class CGPoint(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]

point = CGPoint(allow_btn_x, quartz_y)

# 移动鼠标
def post_event(event_type, point):
    event = CGEventCreateMouseEvent(None, event_type, ctypes.byref(point), kCGMouseButtonLeft)
    CGEventPost(kCGHIDEventTap, event)
    quartz.CFRelease(event)

print("Clicking Allow button in 3 seconds...")
time.sleep(3)

# 移动到位置
post_event(kCGEventMouseMoved, point)
time.sleep(0.1)

# 按下
post_event(kCGEventLeftMouseDown, point)
time.sleep(0.1)

# 释放
post_event(kCGEventLeftMouseUp, point)

print("Click sent!")
