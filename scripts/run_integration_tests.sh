#!/bin/bash
# 逐个运行 Flutter 集成测试文件，避免 macOS 桌面应用重启问题

set -e

PROJECT_DIR="/Users/jacky/development/dbmaster-flutter"
cd "$PROJECT_DIR"

# 数据库连接配置（开源剥离：默认凭据已从 config 清空）
# - 主机：必填 DBMASTER_TEST_HOST（统一注入各 DB 的 *_HOST define）
# - 用户名/密码等：从环境里其余 DBMASTER_* 变量原样透传（键名见
#   integration_test/config/*_test_config.dart）
TEST_HOST="${DBMASTER_TEST_HOST:?需要 DBMASTER_TEST_HOST（测试库主机）；用户名/密码经 DBMASTER_* 环境变量提供}"
DART_DEFINES=""
for db in MYSQL PG MONGO REDIS DORIS SQLSERVER ORACLE TDENGINE ES; do
  DART_DEFINES="$DART_DEFINES --dart-define=DBMASTER_${db}_HOST=$TEST_HOST"
done
while IFS='=' read -r k v; do
  case "$k" in
    DBMASTER_TEST_HOST) ;;
    DBMASTER_*) DART_DEFINES="$DART_DEFINES --dart-define=$k=$v" ;;
  esac
done < <(printenv | grep '^DBMASTER_' || true)

RESULTS_FILE="/tmp/integration_test_results.txt"
echo "Integration Test Results - $(date)" > "$RESULTS_FILE"
echo "=================================" >> "$RESULTS_FILE"

TOTAL=0
PASSED=0
FAILED=0

for test_file in integration_test/*_test.dart; do
    filename=$(basename "$test_file")
    # 跳过性能基准文件——改由末尾 benchmark 段以 strict 模式统一执行（contracts C1/C3）
    case "$filename" in
        *_performance_benchmark_test.dart|results_scroll_frame_benchmark_test.dart) continue ;;
    esac
    echo ""
    echo "========================================"
    echo "Running: $filename"
    echo "========================================"

    # 杀掉残留进程
    pkill -f "DbMaster.app/Contents/MacOS/DbMaster" 2>/dev/null || true
    pkill -f "flutter_tester" 2>/dev/null || true
    sleep 2

    set +e
    flutter test "$test_file" $DART_DEFINES --timeout=none 2>&1 | tee "/tmp/${filename}.log"
    exit_code=${PIPESTATUS[0]}
    set -e

    TOTAL=$((TOTAL + 1))
    if [ $exit_code -eq 0 ]; then
        PASSED=$((PASSED + 1))
        echo "✅ $filename - PASSED" >> "$RESULTS_FILE"
    else
        FAILED=$((FAILED + 1))
        echo "❌ $filename - FAILED" >> "$RESULTS_FILE"
    fi

    # 再次清理残留进程
    pkill -f "DbMaster.app/Contents/MacOS/DbMaster" 2>/dev/null || true
    pkill -f "flutter_tester" 2>/dev/null || true
    sleep 1
done

# 性能基准门槛段（feature 038, FR-009 / contracts C4）
# 委托独立门槛脚本：C1(strict,阻塞)+C2(警告)+C3 Profile(阻塞)；任一 C1/C3 超标阻塞发版。
echo "" >> "$RESULTS_FILE"
echo "=================================" >> "$RESULTS_FILE"
echo "Performance Benchmark Gate (contracts C4)" >> "$RESULTS_FILE"
echo "=================================" >> "$RESULTS_FILE"
set +e
BENCH_DEVICE=macos bash "$(dirname "$0")/run_performance_benchmarks.sh"
BENCH_EXIT=$?
set -e
if [ $BENCH_EXIT -eq 0 ]; then
    echo "✅ performance benchmark gate PASSED" >> "$RESULTS_FILE"
else
    echo "❌ performance benchmark gate FAILED — 阻塞发版（contracts C4）" >> "$RESULTS_FILE"
    FAILED=$((FAILED + 1))
fi

echo "" >> "$RESULTS_FILE"
echo "=================================" >> "$RESULTS_FILE"
echo "Total: $TOTAL, Passed: $PASSED, Failed: $FAILED" >> "$RESULTS_FILE"
echo "=================================" >> "$RESULTS_FILE"

cat "$RESULTS_FILE"
