# Dbmaster Windows Build Script

param(
    [switch]$Clean,      # 向后兼容：现在 clean 是默认行为，无需显式传
    [switch]$NoClean,    # 跳过 flutter clean，用于快速增量迭代（有陈旧构建风险）
    [switch]$Debug,      # 构建 Debug 版（默认 Release）
    [switch]$Direct,     # 直销构建，启用 DIRECT_BUILD（离线授权 UI 出现）
    [switch]$SkipServer  # 跳过 cargo 构建 embedded server（仅客户端构建）
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Dbmaster Windows Build Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir

$BuildMode = if ($Debug) { "Debug" } else { "Release" }
$BuildType = if ($Debug) { "--debug" } else { "--release" }

Push-Location $ProjectDir

try {
    # ── [1/4] Clean / Prepare ──
    if ($NoClean) {
        Write-Host "`n[1/4] Skipping clean (-NoClean, 增量构建, 有陈旧风险)..." -ForegroundColor Yellow
        flutter pub get
    } else {
        # 默认始终 flutter clean：防止 AOT 快照/构建缓存陈旧导致源码改动未生效。
        # 尤其 --release：旧 kernel/AOT snapshot 不会因源码小改自动失效，
        # 表现为「改了代码但行为没变」。要快速增量迭代可传 -NoClean（自负陈旧风险）。
        Write-Host "`n[1/4] Cleaning (默认, 防止陈旧构建)..." -ForegroundColor Yellow
        flutter clean
        flutter pub get
    }

    # ── [2/4] Build ──
    # 直销构建追加 DIRECT_BUILD 编译期常量（参数数组拼接，避免空串参数）
    # U15：APP_VERSION 取 git tag 注入（遥测/更新检查共用；取不到 = dev）
    $AppVersion = (git describe --tags --abbrev=0 2>$null)
    if (-not $AppVersion) { $AppVersion = "dev" }
    Write-Host "APP_VERSION: $AppVersion"
    $BuildArgs = @("build", "windows", $BuildType, "--dart-define=APP_VERSION=$AppVersion")
    if ($Direct) { $BuildArgs += "--dart-define=DIRECT_BUILD=true" }
    $BuildLabel = if ($Direct) { "$BuildMode · Direct" } else { $BuildMode }
    Write-Host "`n[2/4] Building Windows app ($BuildLabel)..." -ForegroundColor Yellow
    flutter @BuildArgs

    $exePath = "build/windows/x64/runner/$BuildMode/dbmaster.exe"
    if (-not (Test-Path $exePath)) {
        throw "构建未生成预期的可执行文件: $exePath"
    }

    # ── [3/4] Copy artifacts to dist\<Mode>\ ──
    # 复制整个构建目录（exe + DLLs + data/，运行所需全集）。
    # Release 与 Debug 各占 dist\<Mode>\ 子目录，互不覆盖（两种模式可共存）。
    Write-Host "`n[3/4] Copying $BuildMode artifacts to dist\" -ForegroundColor Yellow
    $buildOutDir = "build\windows\x64\runner\$BuildMode"
    $distDir = "dist"
    # 直销构建产物输出到独立目录（<Mode>-direct），与 MAS-clean 构建隔离
    $distModeName = if ($Direct) { "$BuildMode-direct" } else { $BuildMode }
    $distModeDir = Join-Path $distDir $distModeName
    if (-not (Test-Path $distDir)) {
        New-Item -ItemType Directory -Path $distDir | Out-Null
    }
    # 先清空目标子目录，确保干净复制（不残留旧文件）
    if (Test-Path $distModeDir) {
        Remove-Item $distModeDir -Recurse -Force
    }
    # 复制到 $distModeDir（含 -direct 后缀），而非 $distDir——后者会用源文件夹
    # 名 Release 落位，导致直销/普通构建互相覆盖到 dist\Release。$distModeDir 已清空，
    # Copy-Item 会以该名新建。
    Copy-Item -Path $buildOutDir -Destination $distModeDir -Recurse -Force
    Write-Host "  Copied $BuildMode -> $distModeDir" -ForegroundColor White

    # ── [3.5/4] Build + copy the embedded server binary (ADR-0003 S2b) ──
    # The desktop client spawns dbmaster-server.exe in --embedded mode at
    # startup. The binary MUST sit beside dbmaster.exe (the auto-detect in
    # EmbeddedServerService.locateBinary looks next to Platform.resolvedExecutable).
    # Skip with -SkipServer to do a client-only build (e.g. when the Rust
    # toolchain isn't installed on this machine).
    if (-not $SkipServer) {
        Write-Host "`n[3.5/4] Building embedded server (cargo)..." -ForegroundColor Yellow
        $ServerDir = Join-Path $ProjectDir "..\dbmaster-server"
        $ServerManifest = Join-Path $ServerDir "Cargo.toml"
        if (-not (Test-Path $ServerManifest)) {
            Write-Host "  $ServerManifest not found; skipping server binary (client-only build)." -ForegroundColor Yellow
        } else {
            $CargoMode = if ($Debug) { "debug" } else { "release" }
            # cargo build (release unless -Debug). Reuses cargo's incremental
            # cache, so this is fast when the server is already built.
            & cargo build --manifest-path $ServerManifest $(if (-not $Debug) { "--release" })
            if ($LASTEXITCODE -ne 0) { throw "cargo build failed (exit $LASTEXITCODE)" }
            $ServerExe = Join-Path $ServerDir "target\$CargoMode\dbmaster-server.exe"
            if (-not (Test-Path $ServerExe)) {
                throw "cargo build did not produce expected binary: $ServerExe"
            }
            Copy-Item -Path $ServerExe -Destination (Join-Path $distModeDir "dbmaster-server.exe") -Force
            Write-Host "  Copied dbmaster-server.exe ($CargoMode) -> $distModeDir" -ForegroundColor White
        }
    } else {
        Write-Host "`n[3.5/4] Skipping embedded server build (-SkipServer)" -ForegroundColor Yellow
    }

    # ── [3.6/4] MaterialIcons 字体子集（#31 T15，fail-open）──
    # Flutter 3.41 Windows 桌面构建的 --tree-shake-icons 实证不生效（T01），
    # 产物里的 MaterialIcons-Regular.otf 是 SDK 原版直拷（1.57MB）。这里在
    # dist 产物上做后处理子集化（扫描依赖闭包 + SDK 框架库的 Icons 引用，
    # pyftsubset 抽字形）。工具内部 fail-open：无 Python/fontTools 时保留
    # 原版字体仅打警告，构建不因此失败。
    Write-Host "`n[3.6/4] Subsetting MaterialIcons font (fail-open)..." -ForegroundColor Yellow
    try {
        & dart run tool/subset_material_icons.dart --dist "$distModeDir"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  subset tool exited $LASTEXITCODE; keeping original font." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  dart run failed ($_); keeping original font (install Python 3 + fonttools to enable)." -ForegroundColor Yellow
    }

    # ── [4/4] Output ──
    Write-Host "`n[4/4] Output:" -ForegroundColor Yellow
    Write-Host "  - Build: $exePath" -ForegroundColor White
    Write-Host "  - Dist:  $distModeDir\dbmaster.exe" -ForegroundColor Green
    if ((-not $SkipServer) -and (Test-Path (Join-Path $distModeDir "dbmaster-server.exe"))) {
        Write-Host "  - Dist:  $distModeDir\dbmaster-server.exe (embedded)" -ForegroundColor Green
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Build succeeded!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan

} catch {
    Write-Host "`nBuild failed: $_" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
