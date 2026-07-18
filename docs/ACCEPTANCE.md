# Windows 验收清单

在一台未配置开发环境的 Windows 10/11 机器上验证：

1. 执行 `irm https://plugin.yuniannian.asia/install.ps1 | iex`。
2. 确认不要求安装 Node.js、Python、.NET SDK 或 Codex CLI。
3. 分别验证全新安装、已有 Codex、已有 CC Switch、重复运行四种路径。
4. 断开境外网络后，确认 EasyStart、CC Switch、插件和可镜像 Skills 仍从域名成功下载并通过哈希校验。
5. 确认 Codex 未安装时明确提示微软联网限制，并说明官方包在 Windows 中显示为 ChatGPT、其中包含 Codex。
6. 确认安装流程不再下载或执行 `ChatGPT-Installer.exe`；优先使用 Microsoft Store 命令安装，失败时才打开商店页面。
7. DeepSeek 路径中确认 Key 输入不回显，CC Switch 显示导入确认。
8. OCR 使用测试图片完成一次真实识别；原生多模态提示可跳过。
9. 北大法宝完成一次最小检索调用。
10. 重启 Codex，确认已选插件和 Skills 可见。
11. 检查 `%LOCALAPPDATA%\CodexEasyStart\logs`，确认无 API Key。
