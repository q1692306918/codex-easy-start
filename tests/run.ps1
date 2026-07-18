$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'src\CodexEasyStart.psm1') -Force -DisableNameChecking
$failed = 0

function Assert([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "PASS $Message" -ForegroundColor Green }
    else { Write-Host "FAIL $Message" -ForegroundColor Red; $script:failed++ }
}

$choices = @(Read-Choices '1, 2，3 2' @(1,2,3))
Assert ($choices.Count -eq 3) '多选解析并去重'
Assert ($choices[0] -eq 1 -and $choices[2] -eq 3) '多选保持顺序'
Assert (@(Read-Choices '' @(1,2,3)).Count -eq 0) '空输入表示跳过'
$invalidFailed = $false
try { Read-Choices '4' @(1,2,3) | Out-Null } catch { $invalidFailed = $true }
Assert $invalidFailed '非法选项被拒绝'
Assert (Test-SupportedWindows) 'Windows 版本检测'

$ranges = @(Get-DownloadRanges 10 4)
Assert ($ranges.Count -eq 4) '并行下载拆分为四段'
Assert ($ranges[0].Start -eq 0 -and $ranges[-1].End -eq 9) '下载分段完整覆盖文件'
Assert ((($ranges | Measure-Object Length -Sum).Sum) -eq 10) '下载分段没有重复或遗漏'

$fixture = Join-Path $env:TEMP ("ces-skill-test-" + [Guid]::NewGuid().ToString('N'))
$fixtureSource = Join-Path $fixture 'source\upstream-name'
$fixtureTarget = Join-Path $fixture 'target\stable-skill'
try {
    New-Item -ItemType Directory -Path $fixtureSource -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $fixtureSource 'SKILL.md'), '# fixture')
    $fixtureZip = Join-Path $fixture 'fixture.zip'
    & tar.exe -a -cf $fixtureZip -C (Join-Path $fixture 'source') 'upstream-name'
    Expand-SingleSkillArchive -Zip $fixtureZip -Target $fixtureTarget -Name 'stable-skill'
    Assert (Test-Path -LiteralPath (Join-Path $fixtureTarget 'SKILL.md')) '单 Skill 绕过外层目录安装到稳定目录'
} finally {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}

$artifacts = Get-Content -LiteralPath (Join-Path $root 'config\artifacts.json') -Raw | ConvertFrom-Json
Assert ($artifacts.baseUrl -eq 'https://plugin.yuniannian.asia') '镜像域名正确'
Assert (@($artifacts.artifacts | Where-Object { -not $_.id -or -not $_.file }).Count -eq 0) '制品字段完整'
$misleadingCodexArtifacts = @($artifacts.artifacts | Where-Object {
    $_.id -match 'codex' -and (($_.file + ' ' + $_.sourceUrl) -match 'ChatGPT|9PLM9XGG6VKS')
})
Assert ($misleadingCodexArtifacts.Count -eq 0) 'Codex 制品不再冒充 ChatGPT 安装器'
$moduleText = Get-Content -LiteralPath (Join-Path $root 'src\CodexEasyStart.psm1') -Raw
Assert ($moduleText -notmatch 'ChatGPT-Installer|codex-store-bootstrapper') 'Codex 安装流程不再执行 ChatGPT Store Installer'

$skills = Get-Content -LiteralPath (Join-Path $root 'config\skills.json') -Raw | ConvertFrom-Json
Assert (@($skills.skills | Where-Object { $_.available -and -not $_.license }).Count -eq 0) '公开镜像 Skill 均有许可证'
Assert (@($skills.skills | Where-Object { -not $_.available -and $_.mirrorFile }).Count -eq 0) '不可镜像 Skill 不暴露下载文件'

Get-ChildItem -LiteralPath (Join-Path $root 'plugins') -Filter '*.json' -Recurse | ForEach-Object {
    try { [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json | Out-Null; Assert $true "JSON 有效：$($_.Name)" }
    catch { Assert $false "JSON 无效：$($_.FullName)" }
}

if ($failed -gt 0) { throw "$failed 项测试失败。" }
Write-Host '全部测试通过。' -ForegroundColor Green
