#!/bin/bash
# Run remaining integration tests sequentially (can't parallelize due to Flutter build lock)
cd "$(dirname "$0")/.."

# 开源剥离：主机必填 DBMASTER_TEST_HOST；其余 DBMASTER_* 环境变量透传
TEST_HOST="${DBMASTER_TEST_HOST:?需要 DBMASTER_TEST_HOST（测试库主机）；用户名/密码经 DBMASTER_* 环境变量提供}"
DART_DEFINES=""
while IFS='=' read -r k v; do
  case "$k" in
    DBMASTER_TEST_HOST) ;;
    DBMASTER_*) DART_DEFINES="$DART_DEFINES --dart-define=$k=$v" ;;
  esac
done < <(printenv | grep '^DBMASTER_' || true)
LOG_DIR="integration_test/logs"
mkdir -p "$LOG_DIR"

# Tests to run
TESTS=(
  "integration_test/redis_integration_test.dart"
  "integration_test/doris_integration_test.dart"
  "integration_test/elasticsearch_integration_test.dart"
  "integration_test/sqlserver_integration_test.dart"
  "integration_test/tdengine_integration_test.dart"
  "integration_test/snowflake_integration_test.dart"
)

for test in "${TESTS[@]}"; do
  name=$(basename "$test" .dart)
  echo "========================================"
  echo "Running $name..."
  echo "========================================"
  flutter test "$test" $DART_DEFINES 2>&1 | tee "$LOG_DIR/${name}.log"
  exit_code=${PIPESTATUS[0]}
  if [ $exit_code -eq 0 ]; then
    echo "✅ $name PASSED"
  else
    echo "❌ $name FAILED (exit $exit_code)"
  fi
  echo ""
done

echo "All remaining tests completed."
