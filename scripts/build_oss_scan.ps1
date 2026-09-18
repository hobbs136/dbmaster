# build_oss_scan.ps1 - OSS build + Pro symbol scan gate (make-or-break)
# spec 045 T009/T010 | ADR 0001
#
# Usage: pwsh scripts/build_oss_scan.ps1
# Exit: 0 = zero Pro symbols (PASS) | 1 = Pro symbols found (FAIL, list) | 2 = build failed
#
# Scans two sources: 1) flutter build --analyze-size size.json (symbol attribution)
#                    2) release exe ASCII strings (covers size.json aggregation bucket blind spots)

$ErrorActionPreference = 'Stop'
$entry = 'lib/main_oss.dart'
$outDir = 'build/oss-scan'

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host "==> flutter build windows --release --target=$entry --analyze-size" -ForegroundColor Cyan
flutter build windows --release --target=$entry --analyze-size --code-size-directory=$outDir
if ($LASTEXITCODE -ne 0) { Write-Host "BUILD FAILED (exit $LASTEXITCODE)" -ForegroundColor Red; exit 2 }

$exe = Get-ChildItem -Path 'build/windows/x64/runner/Release' -Filter 'dbmaster*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) {
  $exe = Get-ChildItem -Path 'build/windows/x64/runner/Release' -Filter '*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
}
if (-not $exe) { Write-Host "EXE NOT FOUND in build/windows/x64/runner/Release" -ForegroundColor Red; exit 2 }
Write-Host "==> exe: $($exe.FullName)" -ForegroundColor Cyan

# Pro symbol list (Phase B tripwire). Tracks real Pro class/method identifiers.
# Refined 2026-07-25 (Phase B.1):
#   - 'Ed25519' removed: matches dartssh2's SSHEd25519Key/ed25519_impl (OSS SSH,
#     free since 7cc59107) → permanent false positive. Replaced with the Pro
#     class 'TrialQuotaCrypto' (the cryptography-package Ed25519 consumer).
#   - 'AiServiceLocalizations' removed: it is core (8 adapters' Free-chat schema
#     + _checkAiQuota) — legitimately in the OSS build, not a Pro leak.
#   - 'DataSyncer' removed: matched L10n key 'dataSyncError*' (substring), not a
#     class. Replaced with the real Pro classes DataSyncService / DataSyncDialog.
$proSymbols = @(
  'PurchaseProvider', 'PurchaseService', 'ProStatusStorage', 'LicenseService',
  'LicenseVerifier', 'TrialQuotaCrypto', 'TrialQuotaService',
  'verifyLicense', 'importLicense', 'restorePurchases',
  'AiAgentService',
  'SchemaSyncService', 'DataSyncService', 'DataSyncDialog',
  'SmartImporter', 'ClusterMongoAdapter', 'ProModuleImpl',
  'trySchemaDiffSync', '_buildReplicaSetUri', '_buildShardedUri'
)

Write-Host "==> scanning size.json + exe ASCII strings" -ForegroundColor Cyan
$sizeJsons = Get-ChildItem -Path $outDir -Filter '*.json' -ErrorAction SilentlyContinue
$exeText = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($exe.FullName))

$found = [System.Collections.Generic.List[string]]::new()
foreach ($sym in $proSymbols) {
  if ($sizeJsons) {
    $hit = Select-String -Path $sizeJsons.FullName -Pattern ([regex]::Escape($sym)) -SimpleMatch -ErrorAction SilentlyContinue
    if ($hit) { $found.Add("$sym  [size.json]") | Out-Null }
  }
  if ($exeText -and ($exeText.Contains($sym))) {
    $found.Add("$sym  [exe strings]") | Out-Null
  }
}

if ($found.Count -gt 0) {
  Write-Host ""
  Write-Host "FAIL: found $($found.Count) Pro symbol(s) (Phase B backlog):" -ForegroundColor Red
  $found | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
  Write-Host ""
  Write-Host "Gate mechanism works (detects). Remaining = Phase B (migrate purchase_dialog/offline_license_section/settings_dialog to Pro)." -ForegroundColor Cyan
  exit 1
}

Write-Host ""
Write-Host "PASS: zero Pro symbols in OSS build - make-or-break cleared" -ForegroundColor Green
exit 0
