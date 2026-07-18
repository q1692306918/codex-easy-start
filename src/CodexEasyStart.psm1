Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) { Write-Host "`n$Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "  [完成] $Text" -ForegroundColor Green }
function Write-Skip([string]$Text) { Write-Host "  [跳过] $Text" -ForegroundColor DarkGray }
function Write-Warn([string]$Text) { Write-Host "  [注意] $Text" -ForegroundColor Yellow }

function Test-SupportedWindows {
    return ($env:OS -eq 'Windows_NT' -and [Environment]::OSVersion.Version.Major -ge 10)
}

function Get-EasyStartState {
    $codex = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue
    $ccCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'CC-Switch\cc-switch.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\CC Switch\cc-switch.exe'),
        (Join-Path $env:ProgramFiles 'CC Switch\cc-switch.exe')
    )
    $cc = $ccCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    return [pscustomobject]@{
        CodexInstalled = [bool]$codex
        CodexVersion = if ($codex) { [string]$codex.Version } else { $null }
        CCSwitchInstalled = [bool]$cc
        CCSwitchPath = $cc
        MarketplaceInstalled = Test-Path -LiteralPath (Join-Path $HOME '.codex\marketplaces\codex-easy-start')
    }
}

function Read-Choices([string]$InputText, [int[]]$Allowed) {
    if ([string]::IsNullOrWhiteSpace($InputText)) { return @() }
    $result = New-Object System.Collections.Generic.List[int]
    foreach ($token in ($InputText -split '[,，\s]+')) {
        if (-not $token) { continue }
        $value = 0
        if (-not [int]::TryParse($token, [ref]$value) -or $Allowed -notcontains $value) {
            throw "无法识别选项：$token"
        }
        if (-not $result.Contains($value)) { $result.Add($value) }
    }
    return $result.ToArray()
}

function Read-Secret([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Get-RemoteManifest([string]$BaseUrl) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    return Invoke-RestMethod -UseBasicParsing -Uri "$BaseUrl/manifest.json"
}

function Save-Artifact($Manifest, [string]$Id, [string]$Destination) {
    $artifact = $Manifest.artifacts | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $artifact) { throw "镜像中没有制品：$Id" }
    $parent = Split-Path -Parent $Destination
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Invoke-WebRequest -UseBasicParsing -Uri $artifact.url -OutFile $Destination
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Destination).Hash.ToLowerInvariant()
    if ($actual -ne ([string]$artifact.sha256).ToLowerInvariant()) {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        throw "制品校验失败：$Id"
    }
    return $artifact
}

function Install-CodexDesktop($Manifest, [string]$WorkDir) {
    $state = Get-EasyStartState
    if ($state.CodexInstalled) { Write-Ok "Codex 已安装（$($state.CodexVersion)）"; return $true }
    Write-Warn 'Codex 完整离线包暂不可公开镜像；接下来运行的是官方微软安装入口，可能需要访问微软服务。'
    $answer = Read-Host '继续打开 Codex 官方安装器？[Y/n]'
    if ($answer -match '^[Nn]') { Write-Skip 'Codex'; return $false }
    $path = Join-Path $WorkDir 'ChatGPT-Installer.exe'
    Save-Artifact $Manifest 'codex-store-bootstrapper' $path | Out-Null
    $signature = Get-AuthenticodeSignature -LiteralPath $path
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw 'Codex 官方启动器的 Microsoft 签名无效，已停止执行。'
    }
    Start-Process -FilePath $path -Wait
    $installed = (Get-EasyStartState).CodexInstalled
    if ($installed) { Write-Ok 'Codex 已安装' } else { Write-Warn '尚未检测到 Codex，可稍后再次运行 EasyStart 检查。' }
    return $installed
}

function Install-CCSwitch($Manifest, [string]$WorkDir) {
    $state = Get-EasyStartState
    if ($state.CCSwitchInstalled) { Write-Ok 'CC Switch 已安装'; return $true }
    $arch = $env:PROCESSOR_ARCHITECTURE
    $id = if ($arch -eq 'ARM64') { 'cc-switch-arm64' } else { 'cc-switch-x64' }
    $msi = Join-Path $WorkDir 'CC-Switch.msi'
    Save-Artifact $Manifest $id $msi | Out-Null
    $process = Start-Process msiexec.exe -ArgumentList @('/i', "`"$msi`"", '/passive', '/norestart') -Wait -PassThru
    if ($process.ExitCode -notin @(0, 3010)) { throw "CC Switch 安装失败，代码 $($process.ExitCode)。" }
    Write-Ok 'CC Switch 已安装'
    return $true
}

function Add-CodexMarketplace([string]$PackageRoot, [string[]]$PluginNames) {
    $target = Join-Path $HOME '.codex\marketplaces\codex-easy-start'
    $config = Join-Path $HOME '.codex\config.toml'
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    foreach ($folder in @('.agents', 'plugins')) {
        $managed = Join-Path $target $folder
        Remove-Item -LiteralPath $managed -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item -LiteralPath (Join-Path $PackageRoot $folder) -Destination $managed -Recurse -Force
    }
    if (-not (Test-Path -LiteralPath $config)) { New-Item -ItemType File -Path $config -Force | Out-Null }
    $text = Get-Content -LiteralPath $config -Raw
    if ($text -notmatch '(?m)^# BEGIN CODEX EASY START$') {
        Copy-Item -LiteralPath $config -Destination "$config.easystart.bak" -Force
        $tomlPath = $target.Replace('\', '\\')
        $block = "`r`n# BEGIN CODEX EASY START`r`n[marketplaces.codex-easy-start]`r`nsource_type = `"local`"`r`nsource = `"$tomlPath`"`r`n"
        foreach ($name in $PluginNames) {
            $block += "`r`n[plugins.`"$name@codex-easy-start`"]`r`nenabled = true`r`n"
        }
        $block += '# END CODEX EASY START' + "`r`n"
        Add-Content -LiteralPath $config -Value $block -Encoding UTF8
    } else {
        foreach ($name in $PluginNames) {
            if ($text -notmatch [regex]::Escape("[plugins.`"$name@codex-easy-start`"]")) {
                $insert = "`r`n[plugins.`"$name@codex-easy-start`"]`r`nenabled = true`r`n"
                $text = $text.Replace('# END CODEX EASY START', $insert + '# END CODEX EASY START')
            }
        }
        Set-Content -LiteralPath $config -Value $text -Encoding UTF8
    }
    Write-Ok 'Codex 插件已安装；重启 Codex 后生效'
}

function Set-UserSecret([string]$Name, [string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { throw 'Key 不能为空。' }
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    Set-Item -Path "Env:$Name" -Value $Value
}

function Configure-DeepSeek($Manifest, [string]$WorkDir) {
    Write-Step '配置 DeepSeek'
    Install-CCSwitch $Manifest $WorkDir | Out-Null
    Start-Process 'https://platform.deepseek.com/api_keys'
    Write-Host '浏览器已打开 DeepSeek 开放平台。创建 Key 后回到这里。'
    $key = Read-Secret '请输入 DeepSeek API Key（输入不会显示）'
    if (-not $key) { Write-Skip 'DeepSeek'; return }
    $testBody = @{ model = 'deepseek-chat'; messages = @(@{ role = 'user'; content = '只回复 OK' }); max_tokens = 3 } | ConvertTo-Json -Depth 5
    try {
        $null = Invoke-RestMethod -Method Post -Uri 'https://api.deepseek.com/chat/completions' -Headers @{ Authorization = "Bearer $key" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($testBody))
        Write-Ok 'DeepSeek 连接测试通过'
    } catch { throw "DeepSeek 连接测试失败：$($_.Exception.Message)" }
    $query = @{
        resource = 'provider'; app = 'codex'; name = 'DeepSeek'
        endpoint = 'https://api.deepseek.com'; apiKey = $key; model = 'deepseek-chat'
    }
    $parts = foreach ($item in $query.GetEnumerator()) { "$([Uri]::EscapeDataString($item.Key))=$([Uri]::EscapeDataString([string]$item.Value))" }
    Start-Process ("ccswitch://v1/import?" + ($parts -join '&'))
    Write-Host '请在 CC Switch 弹窗中确认导入；是否启用由您在 CC Switch 中确认。'
    Write-Ok 'DeepSeek 配置已发送到 CC Switch'
    $key = $null
}

function Configure-Ocr([string]$PackageRoot, [string[]]$Plugins) {
    Write-Step '配置图片与扫描件识别'
    Write-Host '让 DeepSeek 等不能直接看图的模型获得识图能力；原生支持图片的模型无需安装。'
    Start-Process 'https://bailian.console.aliyun.com/'
    $key = Read-Secret '请输入百炼 API Key（输入不会显示，直接回车跳过）'
    if (-not $key) { Write-Skip '图片识别'; return $false }
    $pixel = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII='
    $testBody = @{
        model = 'qwen3-vl-plus'; max_tokens = 8
        messages = @(@{ role = 'user'; content = @(
            @{ type = 'image_url'; image_url = @{ url = "data:image/png;base64,$pixel" } }
            @{ type = 'text'; text = '只回复 OK' }
        ) })
    } | ConvertTo-Json -Depth 10
    try {
        $null = Invoke-RestMethod -Method Post -Uri 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions' -Headers @{ Authorization = "Bearer $key" } -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($testBody))
        Write-Ok '图片识别连接测试通过'
    } catch { throw "图片识别连接测试失败：$($_.Exception.Message)" }
    Set-UserSecret 'DASHSCOPE_API_KEY' $key
    Add-CodexMarketplace $PackageRoot (@($Plugins + 'codex-vision-ocr') | Select-Object -Unique)
    Write-Ok '百炼 Key 已保存到当前用户环境变量'
    $key = $null
    return $true
}

function Configure-PKULaw([string]$PackageRoot, [string[]]$Plugins) {
    Write-Step '配置北大法宝'
    $key = Read-Secret '请输入北大法宝 Access Token（直接回车跳过）'
    if (-not $key) { Write-Skip '北大法宝'; return $false }
    $init = @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ protocolVersion = '2025-03-26'; capabilities = @{}; clientInfo = @{ name = 'Codex EasyStart'; version = '1.0.0' } } } | ConvertTo-Json -Depth 8
    try {
        $null = Invoke-RestMethod -Method Post -Uri 'https://apim-gateway.pkulaw.com/mcp-law-search-service' -Headers @{ Authorization = "Bearer $key"; Accept = 'application/json, text/event-stream' } -ContentType 'application/json' -Body ([Text.Encoding]::UTF8.GetBytes($init))
        Write-Ok '北大法宝连接测试通过'
    } catch { throw "北大法宝连接测试失败：$($_.Exception.Message)" }
    Set-UserSecret 'PKULAW_ACCESS_TOKEN' $key
    Add-CodexMarketplace $PackageRoot (@($Plugins + 'codex-legal-tools') | Select-Object -Unique)
    Write-Ok '北大法宝 Token 已保存到当前用户环境变量'
    $key = $null
    return $true
}

function Install-SkillArchive($Manifest, $Skill, [string]$WorkDir) {
    $id = 'skill-' + $Skill.id
    $zip = Join-Path $WorkDir ($Skill.id + '.zip')
    Save-Artifact $Manifest $id $zip | Out-Null
    $unpack = Join-Path $WorkDir ($Skill.id + '-unpack')
    Expand-Archive -LiteralPath $zip -DestinationPath $unpack -Force
    $skillFiles = Get-ChildItem -LiteralPath $unpack -Filter 'SKILL.md' -Recurse -File
    if (-not $skillFiles) { throw "Skill 包中没有 SKILL.md：$($Skill.name)" }
    $destinationRoot = Join-Path $HOME '.agents\skills'
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    foreach ($file in $skillFiles) {
        $sourceDir = $file.Directory.FullName
        $target = Join-Path $destinationRoot $file.Directory.Name
        if (Test-Path -LiteralPath $target) {
            Write-Warn "$($file.Directory.Name) 已存在，未覆盖"
            continue
        }
        Copy-Item -LiteralPath $sourceDir -Destination $target -Recurse -Force
    }
    Write-Ok "$($Skill.name) 已安装"
}

function Configure-Skills($Manifest, [string]$PackageRoot, [string]$WorkDir) {
    $config = Get-Content -LiteralPath (Join-Path $PackageRoot 'config\skills.json') -Raw | ConvertFrom-Json
    $available = @($config.skills | Where-Object { $_.available -and $_.mirrorFile })
    if (-not $available) { Write-Skip '当前没有可合法镜像的 Skills'; return }
    Write-Host "`n可选 Skills："
    for ($i = 0; $i -lt $available.Count; $i++) {
        Write-Host "  $($i + 1). [ ] $($available[$i].name)"
        Write-Host "     $($available[$i].description)" -ForegroundColor DarkGray
    }
    $raw = Read-Host '输入编号（可多选，直接回车跳过）'
    $choices = Read-Choices $raw (1..$available.Count)
    foreach ($choice in $choices) { Install-SkillArchive $Manifest $available[$choice - 1] $WorkDir }
}

function Remove-EasyStart {
    $target = Join-Path $HOME '.codex\marketplaces\codex-easy-start'
    Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue
    $config = Join-Path $HOME '.codex\config.toml'
    if (Test-Path -LiteralPath $config) {
        $text = Get-Content -LiteralPath $config -Raw
        $text = [regex]::Replace($text, '(?ms)^# BEGIN CODEX EASY START\r?\n.*?^# END CODEX EASY START\r?\n?', '')
        Set-Content -LiteralPath $config -Value $text -Encoding UTF8
    }
    Write-Ok 'EasyStart 管理的插件和配置入口已移除；Codex、CC Switch 和用户 Key 未删除。'
}

Export-ModuleMember -Function *
