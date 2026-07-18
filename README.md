# Codex EasyStart

面向 Windows 普通用户的一条命令安装与配置工具：

```powershell
irm https://plugin.yuniannian.asia/install.ps1 | iex
```

它会检测现有 Codex 和 CC Switch，并按需安装 DeepSeek 配置、图片识别、北大法宝和法律 Skills。所有可再分发制品都由境内域名提供并校验 SHA-256，不依赖用户访问 GitHub。

Codex 桌面端的官方完整离线包目前不可公开取得；未安装 Codex 时会启动已镜像的官方 Microsoft Store 安装器，该一步仍可能需要微软网络。

开发与发布说明见 [制品文档](docs/ARTIFACTS.md) 和 [部署文档](docs/DEPLOYMENT.md)，人工验收见 [验收清单](docs/ACCEPTANCE.md)。
