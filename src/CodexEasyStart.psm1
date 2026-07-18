Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Text) { Write-Host "`n$Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "  [完成] $Text" -ForegroundColor Green }
function Write-Skip([string]$Text) { Write-Host "  [跳过] $Text" -ForegroundColor DarkGray }
function Write-Warn([string]$Text) { Write-Host "  [注意] $Text" -ForegroundColor Yellow }

function Test-SupportedWindows {
    return ($env:OS -eq 'Windows_NT' -and [Environment]::OSVersion.Version.Major -ge 10)
}

function Get-CodexDesktopPackage {
    $package = Get-AppxPackage -Name 'OpenAI.Codex' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $package) { return $null }
    $manifestPath = Join-Path $package.InstallLocation 'AppxManifest.xml'
    if (-not (Test-Path -LiteralPath $manifestPath)) { return $null }
    $manifestText = Get-Content -LiteralPath $manifestPath -Raw
    if ($manifestText -notmatch '<uap:Protocol\s+Name="codex"') { return $null }
    return $package
}

function Resolve-CCSwitchExecutable([string[]]$Candidates, [object[]]$UninstallEntries) {
    foreach ($candidate in $Candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return (Get-Item -LiteralPath $candidate).FullName
        }
    }
    foreach ($entry in $UninstallEntries) {
        $displayNameProperty = $entry.PSObject.Properties['DisplayName']
        if (-not $displayNameProperty -or [string]$displayNameProperty.Value -notmatch '^CC Switch(?:\s|$)') { continue }
        $installLocationProperty = $entry.PSObject.Properties['InstallLocation']
        $installLocation = if ($installLocationProperty) { ([string]$installLocationProperty.Value).Trim().Trim('"') } else { '' }
        if ($installLocation) {
            $installedExe = Join-Path $installLocation 'cc-switch.exe'
            if (Test-Path -LiteralPath $installedExe) { return (Get-Item -LiteralPath $installedExe).FullName }
        }
        $displayIconProperty = $entry.PSObject.Properties['DisplayIcon']
        $displayIcon = if ($displayIconProperty) { ([string]$displayIconProperty.Value).Trim().Trim('"') -replace ',\d+$', '' } else { '' }
        if ($displayIcon -and (Test-Path -LiteralPath $displayIcon)) {
            return (Get-Item -LiteralPath $displayIcon).FullName
        }
    }
    return $null
}

function Get-CCSwitchUninstallEntries {
    $paths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    return @(Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue)
}

function Get-EasyStartState {
    $codex = Get-CodexDesktopPackage
    $ccCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'CC-Switch\cc-switch.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\CC Switch\cc-switch.exe'),
        (Join-Path $env:ProgramFiles 'CC Switch\cc-switch.exe')
    )
    $cc = Resolve-CCSwitchExecutable -Candidates $ccCandidates -UninstallEntries (Get-CCSwitchUninstallEntries)
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
    $response = Invoke-WebRequest -UseBasicParsing -Uri "$BaseUrl/manifest.json"
    return $response.Content | ConvertFrom-Json
}

function Get-DownloadRanges([long]$Size, [int]$Count = 4) {
    if ($Size -le 0) { throw '文件大小必须大于 0。' }
    $actualCount = [Math]::Min($Count, [int]$Size)
    $chunkSize = [long][Math]::Ceiling($Size / [double]$actualCount)
    $ranges = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $actualCount; $i++) {
        $start = [long]$i * $chunkSize
        if ($start -ge $Size) { break }
        $end = [Math]::Min($Size - 1, $start + $chunkSize - 1)
        $ranges.Add([pscustomobject]@{ Index = $i; Start = $start; End = $end; Length = $end - $start + 1 })
    }
    return $ranges.ToArray()
}

function Save-ParallelDownload([string]$Uri, [string]$Destination, [long]$Size) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if (-not $curl) {
        Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $Destination
        return
    }
    $ranges = @(Get-DownloadRanges $Size 4)
    $processes = New-Object System.Collections.Generic.List[object]
    $parts = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($range in $ranges) {
            $part = "$Destination.part$($range.Index)"
            $parts.Add($part)
            $arguments = "--fail --silent --show-error --location --range $($range.Start)-$($range.End) --output `"$part`" `"$Uri`""
            $processes.Add((Start-Process -FilePath $curl.Source -ArgumentList $arguments -WindowStyle Hidden -PassThru))
        }

        while (@($processes | Where-Object { -not $_.HasExited }).Count -gt 0) {
            $downloaded = 0L
            foreach ($part in $parts) {
                if (Test-Path -LiteralPath $part) { $downloaded += (Get-Item -LiteralPath $part).Length }
            }
            $percent = [Math]::Min(99, [int](100 * $downloaded / $Size))
            Write-Progress -Activity '正在下载' -Status "$percent%" -PercentComplete $percent
            Start-Sleep -Milliseconds 250
        }

        foreach ($process in $processes) {
            $process.Refresh()
            if ($process.ExitCode -ne 0) { throw "分段下载失败，curl 退出代码：$($process.ExitCode)" }
        }
        for ($i = 0; $i -lt $ranges.Count; $i++) {
            if (-not (Test-Path -LiteralPath $parts[$i]) -or (Get-Item -LiteralPath $parts[$i]).Length -ne $ranges[$i].Length) {
                throw "下载分段长度不正确：$i"
            }
        }

        $output = [IO.File]::Create($Destination)
        try {
            foreach ($part in $parts) {
                $input = [IO.File]::OpenRead($part)
                try { $input.CopyTo($output) } finally { $input.Dispose() }
            }
        } finally { $output.Dispose() }
        Write-Progress -Activity '正在下载' -Completed
    } finally {
        foreach ($process in $processes) {
            if (-not $process.HasExited) { $process.Kill() }
            $process.Dispose()
        }
        foreach ($part in $parts) { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
    }
}

function Save-Artifact($Manifest, [string]$Id, [string]$Destination) {
    $artifact = $Manifest.artifacts | Where-Object { $_.id -eq $Id } | Select-Object -First 1
    if (-not $artifact) { throw "镜像中没有制品：$Id" }
    Write-Host "  正在下载 $Id（$([Math]::Round([long]$artifact.size / 1MB, 1)) MB）..."
    $parent = Split-Path -Parent $Destination
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if ([long]$artifact.size -ge 4MB) {
        Save-ParallelDownload -Uri $artifact.url -Destination $Destination -Size ([long]$artifact.size)
    } else {
        Invoke-WebRequest -UseBasicParsing -Uri $artifact.url -OutFile $Destination
    }
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
    Write-Warn 'Codex 已改名为 ChatGPT；本步骤需要连接 Microsoft Store。'
    $answer = Read-Host '继续安装 ChatGPT（原 Codex）？[Y/n]'
    if ($answer -match '^[Nn]') { Write-Skip 'Codex'; return $false }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($winget) {
        Write-Host '  正在通过 Microsoft Store 安装 OpenAI 官方桌面包...'
        & $winget.Source install --id 9PLM9XGG6VKS --source msstore --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            Write-Warn "Microsoft Store 命令安装未完成（代码 $LASTEXITCODE），将打开商店页面。"
        }
    }

    $installed = (Get-EasyStartState).CodexInstalled
    if (-not $installed) {
        Start-Process 'ms-windows-store://pdp/?ProductId=9PLM9XGG6VKS'
        Write-Host '请在 Microsoft Store 完成 ChatGPT（原 Codex）安装。'
        Read-Host '安装完成后回到这里按回车继续' | Out-Null
        $installed = (Get-EasyStartState).CodexInstalled
    }
    if ($installed) { Write-Ok 'Codex 已安装' } else { Write-Warn '尚未检测到 Codex，可稍后再次运行 EasyStart 检查。' }
    return $installed
}

function Open-CodexDesktop {
    try { Start-Process 'codex:' -ErrorAction Stop }
    catch { Start-Process explorer.exe -ArgumentList 'shell:AppsFolder\OpenAI.Codex_2p2nqsd0c76g0!App' -ErrorAction SilentlyContinue }
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

function Get-CCSwitchCurrentCodexProviderId {
    $settingsPath = Join-Path $HOME '.cc-switch\settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) { return $null }
    try {
        $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
        $property = $settings.PSObject.Properties['currentProviderCodex']
        if ($property) { return [string]$property.Value }
    } catch { return $null }
    return $null
}

function Get-CCSwitchCodexRouteEndpoint([string]$ConfigPath = (Join-Path $HOME '.codex\config.toml')) {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $null }
    $config = Get-Content -LiteralPath $ConfigPath -Raw
    $match = [regex]::Match($config, '(?m)^\s*base_url\s*=\s*"(http://(?:127\.0\.0\.1|localhost):(\d+)/v1)"\s*$')
    if (-not $match.Success) { return $null }
    return [pscustomobject]@{ BaseUrl = $match.Groups[1].Value; Port = [int]$match.Groups[2].Value }
}

function Confirm-CCSwitchCodexRoute([string]$CCSwitchPath) {
    Write-Host "`n请在 CC Switch 完成以下设置："
    Write-Host '  1. 确认导入 DeepSeek，并将 API 格式设为 OpenAI Chat Completions（需开启路由）'
    Write-Host '  2. 打开 设置 > 路由 > 本地路由'
    Write-Host '  3. 打开路由总开关，并在路由启用中打开 Codex'
    if ($CCSwitchPath -and -not (Get-Process -Name 'cc-switch' -ErrorAction SilentlyContinue)) {
        Start-Process -FilePath $CCSwitchPath
    }
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        Read-Host '完成后回到这里按回车验证' | Out-Null
        $route = Get-CCSwitchCodexRouteEndpoint
        if ($route) {
            try {
                $health = Invoke-WebRequest -UseBasicParsing -Uri ("http://127.0.0.1:{0}/health" -f $route.Port) -TimeoutSec 3
                if ($health.StatusCode -eq 200) {
                    Write-Ok "CC Switch 本地路由已运行（$($route.BaseUrl)）"
                    return $true
                }
            } catch { }
        }
        if ($attempt -lt 3) { Write-Warn '尚未检测到 Codex 本地路由，请检查两个路由开关后重试。' }
    }
    throw '未检测到 CC Switch 的 Codex 本地路由，DeepSeek 配置尚未完成。'
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
    $beforeProviderId = Get-CCSwitchCurrentCodexProviderId
    $query = @{
        resource = 'provider'; app = 'codex'; name = 'DeepSeek'
        endpoint = 'https://api.deepseek.com'; apiKey = $key; model = 'deepseek-chat'
        homepage = 'https://platform.deepseek.com'; icon = 'deepseek'; enabled = 'true'
    }
    $parts = foreach ($item in $query.GetEnumerator()) { "$([Uri]::EscapeDataString($item.Key))=$([Uri]::EscapeDataString([string]$item.Value))" }
    Start-Process ("ccswitch://v1/import?" + ($parts -join '&'))
    Write-Host 'CC Switch 已打开官方导入确认框；确认后会把 DeepSeek 设为当前 Provider。'
    Read-Host '确认导入后回到这里按回车继续' | Out-Null
    $afterProviderId = Get-CCSwitchCurrentCodexProviderId
    if (-not $afterProviderId -or $afterProviderId -eq $beforeProviderId) {
        throw '未检测到新的 DeepSeek Provider，请在 CC Switch 中确认导入后重试。'
    }
    Write-Ok 'DeepSeek Provider 已由 CC Switch 导入并启用'
    $ccSwitchPath = (Get-EasyStartState).CCSwitchPath
    Confirm-CCSwitchCodexRoute -CCSwitchPath $ccSwitchPath | Out-Null
    Write-Ok 'DeepSeek 已通过 CC Switch 本地路由应用到 ChatGPT（原 Codex）'
    $key = $null
}

function Configure-Ocr([string]$PackageRoot, [string[]]$Plugins) {
    Write-Step '配置图片与扫描件识别'
    Write-Host '让 DeepSeek 等不能直接看图的模型获得识图能力；原生支持图片的模型无需安装。'
    $key = [Environment]::GetEnvironmentVariable('DASHSCOPE_API_KEY', 'User')
    if ($key -and (Read-Host '检测到已保存的百炼 API Key，继续沿用？[Y/n]') -notmatch '^[Nn]') {
        Write-Host '将沿用已保存的百炼 API Key。'
    } else {
        Start-Process 'https://bailian.console.aliyun.com/'
        $key = Read-Secret '请输入百炼 API Key（输入不会显示，直接回车跳过）'
    }
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
    $key = [Environment]::GetEnvironmentVariable('PKULAW_ACCESS_TOKEN', 'User')
    if ($key -and (Read-Host '检测到已保存的北大法宝 Token，继续沿用？[Y/n]') -notmatch '^[Nn]') {
        Write-Host '将沿用已保存的北大法宝 Token。'
    } else {
        $key = Read-Secret '请输入北大法宝 Access Token（直接回车跳过）'
    }
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

function Expand-SingleSkillArchive([string]$Zip, [string]$Target, [string]$Name) {
    if (Test-Path -LiteralPath $Target) { throw "$Name 已存在，未覆盖。" }
    $destinationRoot = Split-Path -Parent $Target
    New-Item -ItemType Directory -Path $destinationRoot -Force | Out-Null
    $staging = Join-Path $destinationRoot ('.easystart-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    try {
        $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
        if (-not $tar) { throw '系统缺少 tar.exe，请确认正在使用 Windows 10/11。' }
        & $tar.Source -xf $Zip -C $staging --strip-components 1
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $staging 'SKILL.md'))) {
            throw "Skill 解压失败：$Name"
        }
        [IO.Directory]::Move($staging, $Target)
    } finally {
        if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Install-SkillArchive($Manifest, $Skill, [string]$WorkDir) {
    $destinationRoot = Join-Path $HOME '.agents\skills'
    $target = Join-Path $destinationRoot ([string]$Skill.name)
    if (Test-Path -LiteralPath $target) {
        Write-Warn "$($Skill.name) 已存在，未覆盖"
        return
    }
    $id = 'skill-' + $Skill.id
    $zip = Join-Path $WorkDir ($Skill.id + '.zip')
    Save-Artifact $Manifest $id $zip | Out-Null
    Expand-SingleSkillArchive -Zip $zip -Target $target -Name ([string]$Skill.name)
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
