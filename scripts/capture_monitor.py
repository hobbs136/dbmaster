"""Try capturing the whole monitor instead of just the window."""
import sys
import os
import time
import threading
from windows_capture import WindowsCapture, Frame

out_path = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\hobbs\Projects\dbmaster\dbmaster-flutter\site\assets\screenshots\_monitor.png"
os.makedirs(os.path.dirname(out_path), exist_ok=True)

frame_counter = [0]

def on_frame(frame: Frame, capture_control):
    idx = frame_counter[0]
    frame_counter[0] += 1
    frame.save_as_image(out_path)
    print(f"frame {idx}: {os.path.getsize(out_path)} bytes")
    if idx >= 3:
        capture_control.stop()

def on_closed(_):
    pass

# Try monitor 0 first (full primary)
capture = WindowsCapture(
    cursor_capture=False,
    monitor_index=1,
    minimum_update_interval=200,
)
capture.frame_handler = on_frame
capture.closed_handler = on_closed

t = threading.Thread(target=capture.start, daemon=True)
t.start()

deadline = time.time() + 6
while time.time() < deadline:
    time.sleep(0.5)
    if frame_counter[0] >= 3:
        break

print(f"captured {frame_counter[0]} frames")
os._exit(0)