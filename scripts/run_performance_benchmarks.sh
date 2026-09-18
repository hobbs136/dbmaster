#!/bin/bash
# ============================================================================
# 性能基准门槛脚本（feature 038, FR-009 / contracts C4）
# 发版前必跑：C1/C3 任一超标即非零退出阻塞发版；C2 超标仅警告不阻塞。
#
# 三段（contracts/benchmark-contracts.md）：
#   [1/3] C1 适配器层基准（真实库, strict）   —— 阻塞
#   [2/3] C2 UI 渲染基准（Debug 代理, strict） —— 警告（开发期回归线, 非验收）
#   [3/3] C3 Profile 帧率基准（验收依据）      —— 阻塞
#
# 用法：bash scripts/run_performance_benchmarks.sh
# 环境：真实测试库参数经 DBMASTER_* 环境变量提供（host 统一经 DBMASTER_TEST_HOST）
# 设备：默认 windows（spec 验收平台）；macOS 执行前请 export BENCH_DEVICE=macos
# ============================================================================

set -e
cd "$(dirname "$0")/.."

# 开源剥离：基准需要真实库参数——DBMASTER_TEST_HOST（统一注入各 DB 的
# *_HOST define）+ 其余 DBMASTER_* 环境变量（用户名/密码）透传。
TEST_HOST="${DBMASTER_TEST_HOST:?需要 DBMASTER_TEST_HOST（测试库主机）；用户名/密码经 DBMASTER_* 环境变量提供}"
DART_DEFINES=""
for db in MYSQL PG MONGO REDIS; do
  DART_DEFINES="$DART_DEFINES --dart-define=DBMASTER_${db}_HOST=$TEST_HOST"
done
while IFS='=' read -r k v; do
  case "$k" in
    DBMASTER_TEST_HOST) ;;
    DBMASTER_*) DART_DEFINES="$DART_DEFINES --dart-define=$k=$v" ;;
  esac
done < <(printenv | grep '^DBMASTER_' || true)

DEVICE="${BENCH_DEVICE:-windows}"
FAILED=0
WARNED=0

echo "================================================================"
echo " [1/3] 适配器层基准（真实库 strict 回归线, contracts C1）"
echo "================================================================"
for f in mysql postgresql redis mongodb; do
  echo ""
  echo "----- ${f} performance benchmark (strict) -----"
  if flutter test "integration_test/${f}_performance_benchmark_test.dart" \
      -d "${DEVICE}" \
      --dart-define=DBMASTER_BENCH_STRICT=1 $DART_DEFINES; then
    echo "✅ ${f} PASSED"
  else
    echo "❌ ${f} FAILED — 阻塞发版（contracts C4）"
    FAILED=1
  fi
done

echo ""
echo "================================================================"
echo " [2/3] UI 渲染基准（Debug 代理, contracts C2）— 仅警告，不阻塞"
echo "================================================================"
# Debug 构建布局成本代理，非验收依据；超标只警告，不置 FAILED
if flutter test test/organisms/results/virtualized_data_table_benchmark_test.dart \
    --dart-define=DBMASTER_BENCH_STRICT=1; then
  echo "✅ C2 Debug 代理 PASSED"
else
  echo "⚠️  C2 Debug 代理超标 — 仅警告，不阻塞发版（contracts C4：C2 警告）"
  WARNED=1
fi

echo ""
echo "================================================================"
echo " [3/3] Profile 验收基准（contracts C3 + PG P2 验收口径, research D3）"
echo "      ⏳ Profile 构建较慢，请耐心等待"
echo "================================================================"
# 帧率验收（scroll/jump ≤33ms, first frame ≤380ms）
if flutter drive --profile -d "${DEVICE}" \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/results_scroll_frame_benchmark_test.dart \
    --dart-define=DBMASTER_BENCH_STRICT=1; then
  echo "✅ scroll frame profile PASSED"
else
  echo "❌ scroll frame profile FAILED — 阻塞发版（contracts C4）"
  FAILED=1
fi

# PG 大结果集取数验收（P2 ≤1s, Profile 口径）
if flutter drive --profile -d "${DEVICE}" \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/postgresql_performance_benchmark_test.dart; then
  echo "✅ PG profile benchmark PASSED（检查 P2 ≤ 1000ms 输出）"
else
  echo "❌ PG profile benchmark FAILED — 阻塞发版（contracts C4）"
  FAILED=1
fi

echo ""
if [ $FAILED -ne 0 ]; then
  echo "❌ 性能门槛未通过（C1/C3 超标），发版被阻塞（contracts C4）"
  exit 1
fi
if [ $WARNED -ne 0 ]; then
  echo "⚠️  性能门槛通过，但 C2 Debug 代理有警告（不阻塞发版）"
  exit 0
fi
echo "✅ 性能门槛全部通过"
