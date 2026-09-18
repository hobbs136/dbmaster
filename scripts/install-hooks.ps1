# 启用项目级 git hooks（core.hooksPath 指向仓库内 git-hooks/，入库可共享）。
# 运行一次即可：.\scripts\install-hooks.ps1
# 当前提供 pre-commit：拦截含未清除 CHANGE: 标记的提交。
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    git config core.hooksPath 'git-hooks'
    Write-Host '✅ git hooks 已启用：core.hooksPath = git-hooks' -ForegroundColor Green
    Write-Host '   - pre-commit：拦截未清除的 CHANGE: 变更标记' -ForegroundColor Green
    Write-Host '   卸载：git config --unset core.hooksPath' -ForegroundColor DarkGray
}
finally {
    Pop-Location
}
