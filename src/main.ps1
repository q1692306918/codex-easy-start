param(
    [string]$BaseUrl = 'https://plugin.yuniannian.asia',
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'CodexEasyStart.psm1') -Force -DisableNameChecking

if (-not (Test-SupportedWindows)) { throw 'Codex EasyStart 仅支持 Windows 10/11。' }
$work = Join-Path $env:TEMP ("CodexEasyStartRun-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null

try {
    Write-Host "`nCodex EasyStart" -ForegroundColor White
    Write-Host '一条命令，装好 Codex 和需要的能力。' -ForegroundColor DarkGray
    $state = Get-EasyStartState
    Write-Host "`n  Codex       $(if ($state.CodexInstalled) { '已安装' } else { '未安装' })"
    Write-Host "  CC Switch   $(if ($state.CCSwitchInstalled) { '已安装' } else { '未安装' })"
    Write-Host "  插件         $(if ($state.MarketplaceInstalled) { '已安装' } else { '未安装' })"

    Write-Host "`n请选择操作："
    Write-Host '  1. 安装或配置'
    Write-Host '  2. 检查和修复'
    Write-Host '  3. 卸载 EasyStart 管理的插件'
    $mode = Read-Host '输入编号（默认 1）'
    if (-not $mode) { $mode = '1' }
    if ($mode -eq '3') { Remove-EasyStart; return }
    if ($DryRun) { Write-Host 'DryRun 完成'; return }

    $manifest = Get-RemoteManifest $BaseUrl
    if (-not $state.CodexInstalled) { Install-CodexDesktop $manifest $work | Out-Null }

    Write-Host "`n请选择需要的能力（可多选，直接回车跳过）："
    Write-Host '  1. 使用 DeepSeek'
    Write-Host '  2. 识别图片和扫描件'
    Write-Host '  3. 增强法律工作能力'
    $choices = Read-Choices (Read-Host '输入编号，例如 1,2') @(1, 2, 3)
    $plugins = @()
    if ($choices -contains 1) { Configure-DeepSeek $manifest $work }
    if ($choices -contains 2) { if (Configure-Ocr $PackageRoot $plugins) { $plugins += 'codex-vision-ocr' } }
    if ($choices -contains 3) {
        if (Configure-PKULaw $PackageRoot $plugins) { $plugins += 'codex-legal-tools' }
        Configure-Skills $manifest $PackageRoot $work
    }

    Write-Host "`n完成" -ForegroundColor Green
    $final = Get-EasyStartState
    Write-Host "  Codex       $(if ($final.CodexInstalled) { '已安装' } else { '需要处理' })"
    Write-Host "  CC Switch   $(if ($final.CCSwitchInstalled) { '已安装' } else { '未选择' })"
    Write-Host "  插件         $(if ($final.MarketplaceInstalled) { '已安装，重启 Codex 生效' } else { '未选择' })"
    if ($final.CodexInstalled -and (Read-Host '现在打开 Codex？[Y/n]') -notmatch '^[Nn]') {
        Start-Process explorer.exe -ArgumentList 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App' -ErrorAction SilentlyContinue
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
