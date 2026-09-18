# MySQL Studio - Debug Run Script
# Version: 0.0.1

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "MySQL Studio - Debug Build" -ForegroundColor Cyan
Write-Host "Version: 0.0.1" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/3] Cleaning previous build..." -ForegroundColor Yellow
flutter clean

Write-Host ""
Write-Host "[2/3] Getting dependencies..." -ForegroundColor Yellow
flutter pub get

Write-Host ""
Write-Host "[3/3] Running debug build..." -ForegroundColor Yellow
flutter run -d windows

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
