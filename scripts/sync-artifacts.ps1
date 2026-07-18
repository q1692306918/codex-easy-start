param(
    [string]$GitHubProxy = 'https://gh-proxy.com/',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = Split-Path -Parent $PSScriptRoot
$vendor = Join-Path $root 'vendor'
New-Item -ItemType Directory -Path (Join-Path $vendor 'artifacts') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $vendor 'skills') -Force | Out-Null

function Save-Remote([string]$Uri, [string]$Path, [string]$ExpectedHash) {
    if ($Force -or -not (Test-Path -LiteralPath $Path)) {
        Write-Host "下载 $Uri"
        $downloadUri = if ($Uri.StartsWith('https://github.com/')) { $GitHubProxy + $Uri } else { $Uri }
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $downloadUri -OutFile $Path
        } catch {
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
            $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
            if (-not $curl) { throw }
            & $curl.Source --fail --location --retry 3 --output $Path $downloadUri
            if ($LASTEXITCODE -ne 0) { throw "下载失败：$Uri" }
        }
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($ExpectedHash -and $hash -ne $ExpectedHash.ToLowerInvariant()) {
        throw "SHA-256 不匹配：$Path"
    }
    Write-Host "已核验 $([IO.Path]::GetFileName($Path))  $hash"
}

Save-Remote 'https://github.com/farion1231/cc-switch/releases/download/v3.17.0/CC-Switch-v3.17.0-Windows.msi' `
    (Join-Path $vendor 'artifacts\CC-Switch-v3.17.0-Windows.msi') `
    'c541e1981023cc5cfe4d8357ce9c57a712eb8949bf2ae8cd49b087c75762607b'
Save-Remote 'https://github.com/farion1231/cc-switch/releases/download/v3.17.0/CC-Switch-v3.17.0-Windows-arm64.msi' `
    (Join-Path $vendor 'artifacts\CC-Switch-v3.17.0-Windows-arm64.msi') `
    'e3b5c01d4d12914f3f98f715d386aeddb9ceaa39981984cb05f3050163933b6e'

Save-Remote 'https://github.com/Daknniel-0881/qulv-china-legal-counsel-skill/archive/73ff53a857ffbdd91296bf41ed5bcc1294bc2042.zip' `
    (Join-Path $vendor 'skills\china-legal-counsel.zip') `
    '89ac5490e51ea875c3ed822f4a949463b4e2a90fadbe49d9290d0f8e843fee2a'
Save-Remote 'https://github.com/op7418/Humanizer-zh/archive/91f3d394db8419c20d67ebe22a96cf8fee0a404b.zip' `
    (Join-Path $vendor 'skills\humanizer-zh.zip') `
    '62c1c28f45341e7be9772d49ad3d3e8588112c62612411c8ed5ced1b38d58622'

Write-Host '上游制品同步完成。' -ForegroundColor Green
