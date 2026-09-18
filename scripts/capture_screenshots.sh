#!/bin/bash
# DbMaster App Store 截图辅助脚本
# 用法: bash scripts/capture_screenshots.sh

set -e

OUTPUT_DIR="screenshots"
mkdir -p "$OUTPUT_DIR"

echo "=== DbMaster App Store 截图脚本 ==="
echo "输出目录: $OUTPUT_DIR"

# 检查是否在项目根目录
if [ ! -f "pubspec.yaml" ]; then
    echo "错误: 请在项目根目录运行此脚本"
    exit 1
fi

# 检查是否已有运行的 Flutter 应用
FLUTTER_PID=$(pgrep -f "dbmaster" | head -1 || true)

if [ -z "$FLUTTER_PID" ]; then
    echo "正在启动 DbMaster..."
    flutter run -d macos --release > /tmp/dbmaster_run.log 2>&1 &
    FLUTTER_PID=$!
    echo "Flutter PID: $FLUTTER_PID"
    echo "等待应用启动 (15 秒)..."
    sleep 15
else
    echo "检测到已有运行的 DbMaster 应用 (PID: $FLUTTER_PID)"
fi

# 等待窗口出现
sleep 3

# 调整窗口大小为 1280x800
echo "调整窗口大小为 1280x800..."
osascript -e 'tell application "System Events" to tell process "dbmaster" to set size of front window to {1280, 800}' 2>/dev/null || true
sleep 2

# 截图整个窗口
echo "截取主界面..."
screencapture -w "$OUTPUT_DIR/screenshot_1_main_1280x800.png" 2>/dev/null || \
    screencapture -x "$OUTPUT_DIR/screenshot_1_main_1280x800.png"

# 生成其他尺寸
echo "生成 1440x900 尺寸..."
sips -z 900 1440 "$OUTPUT_DIR/screenshot_1_main_1280x800.png" --out "$OUTPUT_DIR/screenshot_1_main_1440x900.png" >/dev/null 2>&1 || true

echo "生成 2560x1600 尺寸..."
sips -z 1600 2560 "$OUTPUT_DIR/screenshot_1_main_1280x800.png" --out "$OUTPUT_DIR/screenshot_1_main_2560x1600.png" >/dev/null 2>&1 || true

# 调整窗口为 1440x900 重新截图（更精确）
osascript -e 'tell application "System Events" to tell process "dbmaster" to set size of front window to {1440, 900}' 2>/dev/null || true
sleep 2
screencapture -w "$OUTPUT_DIR/screenshot_1_main_1440x900.png" 2>/dev/null || true

# 调整窗口为 2560x1600 重新截图
osascript -e 'tell application "System Events" to tell process "dbmaster" to set size of front window to {2560, 1600}' 2>/dev/null || true
sleep 2
screencapture -w "$OUTPUT_DIR/screenshot_1_main_2560x1600.png" 2>/dev/null || true

# 恢复窗口大小
osascript -e 'tell application "System Events" to tell process "dbmaster" to set size of front window to {1280, 800}' 2>/dev/null || true

echo ""
echo "=== 截图完成 ==="
echo "文件列表:"
ls -la "$OUTPUT_DIR"
echo ""
echo "注意: 此脚本仅生成主界面示例截图。"
echo "AI 面板、ER 图、深色模式等截图请手动操作。"
