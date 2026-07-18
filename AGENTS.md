# AI 协作规则

本仓库交付 Codex EasyStart。面向用户的说明使用中文；代码标识、命令和路径保持 ASCII。

## 开始工作前

1. 阅读 `PRODUCT.md`、`DESIGN.md` 和 `docs/ARTIFACTS.md`。
2. 检查 Git 状态，保留用户已有改动。
3. 密码、Cookie、访问令牌和 API Key 不得写入仓库、日志或命令历史。

## 工程约束

- 仅支持 Windows 10/11 和 Windows PowerShell 5.1+。
- 用户入口固定为 `irm https://plugin.yuniannian.asia/install.ps1 | iex`。
- 运行时下载必须使用 `config/artifacts.json` 中的境内镜像，并校验 SHA-256。
- 每个制品必须记录版本、来源、许可证和 `offlineReady`；不得把联网启动器描述成离线安装包。
- 不覆盖既有 Codex、CC Switch 或用户配置；修改前备份，失败时可恢复。
- API Key 仅在本机隐藏输入，保存到用户环境变量或目标工具配置，不进入日志。
- 修改代码后运行 `powershell -NoProfile -ExecutionPolicy Bypass -File tests/run.ps1` 和 `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1`。

