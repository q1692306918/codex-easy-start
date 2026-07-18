# Codex EasyStart

Codex EasyStart 面向没有开发环境经验、也可能无法访问境外网站的 Windows 用户。它用一条 PowerShell 命令完成 Codex 桌面端、CC Switch、可选插件和 Skills 的检测、安装与修复。

## 用户承诺

- 所有由本项目分发的运行时文件均从 `plugin.yuniannian.asia` 下载。
- 安装器在执行文件前验证 SHA-256。
- 已安装组件和既有配置默认保留。
- DeepSeek、OCR、北大法宝和 Skills 都是可选项。
- 不收集遥测；日志只保存在本机且不记录 API Key。

## 能力选项

- 使用 DeepSeek：安装或复用 CC Switch，打开 DeepSeek 官方平台获取 Key，并由 CC Switch 确认导入。
- 识别图片和扫描件：让 DeepSeek 等不能直接看图的模型获得识图能力；原生支持图片的模型无需安装。
- 增强法律工作能力：可独立配置北大法宝 MCP，并选择法律 Skills。

## 已知限制

Codex 桌面应用目前没有可公开取得并合法镜像的完整离线安装包。项目镜像官方 Microsoft Store 启动器，但首次安装仍可能需要访问微软服务。该制品必须标记为 `offlineReady: false`。

