param()

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)

function Send-JsonRpc($Value) {
    $json = $Value | ConvertTo-Json -Depth 20 -Compress
    [Console]::Out.WriteLine($json)
    [Console]::Out.Flush()
}

function Get-MimeType([string]$Path) {
    switch ([IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.webp' { 'image/webp' }
        '.gif'  { 'image/gif' }
        default { throw '仅支持 PNG、JPEG、WEBP 和 GIF 图片。' }
    }
}

function Invoke-Ocr([string]$Path, [string]$Prompt) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "图片不存在：$Path" }
    $apiKey = [Environment]::GetEnvironmentVariable('DASHSCOPE_API_KEY', 'User')
    if (-not $apiKey) { $apiKey = $env:DASHSCOPE_API_KEY }
    if (-not $apiKey) { throw '未配置 DASHSCOPE_API_KEY，请重新运行 EasyStart 配置百炼。' }

    $mime = Get-MimeType $Path
    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path))
    $dataUrl = "data:$mime;base64,$([Convert]::ToBase64String($bytes))"
    if (-not $Prompt) { $Prompt = '请准确识别图片中的文字、表格和版面结构，并用中文输出。' }
    $body = @{
        model = 'qwen3-vl-plus'
        messages = @(@{
            role = 'user'
            content = @(
                @{ type = 'image_url'; image_url = @{ url = $dataUrl } }
                @{ type = 'text'; text = $Prompt }
            )
        })
    } | ConvertTo-Json -Depth 12
    $headers = @{ Authorization = "Bearer $apiKey" }
    $result = Invoke-RestMethod -Method Post -Uri 'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions' -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
    return [string]$result.choices[0].message.content
}

while ($null -ne ($line = [Console]::In.ReadLine())) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try {
        $request = $line | ConvertFrom-Json
        $response = [ordered]@{ jsonrpc = '2.0'; id = $request.id }
        switch ($request.method) {
            'initialize' {
                $response.result = @{ protocolVersion = '2025-03-26'; capabilities = @{ tools = @{} }; serverInfo = @{ name = 'easystart-ocr'; version = '1.0.0' } }
            }
            'notifications/initialized' { continue }
            'tools/list' {
                $response.result = @{ tools = @(@{
                    name = 'recognize_image'
                    description = '识别本地图片或扫描件中的文字、表格和版面结构。'
                    inputSchema = @{
                        type = 'object'
                        properties = @{
                            path = @{ type = 'string'; description = '本地图片绝对路径' }
                            prompt = @{ type = 'string'; description = '可选的识别要求' }
                        }
                        required = @('path')
                    }
                }) }
            }
            'tools/call' {
                if ($request.params.name -ne 'recognize_image') { throw '未知工具。' }
                $text = Invoke-Ocr -Path ([string]$request.params.arguments.path) -Prompt ([string]$request.params.arguments.prompt)
                $response.result = @{ content = @(@{ type = 'text'; text = $text }); isError = $false }
            }
            default { $response.error = @{ code = -32601; message = 'Method not found' } }
        }
        Send-JsonRpc $response
    } catch {
        Send-JsonRpc ([ordered]@{ jsonrpc = '2.0'; id = $request.id; error = @{ code = -32000; message = $_.Exception.Message } })
    }
}

