# 部署

生产入口是 `https://plugin.yuniannian.asia`。部署使用本机专用 SSH 私钥，不在仓库中保存服务器密码或私钥：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/deploy.ps1
```

`deploy.ps1` 会完成以下工作：

1. 使用跨平台 ZIP 上传 `dist/`。
2. 在服务器逐项复算 `manifest.json` 中的 SHA-256。
3. 把新版本解压到独立 release 目录，再原子切换 `current` 软链接。
4. 使用 Certbot webroot 模式申请或续期证书。
5. 在 443 端口按 TLS SNI 分流：本站进入 Nginx 内部 TLS 端口，其他流量保持转发到服务器既有 xray REALITY 服务。
6. 验证 Nginx、xray、清单和安装脚本后才报告成功。

站点发布目录为 `/var/www/codex-easy-start/releases/`，当前版本由 `/var/www/codex-easy-start/current` 指向。Nginx 站点和 SNI 分流配置分别位于：

```text
/etc/nginx/sites-available/codex-easy-start
/etc/nginx/streams-enabled/easystart-sni.conf
```

服务器首次迁移 xray 监听端口时会保留 `/usr/local/etc/xray/config.json.easystart.bak`。

