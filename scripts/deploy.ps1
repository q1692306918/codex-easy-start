param(
    [string]$Server = '154.12.41.190',
    [int]$Port = 48803,
    [string]$Domain = 'plugin.yuniannian.asia',
    [string]$KeyPath = "$HOME\.ssh\codex_easy_start_deploy"
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root 'dist'
$archive = Join-Path $env:TEMP ("codex-easy-start-deploy-$([Guid]::NewGuid().ToString('N')).zip")
$sshOptions = @('-i', $KeyPath, '-p', [string]$Port, '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=yes')

function Invoke-Remote([string]$Script) {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Script))
    & ssh @sshOptions "root@$Server" "echo '$encoded' | base64 -d | bash"
    if ($LASTEXITCODE -ne 0) { throw "远程命令失败，代码 $LASTEXITCODE。" }
}

try {
    if (-not (Test-Path -LiteralPath $KeyPath)) { throw "SSH 私钥不存在：$KeyPath" }
    if (-not (Test-Path -LiteralPath (Join-Path $dist 'manifest.json'))) { throw '缺少 dist，请先运行 scripts/build.ps1。' }
    & tar.exe -a -c -f $archive -C $dist .
    if ($LASTEXITCODE -ne 0) { throw "部署包创建失败，代码 $LASTEXITCODE。" }

    Write-Host '准备服务器...' -ForegroundColor Cyan
    Invoke-Remote @'
set -eu
export DEBIAN_FRONTEND=noninteractive
if command -v apt-get >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq nginx certbot python3-certbot-nginx unzip libnginx-mod-stream
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y nginx certbot python3-certbot-nginx unzip
elif command -v yum >/dev/null 2>&1; then
  yum install -y nginx certbot python3-certbot-nginx unzip
else
  echo "Unsupported package manager" >&2
  exit 2
fi
mkdir -p /var/www/codex-easy-start/releases
if command -v ufw >/dev/null 2>&1; then ufw allow 'Nginx Full' >/dev/null || true; fi
'@

    Write-Host '上传发布包...' -ForegroundColor Cyan
    $scpOptions = @('-i', $KeyPath, '-P', [string]$Port, '-o', 'BatchMode=yes', '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=yes')
    & scp @scpOptions $archive "root@${Server}:/tmp/codex-easy-start.zip"
    if ($LASTEXITCODE -ne 0) { throw "上传失败，代码 $LASTEXITCODE。" }

    $nginxBootstrap = @"
server {
    listen 80;
    listen [::]:80;
    server_name $Domain;
    root /var/www/codex-easy-start/current;

    location = /install.ps1 {
        default_type text/plain;
        charset utf-8;
        add_header Cache-Control "no-store" always;
        try_files `$uri =404;
    }
    location = /manifest.json {
        default_type application/json;
        charset utf-8;
        add_header Cache-Control "no-cache" always;
        try_files `$uri =404;
    }
    location / {
        try_files `$uri `$uri/ =404;
    }
}
"@
    $nginxFinal = @"
server {
    listen 80;
    listen [::]:80;
    server_name $Domain;
    return 301 https://`$host`$request_uri;
}
server {
    listen 127.0.0.1:9443 ssl;
    server_name $Domain;
    root /var/www/codex-easy-start/current;
    ssl_certificate /etc/letsencrypt/live/$Domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$Domain/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location = /install.ps1 {
        default_type text/plain;
        charset utf-8;
        add_header Cache-Control "no-store" always;
        try_files `$uri =404;
    }
    location = /manifest.json {
        default_type application/json;
        charset utf-8;
        add_header Cache-Control "no-cache" always;
        try_files `$uri =404;
    }
    location / {
        try_files `$uri `$uri/ =404;
    }
}
"@
    $stream = @"
stream {
    map `$ssl_preread_server_name `$easystart_backend {
        $Domain 127.0.0.1:9443;
        default 127.0.0.1:8443;
    }
    server {
        listen 443;
        listen [::]:443;
        proxy_connect_timeout 5s;
        proxy_timeout 1h;
        proxy_pass `$easystart_backend;
        ssl_preread on;
    }
}
"@
    $bootstrap64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($nginxBootstrap))
    $final64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($nginxFinal))
    $stream64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($stream))
    $release = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss')
    Invoke-Remote @"
set -eu
release=/var/www/codex-easy-start/releases/$release
mkdir -p "`$release"
unzip -q /tmp/codex-easy-start.zip -d "`$release"
test -f "`$release/install.ps1"
test -f "`$release/manifest.json"
RELEASE="`$release" python3 - <<'PY'
import hashlib, json, os
root = os.environ['RELEASE']
with open(os.path.join(root, 'manifest.json'), encoding='utf-8-sig') as f:
    manifest = json.load(f)
for item in manifest['artifacts']:
    path = os.path.join(root, item['file'])
    with open(path, 'rb') as f:
        digest = hashlib.sha256(f.read()).hexdigest()
    if digest != item['sha256']:
        raise SystemExit('hash mismatch: ' + item['id'])
print('all artifact hashes verified')
PY
ln -sfn "`$release" /var/www/codex-easy-start/current
echo '$bootstrap64' | base64 -d > /etc/nginx/sites-available/codex-easy-start
ln -sfn /etc/nginx/sites-available/codex-easy-start /etc/nginx/sites-enabled/codex-easy-start
nginx -t
systemctl enable --now nginx
systemctl reload nginx
certbot certonly --webroot -w /var/www/codex-easy-start/current -d '$Domain' --cert-name '$Domain' --non-interactive --agree-tos --register-unsafely-without-email --keep-until-expiring

cp -n /usr/local/etc/xray/config.json /usr/local/etc/xray/config.json.easystart.bak || true
XRAY_CONFIG=/usr/local/etc/xray/config.json python3 - <<'PY'
import json, os, tempfile
path = os.environ['XRAY_CONFIG']
with open(path) as f:
    data = json.load(f)
found = False
for inbound in data.get('inbounds', []):
    stream = inbound.get('streamSettings', {})
    if stream.get('security') == 'reality' and inbound.get('port') in (443, 8443):
        inbound['listen'] = '127.0.0.1'
        inbound['port'] = 8443
        found = True
if not found:
    raise SystemExit('xray REALITY inbound not found')
fd, temp = tempfile.mkstemp(dir=os.path.dirname(path))
with os.fdopen(fd, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
os.chmod(temp, 0o644)
os.replace(temp, path)
PY
/usr/local/bin/xray run -test -config /usr/local/etc/xray/config.json

mkdir -p /etc/nginx/streams-enabled
grep -qxF 'include /etc/nginx/streams-enabled/*.conf;' /etc/nginx/nginx.conf || echo 'include /etc/nginx/streams-enabled/*.conf;' >> /etc/nginx/nginx.conf
echo '$final64' | base64 -d > /etc/nginx/sites-available/codex-easy-start
echo '$stream64' | base64 -d > /etc/nginx/streams-enabled/easystart-sni.conf
nginx -t
systemctl restart xray
systemctl restart nginx
test "`$(systemctl is-active xray)" = active
test "`$(systemctl is-active nginx)" = active
curl -fsS --resolve '${Domain}:443:127.0.0.1' 'https://$Domain/manifest.json' >/dev/null
curl -fsS --resolve '${Domain}:443:127.0.0.1' 'https://$Domain/install.ps1' >/dev/null
"@
    Write-Host "部署完成：https://$Domain" -ForegroundColor Green
} finally {
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
}
