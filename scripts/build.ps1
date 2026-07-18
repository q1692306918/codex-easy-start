param([string]$BaseUrl = 'https://plugin.yuniannian.asia')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$vendor = Join-Path $root 'vendor'
$dist = Join-Path $root 'dist'
$stage = Join-Path $env:TEMP ("CodexEasyStartBuild-" + [Guid]::NewGuid().ToString('N'))

function Write-Utf8Bom([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    $utf8Bom = New-Object Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($Path, $text, $utf8Bom)
}

try {
    if (-not (Test-Path -LiteralPath $vendor)) { throw '缺少 vendor，先运行 scripts/sync-artifacts.ps1。' }
    Remove-Item -LiteralPath $dist -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $dist -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dist 'artifacts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $dist 'skills') -Force | Out-Null
    New-Item -ItemType Directory -Path $stage -Force | Out-Null

    Copy-Item -LiteralPath (Join-Path $root 'src') -Destination $stage -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'plugins') -Destination $stage -Recurse
    Copy-Item -LiteralPath (Join-Path $root '.agents') -Destination $stage -Recurse
    Copy-Item -LiteralPath (Join-Path $root 'config') -Destination $stage -Recurse
    Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') } | ForEach-Object { Write-Utf8Bom $_.FullName }

    $coreZip = Join-Path $dist 'artifacts\easy-start-core.zip'
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $coreZip -CompressionLevel Optimal
    Copy-Item -Path (Join-Path $vendor 'artifacts\*') -Destination (Join-Path $dist 'artifacts') -Force
    Copy-Item -Path (Join-Path $vendor 'skills\*') -Destination (Join-Path $dist 'skills') -Force
    Copy-Item -LiteralPath (Join-Path $root 'install.ps1') -Destination (Join-Path $dist 'install.ps1') -Force
    Write-Utf8Bom (Join-Path $dist 'install.ps1')

    $source = Get-Content -LiteralPath (Join-Path $root 'config\artifacts.json') -Raw | ConvertFrom-Json
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($entry in $source.artifacts) {
        $path = Join-Path $dist ([string]$entry.file)
        if (-not (Test-Path -LiteralPath $path)) { throw "发布文件不存在：$($entry.file)" }
        $items.Add([ordered]@{
            id = $entry.id; version = $entry.version; url = "$BaseUrl/$($entry.file.Replace('\','/'))"
            file = $entry.file; size = (Get-Item -LiteralPath $path).Length
            sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant()
            source = $entry.source; sourceUrl = $entry.sourceUrl; license = $entry.license
            offlineReady = [bool]$entry.offlineReady
        })
    }
    $items.Add([ordered]@{
        id = 'easy-start-core'; version = '1.0.0'; url = "$BaseUrl/artifacts/easy-start-core.zip"
        file = 'artifacts/easy-start-core.zip'; size = (Get-Item $coreZip).Length
        sha256 = (Get-FileHash -Algorithm SHA256 $coreZip).Hash.ToLowerInvariant()
        source = 'q1692306918/codex-easy-start'; sourceUrl = 'https://github.com/q1692306918/codex-easy-start'
        license = 'MIT'; offlineReady = $true
    })
    $skills = Get-Content -LiteralPath (Join-Path $root 'config\skills.json') -Raw | ConvertFrom-Json
    foreach ($skill in @($skills.skills | Where-Object { $_.available -and $_.mirrorFile })) {
        $path = Join-Path $dist ([string]$skill.mirrorFile)
        if (-not (Test-Path -LiteralPath $path)) { throw "Skill 镜像不存在：$($skill.name)" }
        $items.Add([ordered]@{
            id = "skill-$($skill.id)"; version = $skill.commit; url = "$BaseUrl/$($skill.mirrorFile)"
            file = $skill.mirrorFile; size = (Get-Item $path).Length
            sha256 = (Get-FileHash -Algorithm SHA256 $path).Hash.ToLowerInvariant()
            source = $skill.source; sourceUrl = "https://github.com/$($skill.source)/commit/$($skill.commit)"
            license = $skill.license; offlineReady = $true
        })
    }
    [ordered]@{
        schemaVersion = 1
        generatedAt = [DateTime]::UtcNow.ToString('o')
        baseUrl = $BaseUrl
        artifacts = $items
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $dist 'manifest.json') -Encoding UTF8

    @"
<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Codex EasyStart</title><style>body{font:16px/1.65 system-ui;margin:40px auto;max-width:760px;padding:0 20px;color:#202124}code{background:#f3f4f6;padding:12px;display:block;overflow:auto}small{color:#666}</style><h1>Codex EasyStart</h1><p>在 Windows PowerShell 中运行：</p><code>irm https://plugin.yuniannian.asia/install.ps1 | iex</code><p><small>安装文件由境内镜像提供并校验 SHA-256。Codex 官方启动器仍可能需要连接微软服务。</small></p></html>
"@ | Set-Content -LiteralPath (Join-Path $dist 'index.html') -Encoding UTF8
    Write-Host "发布目录已生成：$dist" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
