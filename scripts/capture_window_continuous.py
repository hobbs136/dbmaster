"""Continuous capture from dbmaster window.
Saves frames at fixed interval. Captures for max duration or until N unique frames found.
"""
import sys
import os
import time
import threading
import hashlib
from windows_capture import WindowsCapture, Frame

hwnd = 4523002
out_dir = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\hobbs\Projects\dbmaster\dbmaster-flutter\site\assets\screenshots"
duration_sec = float(sys.argv[2]) if len(sys.argv) > 2 else 6
min_interval_ms = int(sys.argv[3]) if len(sys.argv) > 3 else 200

os.makedirs(out_dir, exist_ok=True)

frame_counter = [0]
saved_hashes = []
control_ref = [None]

def on_frame(frame: Frame, capture_control):
    idx = frame_counter[0]
    frame_counter[0] += 1
    out_path = os.path.join(out_dir, f"_cap_{idx:04d}.png")
    frame.save_as_image(out_path)
    with open(out_path, 'rb') as f:
        h = hashlib.md5(f.read()).hexdigest()[:8]
    saved_hashes.append(h)
    size = os.path.getsize(out_path)
    print(f"frame {idx}: {size}B hash={h}")
    # Stop after 8 frames
    if idx >= 8:
        capture_control.stop()

def on_closed(_):
    pass

capture = WindowsCapture(
    cursor_capture=False,
    window_hwnd=hwnd,
    minimum_update_interval=min_interval_ms,
)
capture.frame_handler = on_frame
capture.closed_handler = on_closed

# Run in thread so we can timeout
t = threading.Thread(target=capture.start, daemon=True)
t.start()

# Wait up to duration_sec, then force exit
deadline = time.time() + duration_sec
while time.time() < deadline:
    time.sleep(0.3)

print(f"final: {frame_counter[0]} frames, {len(set(saved_hashes))} unique")
# Just exit — daemon thread will be killed
os._exit(0)