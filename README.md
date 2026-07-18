# Codex EasyStart

面向 Windows 普通用户的一条命令安装与配置工具：

```powershell
irm https://plugin.yuniannian.asia/install.ps1 | iex
```

它会检测现有 Codex 和 CC Switch，并按需安装 DeepSeek 配置、图片识别、北大法宝和法律 Skills。所有可再分发制品都由境内域名提供并校验 SHA-256，不依赖用户访问 GitHub。

Codex 已改名为 ChatGPT。未安装时，EasyStart 会通过 Microsoft Store 安装 ChatGPT；这一步仍需要微软网络，但不会再运行容易重定向失败的 Store Installer EXE。

开发与发布说明见 [制品文档](docs/ARTIFACTS.md) 和 [部署文档](docs/DEPLOYMENT.md)，人工验收见 [验收清单](docs/ACCEPTANCE.md)。
