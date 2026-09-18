"""Capture dbmaster window using Windows Graphics Capture API (DXGI-based).
Saves to specified PNG path. Bypasses GDI limitations on DirectComposition windows.

Usage:  python capture_window.py <out_path> [hwnd]
If hwnd is omitted, the live "DbMaster" window is auto-discovered.
"""
import sys
import os
import ctypes
import threading
from windows_capture import WindowsCapture, Frame


def find_hwnd() -> int:
    user32 = ctypes.windll.user32
    user32.SetProcessDPIAware()
    EnumWindowsProc = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_int, ctypes.c_int)
    found = [0]
    def cb(hwnd, _lparam):
        if not user32.IsWindowVisible(hwnd):
            return True
        length = user32.GetWindowTextLengthW(hwnd)
        if length == 0:
            return True
        buf = ctypes.create_unicode_buffer(length + 1)
        user32.GetWindowTextW(hwnd, buf, length + 1)
        if buf.value == "DbMaster":
            found[0] = hwnd
            return False
        return True
    user32.EnumWindows(EnumWindowsProc(cb), 0)
    return found[0]


out_path = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\hobbs\Projects\dbmaster\dbmaster-flutter\site\assets\screenshots\_probe.png"
if len(sys.argv) > 2:
    hwnd = int(sys.argv[2])
else:
    hwnd = find_hwnd()
    if not hwnd:
        print("no DbMaster window found", file=sys.stderr)
        sys.exit(2)
print(f"capturing HWND={hwnd} -> {out_path}", file=sys.stderr)

done = threading.Event()
saved = [None]


def on_frame(frame: Frame, capture_control):
    try:
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        frame.save_as_image(out_path)
        saved[0] = os.path.getsize(out_path)
    finally:
        capture_control.stop()
        done.set()


def on_closed(_):
    done.set()


capture = WindowsCapture(
    cursor_capture=False,
    window_hwnd=hwnd,
)
capture.frame_handler = on_frame
capture.closed_handler = on_closed
capture.start()

done.wait(timeout=5.0)
if saved[0]:
    print(f"saved {saved[0]} bytes to {out_path}")
else:
    print("no frame captured", file=sys.stderr)
    sys.exit(1)
