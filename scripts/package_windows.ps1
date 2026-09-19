# Dbmaster Windows Package Script
#
# 将 build_windows.ps1 的产物 dist\<Mode>\ 打成 GitHub Releases 分发用
# portable zip：dbmaster-windows-<版本>.zip + 同名 .sha256（sha256sum -c 兼容）。
#
# 已知且有意为之（勿改 build_windows.ps1 对齐）：工作树 dirty 时，本脚本
# 产出的 zip 名带 -dev.<yyyyMMddHHmm> 后缀，而 exe 内 APP_VERSION（build
# 注入）是纯 tag。两者不同是设计选择——zip 名要能区分同一 tag 下的本地脏构建。

param(
    [string]$Version,    # 覆盖版本基名（仅允许字母/数字/. - _；默认取 git tag，取不到 = dev）
    [switch]$SkipBuild,  # 跳过构建，直接打包现有 dist\<Mode>\（不保证新鲜，自负其责）
    [switch]$Debug       # 打包 Debug 产物（默认 Release）
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Dbmaster Windows Package Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$BuildScript = Join-Path $ScriptDir "build_windows.ps1"
$BuildMode = if ($Debug) { "Debug" } else { "Release" }
$DistModeDir = Join-Path $ProjectDir "dist\$BuildMode"
$StagingRoot = Join-Path $ProjectDir "dist\package-staging"

Push-Location $ProjectDir

try {
    # ── [1/4] 构建（或跳过）──
    if ($SkipBuild) {
        Write-Host ""
        Write-Host "[1/4] Skipping build (-SkipBuild)" -ForegroundColor Yellow
        Write-Host "  警告：-SkipBuild 不保证 dist\$BuildMode\ 是最新构建产物，陈旧风险自负！" -ForegroundColor Yellow
    } else {
        Write-Host "`n[1/4] Building Windows app ($BuildMode)..." -ForegroundColor Yellow
        if ($Debug) { & $BuildScript -Debug } else { & $BuildScript }
        if ($LASTEXITCODE -ne 0) {
            throw "build_windows.ps1 失败 (exit $LASTEXITCODE)"
        }
    }

    # ── [2/4] 版本推导 + 产物清单校验（fail-hard）──
    # 版本基名：-Version > git tag（取不到 = dev）。只认 describe 的「最近可达
    # tag」；严禁 git tag 枚举取最大（本地旧 tag 非 HEAD 祖先时会错取）。
    $BaseName = $Version
    if (-not $BaseName) {
        $BaseName = (git describe --tags --abbrev=0 2>$null)
        if (-not $BaseName) { $BaseName = "dev" }
    }
    if ($BaseName -notmatch '^[A-Za-z0-9._-]+$') {
        throw "版本串含非法字符: '$BaseName'（仅允许字母/数字/. - _）"
    }
    # dirty → 追加 -dev.<时间戳>；clean → 纯基名。与 exe 内 APP_VERSION 的
    # 差异是有意为之，见文件头注释。
    $Dirty = @((git status --porcelain 2>$null)).Count -gt 0
    $VersionString = if ($Dirty) { "$BaseName-dev.$(Get-Date -Format 'yyyyMMddHHmm')" } else { $BaseName }
    $PkgName = "dbmaster-windows-$VersionString"
    Write-Host "`n[2/4] Version: $VersionString" -ForegroundColor Yellow

    # 产物清单校验：任一缺失必须失败，且一次性打印完整缺失清单（不只报第一个）。
    # dbmaster-server.exe 连 -SkipBuild 也不豁免——embedded 免费档核心特性。
    $missing = @()
    if (-not (Test-Path -LiteralPath $DistModeDir -PathType Container)) {
        if ($SkipBuild) {
            throw "dist\$BuildMode\ 不存在。请先构建（去掉 -SkipBuild 全量运行，或先单独运行 build_windows.ps1）。"
        }
        throw "构建后未找到产物目录: dist\$BuildMode\"
    }
    foreach ($rel in @("dbmaster.exe", "dbmaster-server.exe", "flutter_windows.dll", "data\icudtl.dat")) {
        if (-not (Test-Path -LiteralPath (Join-Path $DistModeDir $rel) -PathType Leaf)) {
            $missing += $rel
        }
    }
    # 模式项：Release 是 AOT 快照 app.so；Debug 是 JIT 内核 kernel_blob.bin
    $ModeItem = if ($BuildMode -eq "Release") { "data\app.so" } else { "data\kernel_blob.bin" }
    if (-not (Test-Path -LiteralPath (Join-Path $DistModeDir $ModeItem) -PathType Leaf)) {
        $missing += $ModeItem
    }
    # flutter_assets 目录必须存在且非空
    $AssetsDir = Join-Path $DistModeDir "data\flutter_assets"
    if (-not (Test-Path -LiteralPath $AssetsDir -PathType Container) -or
        @(Get-ChildItem -LiteralPath $AssetsDir -Recurse -File).Count -eq 0) {
        $missing += "data\flutter_assets\（目录缺失或为空）"
    }
    # 插件 DLL 至少 5 个（flutter_windows.dll 不计入 *_plugin.dll 通配）
    $PluginDlls = @(Get-ChildItem -LiteralPath $DistModeDir -Filter "*_plugin.dll" -File)
    if ($PluginDlls.Count -lt 5) {
        $missing += "*_plugin.dll（仅找到 $($PluginDlls.Count) 个，要求至少 5 个）"
    }
    # 打包输入：仓库根三件指名文件（缺一不可，进包的合规文件）
    foreach ($rel in @("LICENSE", "NOTICE", "README.md")) {
        if (-not (Test-Path -LiteralPath (Join-Path $ProjectDir $rel) -PathType Leaf)) {
            $missing += "<仓库根>\$rel"
        }
    }
    if ($missing.Count -gt 0) {
        Write-Host "`n产物清单校验失败，缺失 $($missing.Count) 项：" -ForegroundColor Red
        foreach ($m in $missing) { Write-Host "  - $m" -ForegroundColor Red }
        throw "产物清单校验失败（见上方完整缺失清单）"
    }
    Write-Host "  清单校验通过（含 $($PluginDlls.Count) 个插件 DLL）" -ForegroundColor White

    # ── [3/4] 组装 staging ──
    # 来源仅两种：dist\<Mode>\ 全目录复制 + 仓库根【指名】复制三件文件。
    # 禁止对仓库根做任何枚举/通配复制——仓库根物理存在 private_key.hex 等
    # 敏感文件，这是安全红线。
    Write-Host "`n[3/4] Staging -> dist\package-staging\$PkgName\" -ForegroundColor Yellow
    $PkgDir = Join-Path $StagingRoot $PkgName
    if (Test-Path -LiteralPath $StagingRoot) {
        Remove-Item -LiteralPath $StagingRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Path $StagingRoot -Force | Out-Null
    # 目标目录不存在时 Copy-Item 以源目录「内容」落位到 PkgDir
    Copy-Item -LiteralPath $DistModeDir -Destination $PkgDir -Recurse -Force
    foreach ($rel in @("LICENSE", "NOTICE", "README.md")) {
        Copy-Item -LiteralPath (Join-Path $ProjectDir $rel) -Destination $PkgDir -Force
    }
    Write-Host "  dist\$BuildMode\ + LICENSE + NOTICE + README.md -> $PkgDir" -ForegroundColor White

    # ── [4/4] 压缩 + SHA256 + 输出 ──
    Write-Host "`n[4/4] Compressing (Optimal)..." -ForegroundColor Yellow
    $ZipName = "$PkgName.zip"
    $ZipPath = Join-Path (Join-Path $ProjectDir "dist") $ZipName
    # 幂等：同名 zip / .sha256 已存在 → 删除重建
    foreach ($old in @($ZipPath, "$ZipPath.sha256")) {
        if (Test-Path -LiteralPath $old) { Remove-Item -LiteralPath $old -Force }
    }
    # -Path 指向 staging 里的版本化文件夹 → zip 顶层即该文件夹
    Compress-Archive -Path $PkgDir -DestinationPath $ZipPath -CompressionLevel Optimal
    # .sha256 内容：<小写hex> *<zip文件名>，LF 结尾（sha256sum -c binary 模式兼容）
    $Hash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText("$ZipPath.sha256", "$Hash *$ZipName`n")

    $SizeMiB = [math]::Round((Get-Item -LiteralPath $ZipPath).Length / 1MB, 2)
    $FileCount = (Get-ChildItem -LiteralPath $PkgDir -Recurse -File).Count
    Write-Host "`n[4/4] Output:" -ForegroundColor Yellow
    Write-Host "  - Zip:    $ZipPath" -ForegroundColor Green
    Write-Host "  - Size:   $SizeMiB MiB" -ForegroundColor White
    Write-Host "  - SHA256: $Hash" -ForegroundColor White
    Write-Host "  - Files:  $FileCount 个（同名 .sha256 校验和已生成）" -ForegroundColor White

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Package succeeded!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan

} catch {
    Write-Host "`nPackage failed: $_" -ForegroundColor Red
    exit 1
} finally {
    # staging 是临时产物：成功/失败一律清理（SilentlyContinue：清理失败不掩盖
    # 主结果，残留会被下次运行开头重建时清掉）
    if (Test-Path -LiteralPath $StagingRoot) {
        Remove-Item -LiteralPath $StagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Pop-Location
}
