# ============================================================================
# Performance benchmark gate - Windows PowerShell (feature 038, FR-009 / C4)
# Equivalent to scripts/run_performance_benchmarks.sh:
#   [1/3] C1 adapter benchmarks (real DB, strict)   -- blocking
#   [2/3] C2 UI render benchmark (Debug proxy, strict) -- warn only (dev regression line)
#   [3/3] C3 Profile frame benchmark (acceptance)   -- blocking
#
# Usage: powershell -ExecutionPolicy Bypass -File scripts\run_performance_benchmarks.ps1
# Env:   real test DB via DBMASTER_* env vars (host: DBMASTER_TEST_HOST)
# Device: default windows (spec acceptance platform); override via -Device
# NOTE: kept ASCII-only for Windows PowerShell 5.1 (no BOM) compatibility.
# ============================================================================

param(
    [string]$Device = "windows"
)

$ErrorActionPreference = "Continue"
$projectDir = "C:\Users\hobbs\Projects\dbmaster\dbmaster-flutter"
Set-Location $projectDir

# Open-source stripping: benchmarks need real DB params --
# DBMASTER_TEST_HOST (injected as every *_HOST define) + other DBMASTER_*
# env vars (user/password) forwarded verbatim.
$defineHost = $env:DBMASTER_TEST_HOST
if (-not $defineHost) {
    Write-Error "DBMASTER_TEST_HOST is required (test DB host). Credentials are forwarded from DBMASTER_* env vars."
    exit 1
}
$dartDefines = @()
foreach ($db in @("MYSQL", "PG", "MONGO", "REDIS")) {
    $dartDefines += "--dart-define=DBMASTER_${db}_HOST=$defineHost"
}
Get-ChildItem env: |
    Where-Object { $_.Name -like "DBMASTER_*" -and $_.Name -ne "DBMASTER_TEST_HOST" } |
    ForEach-Object { $dartDefines += "--dart-define=$($_.Name)=$($_.Value)" }

$failed = 0
$warned = 0

Write-Host "================================================================"
Write-Host " [1/3] Adapter benchmarks (real DB strict, contracts C1)"
Write-Host "================================================================"
foreach ($f in @("mysql", "postgresql", "redis", "mongodb")) {
    Write-Host ""
    Write-Host "----- $f performance benchmark (strict) -----"
    $proc = Start-Process -FilePath "flutter" `
        -ArgumentList (@("test", "integration_test/${f}_performance_benchmark_test.dart", "-d", $Device, "--dart-define=DBMASTER_BENCH_STRICT=1") + $dartDefines) `
        -NoNewWindow -PassThru -Wait
    if ($proc.ExitCode -eq 0) {
        Write-Host "[PASS] $f"
    } else {
        Write-Host "[FAIL] $f -- blocks release (contracts C4)"
        $failed = 1
    }
}

Write-Host ""
Write-Host "================================================================"
Write-Host " [2/3] UI render benchmark (Debug proxy, contracts C2) -- warn only"
Write-Host "================================================================"
# Debug build layout-cost proxy, not acceptance; warn on exceed, do not set failed
$proc = Start-Process -FilePath "flutter" `
    -ArgumentList @("test", "test/organisms/results/virtualized_data_table_benchmark_test.dart", "--dart-define=DBMASTER_BENCH_STRICT=1") `
    -NoNewWindow -PassThru -Wait
if ($proc.ExitCode -eq 0) {
    Write-Host "[PASS] C2 Debug proxy"
} else {
    Write-Host "[WARN] C2 Debug proxy exceeded -- warn only, does not block (contracts C4)"
    $warned = 1
}

Write-Host ""
Write-Host "================================================================"
Write-Host " [3/3] Profile acceptance benchmark (contracts C3 + PG P2, research D3)"
Write-Host "       (slow Profile build, please wait)"
Write-Host "================================================================"
# Frame acceptance (scroll/jump <=33ms, first frame <=380ms)
$proc = Start-Process -FilePath "flutter" `
    -ArgumentList @("drive", "--profile", "-d", $Device, `
        "--driver=test_driver/integration_test.dart", `
        "--target=integration_test/results_scroll_frame_benchmark_test.dart", `
        "--dart-define=DBMASTER_BENCH_STRICT=1") `
    -NoNewWindow -PassThru -Wait
if ($proc.ExitCode -eq 0) {
    Write-Host "[PASS] scroll frame profile"
} else {
    Write-Host "[FAIL] scroll frame profile -- blocks release (contracts C4)"
    $failed = 1
}

# PG large result fetch acceptance (P2 <=1s, Profile mode)
$proc = Start-Process -FilePath "flutter" `
    -ArgumentList @("drive", "--profile", "-d", $Device, `
        "--driver=test_driver/integration_test.dart", `
        "--target=integration_test/postgresql_performance_benchmark_test.dart") `
    -NoNewWindow -PassThru -Wait
if ($proc.ExitCode -eq 0) {
    Write-Host "[PASS] PG profile benchmark (verify P2 <= 1000ms in output)"
} else {
    Write-Host "[FAIL] PG profile benchmark -- blocks release (contracts C4)"
    $failed = 1
}

Write-Host ""
if ($failed -ne 0) {
    Write-Host "[FAIL] Performance gate NOT passed (C1/C3 exceeded), release blocked (contracts C4)"
    exit 1
}
if ($warned -ne 0) {
    Write-Host "[WARN] Performance gate passed, but C2 Debug proxy warned (does not block)"
    exit 0
}
Write-Host "[PASS] Performance gate all passed"
