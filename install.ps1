$ErrorActionPreference = 'Stop'
$BaseUrl = 'https://plugin.yuniannian.asia'
$work = Join-Path $env:TEMP ("CodexEasyStart-" + [Guid]::NewGuid().ToString('N'))

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    Write-Host '正在获取 Codex EasyStart...' -ForegroundColor Cyan
    $manifest = Invoke-RestMethod -UseBasicParsing -Uri "$BaseUrl/manifest.json"
    $artifact = $manifest.artifacts | Where-Object { $_.id -eq 'easy-start-core' } | Select-Object -First 1
    if (-not $artifact) { throw '发布清单缺少 easy-start-core。' }
    $zip = Join-Path $work 'easy-start-core.zip'
    Invoke-WebRequest -UseBasicParsing -Uri $artifact.url -OutFile $zip
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $zip).Hash.ToLowerInvariant()
    if ($actual -ne $artifact.sha256.ToLowerInvariant()) { throw '安装包校验失败，已停止执行。' }
    Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $work 'app') -Force
    & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $work 'app\src\main.ps1') -BaseUrl $BaseUrl -PackageRoot (Join-Path $work 'app')
    if ($LASTEXITCODE -ne 0) { throw "安装向导退出，代码 $LASTEXITCODE。" }
} catch {
    Write-Host "安装失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host '可重新运行同一条命令进行修复。'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

