# DbMaster integration test runner (Windows PowerShell)
# Equivalent to scripts/run_integration_tests.sh for Windows

$ErrorActionPreference = "Continue"
$projectDir = "C:\Users\hobbs\Projects\dbmaster\dbmaster-flutter"
$resultsLog = Join-Path $projectDir "integration_test_results.txt"
$perTestLogDir = Join-Path $projectDir "integration_test_logs"
$timeout = 600  # 10 minutes

if (-not (Test-Path $perTestLogDir)) {
    New-Item -ItemType Directory -Path $perTestLogDir -Force | Out-Null
}

# Common dart-defines
$defineKeys = @(
    "DBMASTER_MYSQL_HOST",
    "DBMASTER_PG_HOST",
    "DBMASTER_MONGO_HOST",
    "DBMASTER_REDIS_HOST",
    "DBMASTER_DORIS_HOST",
    "DBMASTER_SQLSERVER_HOST",
    "DBMASTER_ORACLE_HOST",
    "DBMASTER_TDENGINE_HOST",
    "DBMASTER_ES_HOST"
)
$defineHost = $env:DBMASTER_TEST_HOST
if (-not $defineHost) {
    Write-Error "DBMASTER_TEST_HOST is required (test DB host). Credentials are forwarded from DBMASTER_* env vars (see integration_test/config/*_test_config.dart)."
    exit 1
}
$dartDefinesList = @()
foreach ($k in $defineKeys) {
    $dartDefinesList += "--dart-define=$k=$defineHost"
}
# Forward remaining DBMASTER_* env vars (user/password/port overrides).
Get-ChildItem env: |
    Where-Object { $_.Name -like "DBMASTER_*" -and $_.Name -ne "DBMASTER_TEST_HOST" } |
    ForEach-Object { $dartDefinesList += "--dart-define=$($_.Name)=$($_.Value)" }
$dartDefinesStr = $dartDefinesList -join " "

# Integration test files
$testFiles = @(
    "mysql_integration_test.dart",
    "postgresql_integration_test.dart",
    "sqlite_integration_test.dart",
    "sqlite_nodes_context_menu_test.dart",
    "sqlserver_integration_test.dart",
    "mongodb_integration_test.dart",
    "mongodb_real_data_test.dart",
    "redis_integration_test.dart",
    "elasticsearch_integration_test.dart",
    "doris_integration_test.dart",
    "tdengine_integration_test.dart",
    "snowflake_integration_test.dart",
    "ai_panel_test.dart",
    "app_startup_test.dart",
    "export_backup_test.dart",
    "query_workflow_test.dart",
    "results_display_test.dart",
    "sidebar_tree_test.dart",
    "table_dialogs_test.dart",
    "table_management_test.dart",
    "workspace_integration_test.dart",
    "schema_diff_sync_test.dart",
    "data_sync_integration_test.dart",
    "ecommerce_to_test_db_sync_test.dart"
)

# Write header
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$headerLines = @(
    "DbMaster Integration Test Results - $timestamp",
    "==================================================================",
    "Test Server: $defineHost",
    "Total files: $($testFiles.Count)",
    "=================================================================="
)
Set-Content -Path $resultsLog -Value $headerLines -Encoding utf8

$total = 0
$passed = 0
$failed = 0
$skipped = 0

foreach ($testFile in $testFiles) {
    $total++
    $testPath = Join-Path $projectDir "integration_test\$testFile"

    if (-not (Test-Path $testPath)) {
        $msg = "SKIP: $testFile - file not found"
        Write-Host ""
        Write-Host ">>> $msg"
        Add-Content -Path $resultsLog -Value $msg -Encoding utf8
        $skipped++
        continue
    }

    Write-Host ""
    Write-Host "=========================================="
    Write-Host "[$total/$($testFiles.Count)] Running: $testFile"
    Write-Host "=========================================="

    $logFile = Join-Path $perTestLogDir ($testFile -replace '\.dart$', '.log')

    $cmdLine = "cd /d `"$projectDir`" && flutter test `"$testPath`" -d windows $dartDefinesStr --timeout=`"${timeout}s`" --reporter=expanded --no-pub"
    $startTime = Get-Date
    cmd /c $cmdLine > $logFile 2>&1
    $exitCode = $LASTEXITCODE
    $duration = (Get-Date) - $startTime

    # Parse log: find the final stats line
    $timeLine = ""
    if (Test-Path $logFile) {
        $logContent = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
        if ($logContent) {
            $m = [regex]::Match($logContent, "\+\d+[\s\S]{0,40}?-\d+")
            if ($m.Success) { $timeLine = $m.Value.Trim() }
        }
    }

    if ($exitCode -eq 0) {
        $passed++
        $status = "PASS  "
        $color = "Green"
    } else {
        $failed++
        $status = "FAIL  "
        $color = "Red"
    }

    $summary = "$status $testFile  (duration: $($duration.ToString('mm\:ss')))"
    Write-Host $summary -ForegroundColor $color
    Add-Content -Path $resultsLog -Value $summary -Encoding utf8
    if ($timeLine) {
        Add-Content -Path $resultsLog -Value "       $timeLine" -Encoding utf8
    }
}

# Performance benchmark gate section (feature 038, FR-009 / contracts C4)
# Invokes the standalone gate as a child process (its internal exit only exits
# the child, so this script's summary still runs):
# C1(strict, blocking) + C2(warn) + C3 Profile(blocking); any C1/C3 fail blocks release.
Add-Content -Path $resultsLog -Value @(
    "",
    "==================================================================",
    "Performance Benchmark Gate (contracts C4)",
    "=================================================================="
) -Encoding utf8
$benchScript = Join-Path $projectDir "scripts\run_performance_benchmarks.ps1"
Write-Host ""
Write-Host "=================================================================="
Write-Host "Performance Benchmark Gate (contracts C4) - C1/C2/C3 (slow)"
Write-Host "=================================================================="
& powershell -NoProfile -ExecutionPolicy Bypass -File $benchScript -Device windows
$benchExit = $LASTEXITCODE
if ($benchExit -eq 0) {
    Add-Content -Path $resultsLog -Value "[PASS] performance benchmark gate" -Encoding utf8
} else {
    Add-Content -Path $resultsLog -Value "[FAIL] performance benchmark gate - release blocked (contracts C4)" -Encoding utf8
    $failed++
}

# Summary
$summary = @(
    "",
    "==================================================================",
    "Total: $total, Passed: $passed, Failed: $failed, Skipped: $skipped",
    "=================================================================="
)
Add-Content -Path $resultsLog -Value $summary -Encoding utf8
foreach ($line in $summary) { Write-Host $line }
