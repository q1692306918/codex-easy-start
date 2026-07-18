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

function Write-Utf8NoBom([string]$Path) {
    $text = [IO.File]::ReadAllText($Path)
    [IO.File]::WriteAllText($Path, $text, (New-Object Text.UTF8Encoding($false)))
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
    $source = Get-Content -LiteralPath (Join-Path $root 'config\artifacts.json') -Raw | ConvertFrom-Json
    foreach ($entry in $source.artifacts) {
        $sourcePath = Join-Path $vendor ([string]$entry.file)
        $destinationPath = Join-Path $dist ([string]$entry.file)
        if (-not (Test-Path -LiteralPath $sourcePath)) { throw "镜像文件不存在：$($entry.file)" }
        New-Item -ItemType Directory -Path (Split-Path -Parent $destinationPath) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
    }
    Copy-Item -Path (Join-Path $vendor 'skills\*') -Destination (Join-Path $dist 'skills') -Force
    Copy-Item -LiteralPath (Join-Path $root 'install.ps1') -Destination (Join-Path $dist 'install.ps1') -Force
    Write-Utf8NoBom (Join-Path $dist 'install.ps1')

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
        id = 'easy-start-core'; version = '1.0.3'; url = "$BaseUrl/artifacts/easy-start-core.zip"
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
    $manifestJson = [ordered]@{
        schemaVersion = 1
        generatedAt = [DateTime]::UtcNow.ToString('o')
        baseUrl = $BaseUrl
        artifacts = $items
    } | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText((Join-Path $dist 'manifest.json'), $manifestJson, (New-Object Text.UTF8Encoding($false)))

    @"
<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Codex EasyStart</title><style>body{font:16px/1.65 system-ui;margin:40px auto;max-width:760px;padding:0 20px;color:#202124}code{background:#f3f4f6;padding:12px;display:block;overflow:auto}small{color:#666}</style><h1>Codex EasyStart</h1><p>在 Windows PowerShell 中运行：</p><code>irm https://plugin.yuniannian.asia/install.ps1 | iex</code><p><small>可镜像文件由境内域名提供并校验 SHA-256。Codex 已改名为 ChatGPT；安装仍需连接 Microsoft Store。</small></p></html>
"@ | Set-Content -LiteralPath (Join-Path $dist 'index.html') -Encoding UTF8

    $installBytes = [IO.File]::ReadAllBytes((Join-Path $dist 'install.ps1'))
    if ($installBytes.Length -ge 3 -and $installBytes[0] -eq 0xEF -and $installBytes[1] -eq 0xBB -and $installBytes[2] -eq 0xBF) {
        throw '发布入口 install.ps1 不能包含 UTF-8 BOM，否则 irm | iex 会把 BOM 识别为命令字符。'
    }
    Get-ChildItem -LiteralPath (Join-Path $dist 'skills') -Filter '*.zip' -File | ForEach-Object {
        $entries = @(& tar.exe -tf $_.FullName)
        $skillEntries = @($entries | Where-Object { $_ -match '/SKILL\.md$' })
        if ($LASTEXITCODE -ne 0 -or $skillEntries.Count -ne 1) {
            throw "Skill 发布包无效：$($_.Name)"
        }
        $verifyDirectory = Join-Path $stage ("verify-" + $_.BaseName)
        New-Item -ItemType Directory -Path $verifyDirectory -Force | Out-Null
        & tar.exe -xf $_.FullName -C $verifyDirectory
        if ($LASTEXITCODE -ne 0 -or -not (Get-ChildItem -LiteralPath $verifyDirectory -Filter 'SKILL.md' -Recurse -File)) {
            throw "Skill 发布包无法通过 tar.exe 解压：$($_.Name)"
        }
    }
    Write-Host "发布目录已生成：$dist" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
}
